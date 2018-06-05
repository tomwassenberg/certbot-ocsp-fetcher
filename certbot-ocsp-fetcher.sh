#!/usr/bin/env bash

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

SEPARATION_BAR="--------------------------------------------------------------"
exit_with_error() {
  echo 1>&2 "${@}"
  exit 1
}

print_usage() {
  exit_with_error \
    "USAGE: ${0} [-c/--certbot-dir DIRECTORY]"\
    "[-n/--cert-name CERTNAME]"\
    "[-o/--output-dir DIRECTORY]"
}
parse_cli_arguments() {
  while [[ ${#} -gt 1 ]]
    do
      local PARAMETER="${1}"; shift

      case ${PARAMETER} in
        -c|--certbot-dir)
          CERTBOT_DIR="$(readlink -fn -- "${1}")"; shift
          ;;
        -n|--cert-name)
          CERT_LINEAGE="${1}"; shift
          ;;
        -o|--output-dir)
          OUTPUT_DIR="$(readlink -fn -- "${1}")"; shift
          ;;
        *)
          print_usage
          ;;
      esac
    done

   # All CLI parameters require a value, so a single argument is always invalid
  if [[ ${#} == 1 ]]; then
    print_usage
  fi
}

# Set output directory if necessary and check if it's writeable
prepare_output_dir() {
  if [[ -n ${OUTPUT_DIR:-} ]]; then
    if [[ ! -e ${OUTPUT_DIR} ]]; then
      # Don't yet fail if it's not possible to create the directory, so we can
      # exit with a custom error down below
      mkdir -p -- "${OUTPUT_DIR}" || true
    fi
  else
    readonly OUTPUT_DIR="."
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

start_in_correct_mode() {
  # Create temporary directory to store OCSP response,
  # before having checked the certificate status therein
  local TEMP_OUTPUT_DIR
  TEMP_OUTPUT_DIR="$(mktemp -d)"

  # These two environment variables are set if this script is invoked by Certbot
  if [[ -z ${RENEWED_DOMAINS:-} || -z ${RENEWED_LINEAGE:-} ]]; then
    run_standalone "${TEMP_OUTPUT_DIR}"
  else
    run_as_deploy_hook "${TEMP_OUTPUT_DIR}"
  fi

  print_and_handle_result
}

# Run in "check one or all certificate lineage(s) managed by Certbot" mode
# $1 - Path to temporary output directory
run_standalone() {
  local -r TEMP_OUTPUT_DIR="${1}"
  readonly CERTBOT_DIR="${CERTBOT_DIR:-/etc/letsencrypt}"

  if [[ ! -r "${CERTBOT_DIR}/live" ]]; then
    exit_with_error \
      "ERROR: Certificate folder does not exist, or you don't have read access!"
  fi

  # Check specific lineage if passed on CLI,
  # or otherwise all lineages in Certbot's dir
  if [[ -n "${CERT_LINEAGE:-}" ]]; then
    fetch_ocsp_response \
      "--standalone" "${CERT_LINEAGE}" "${TEMP_OUTPUT_DIR}"
  else
    set +f; shopt -s nullglob
    for CERT_NAME in ${CERTBOT_DIR}/live/*
    do
      fetch_ocsp_response \
        "--standalone" "$(basename "${CERT_NAME}")" "${TEMP_OUTPUT_DIR}"
    done
    set -f
    unset CERT_NAME
  fi
}

# Run in deploy-hook mode, only checking the passed certificate
# $1 - Path to temporary output directory
run_as_deploy_hook() {
  local -r TEMP_OUTPUT_DIR="${1}"

  if [[ -n ${CERTBOT_DIR:-} ]]; then
    exit_with_error \
      "ERROR: The -c/--certbot-dir parameter is not applicable"\
      "when Certbot is used as a Certbot hook, because the directory"
      "is already inferred from the call that Certbot makes."
  fi

  fetch_ocsp_response \
    "--deploy_hook" "${RENEWED_LINEAGE##*/}" "${TEMP_OUTPUT_DIR}"
}

# Check if it's necessary to fetch a new OCSP response
check_for_existing_ocsp_response() {
  if [[ -f ${OUTPUT_DIR}/${CERT_NAME}.der ]]; then
    local EXPIRY_DATE

    # Inspect the existing local OCSP response, and parse its expiry date
    EXPIRY_DATE=$(openssl ocsp \
      -no_nonce \
      -issuer "${CERT_DIR}/chain.pem" \
      -cert "${CERT_DIR}/cert.pem" \
      -verify_other "${CERT_DIR}/chain.pem" \
      -respin "${OUTPUT_DIR}/${CERT_NAME}.der" 2>&- \
      | grep -oP '(?<=Next Update: ).+$')

    # Only continue fetching OCSP response if existing response expires within
    # two days.
    # Note: A non-zero return code of either `date` command is not caught by
    # Strict Mode, but this isn't critical, since it essentially skips the date
    # check then and always fetches the OCSP response.
    if (( $(date -d "${EXPIRY_DATE}" +%s) > ($(date +%s) + 2*24*60*60) )); then
      echo "${SEPARATION_BAR}"
      echo "Not fetching OCSP response for lineage \"${CERT_NAME}\","
      echo "because existing OCSP response is still valid."
      echo "${SEPARATION_BAR}"
      return 1
    fi
  fi
}

# Generate file used by ssl_stapling_file in nginx config of websites
# $1 - Whether to run as a deploy hook for Certbot, or standalone
# $2 - Name of certificate lineage
# $3 - Path to temporary output directory
fetch_ocsp_response() {
  local -r CERT_NAME="${2}";
  local -r TEMP_OUTPUT_DIR="${3}"
  case ${1} in
    --standalone)
      local -r CERT_DIR="${CERTBOT_DIR}/live/${CERT_NAME}"
      check_for_existing_ocsp_response || return 0
      ;;
    --deploy_hook)
      local -r CERT_DIR="${RENEWED_LINEAGE}"
      ;;
  esac
  shift 3

  local OCSP_ENDPOINT
  OCSP_ENDPOINT="$(openssl x509 -noout -ocsp_uri -in "${CERT_DIR}/cert.pem")"
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
    -respout "${TEMP_OUTPUT_DIR}/${CERT_NAME}.der" 2>&- \
    | grep -q "^${CERT_DIR}/cert.pem: good$"

  # If arrived here status was good, so move OCSP response to definitive folder
  mv "${TEMP_OUTPUT_DIR}/${CERT_NAME}.der" "${OUTPUT_DIR}/"

  # shellcheck disable=SC2004
  RESPONSES_FETCHED=$((${RESPONSES_FETCHED:-0}+1))
}

print_and_handle_result() {
  echo "${SEPARATION_BAR}"
  if [[ -n ${RESPONSES_FETCHED:-} && ${RESPONSES_FETCHED} -gt 0 ]]; then
    echo "Successfully fetched ${RESPONSES_FETCHED} OCSP response(s)!"
    if pgrep -fu "${EUID}" 'nginx: master process' 1>/dev/null; then
      /usr/sbin/service nginx reload
      echo "nginx is reloaded to cache any new responses."
    else
      {
        echo "WARNING: Script is run without root privileges, so nginx has to"
        echo "be manually restarted to cache the new OCSP responses in memory."
      } >&2
    fi
  else
    echo "No OCSP responses were fetched."
  fi
  echo "${SEPARATION_BAR}"
}

main() {
  parse_cli_arguments "${@}"

  prepare_output_dir

  start_in_correct_mode
}

main "${@}"
