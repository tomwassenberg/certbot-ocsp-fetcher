#!/usr/bin/env bash

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

exit_with_error() {
  echo 1>&2 "${@}"
  exit 1
}

print_usage() {
  exit_with_error \
    "USAGE: ${0} [-c/--certbot-dir DIRECTORY]"\
    "[-o/--output-dir DIRECTORY]"
}
parse_cli_arguments() {
  while [[ ${#} -gt 1 ]]
    do
      local PARAMETER="${1}"; shift

      case ${PARAMETER} in
        -o|--output-dir)
          OUTPUT_DIR="$(readlink -fn -- "${1}")"; shift
          ;;
        -c|--certbot-dir)
          CERTBOT_DIR="$(readlink -fn -- "${1}")"; shift
          ;;
        *)
          print_usage
          ;;
      esac
    done

  if [[ ${#} == 1 ]]; then
    print_usage
  fi
}

# Set output directory if necessary and check if it's writeable
prepare_output_dir() {
  if [[ -n ${OUTPUT_DIR+x} ]]; then
    if [[ ! -e ${OUTPUT_DIR} ]]; then
      # Try to create output directory, but don't yet fail if not possible
      mkdir -p -- "${OUTPUT_DIR}" || true
    fi
  else
    readonly OUTPUT_DIR="/etc/nginx/ocsp-cache"
  fi

  if [[ ! -w ${OUTPUT_DIR} ]]; then
    exit_with_error \
      "ERROR: You don't have write access to"\
      "the output directory (\"${OUTPUT_DIR}\")."\
      "Specify another folder using the -o/--output-dir"\
      "flag or create the folder manually with permissions"\
      "that allow it to be writeable for the current user."
  fi
}

# Determine operation mode
process_certificates() {
  # Create temporary directory to store OCSP response,
  # before having checked the certificate status therein
  local -r TEMP_OUTPUT_DIR="$(mktemp -d)"

  # These two environment variables are set if this script is invoked by Certbot
  if [[ -z ${RENEWED_DOMAINS+x} || -z ${RENEWED_LINEAGE+x} ]]; then
    run_standalone "${TEMP_OUTPUT_DIR}"
  else
    run_as_deploy_hook "${TEMP_OUTPUT_DIR}"
  fi
}

# Run in "check every certificate" mode
# $1 - Path to temporary output directory
run_standalone() {
  local -r TEMP_OUTPUT_DIR="${1}"
  readonly CERTBOT_DIR="${CERTBOT_DIR:-/etc/letsencrypt}"

  if [[ -r "${CERTBOT_DIR}/live" ]]; then
    local LINEAGES; LINEAGES=$(ls "${CERTBOT_DIR}/live"); readonly LINEAGES
    for CERT_NAME in ${LINEAGES}
    do
      fetch_ocsp_response \
        "--standalone" "${CERT_NAME}" "${TEMP_OUTPUT_DIR}" 1>/dev/null
    done
    unset CERT_NAME
  else
    exit_with_error \
      "ERROR: Certificate folder does not exist, or you don't have read access!"
  fi

  reload_nginx_and_print_result
}

# Run in Certbot mode, only checking the passed certificate
# $1 - Path to temporary output directory
run_as_deploy_hook() {
  local -r TEMP_OUTPUT_DIR="${1}"

  if [[ -n ${CERTBOT_DIR+x} ]]; then
    exit_with_error \
      "ERROR: The -c/--certbot-dir parameter is not applicable"\
      "when Certbot is used as a Certbot hook, because the directory"
      "is already inferred from the call that Certbot makes."
  fi

  fetch_ocsp_response \
    "--deploy_hook" "${RENEWED_LINEAGE##*/}" "${TEMP_OUTPUT_DIR}" 1>/dev/null

  reload_nginx_and_print_result
}

# Generate file used by ssl_stapling_file in nginx config of websites
# $1 - Whether to run as a deploy hook for Certbot, or standalone
# $2 - Name of certificate lineage
# $3 - Path to temporary output directory
fetch_ocsp_response() {
  case ${1} in
    --standalone)
      local -r CERT_DIR="${CERTBOT_DIR}/live/${CERT_NAME}"
      ;;
    --deploy_hook)
      local -r CERT_DIR="${RENEWED_LINEAGE}"
      ;;
  esac
  local -r CERT_NAME="${2}";
  local -r TEMP_OUTPUT_DIR="${3}"
  shift; shift; shift

  local -r OCSP_ENDPOINT="$(openssl x509 -noout -ocsp_uri -in \
    "${CERT_DIR}/cert.pem")"
  local -r OCSP_HOST="${OCSP_ENDPOINT#*://}"

  # Request, verify and temporarily save the actual OCSP response,
  # and check whether the certificate status is "good"
  openssl ocsp \
    -no_nonce \
    -url "${OCSP_ENDPOINT}" \
    -header "Host" "${OCSP_HOST}" \
    -issuer "${CERT_DIR}/chain.pem" \
    -cert "${CERT_DIR}/cert.pem" \
    -verify_other "${CERT_DIR}/chain.pem" \
    -respout "${TEMP_OUTPUT_DIR}/${CERT_NAME}.der" \
    2>/dev/null | grep -q "^${CERT_DIR}/cert.pem: good$"

  # If arrived here status was good, so move OCSP response to definitive folder
  mv "${TEMP_OUTPUT_DIR}/${CERT_NAME}.der" "${OUTPUT_DIR}/"
}

reload_nginx_and_print_result() {
  # Reload nginx to cache the new OCSP responses in memory
  if pgrep -fu "${EUID}" 'nginx: master process' > /dev/null; then
    /usr/sbin/service nginx reload
    echo \
      "Fetching of OCSP response(s) successful!"\
      "nginx is reloaded to cache any new responses."
  else
    echo \
      "Fetching of OCSP responses successful!"\
      "WARNING: Script is run without root privileges, so nginx has to be"\
      "manually restarted to cache the new OCSP responses in memory."
  fi
}

main() {
  parse_cli_arguments "${@}"

  prepare_output_dir

  process_certificates
}

main "${@}"
