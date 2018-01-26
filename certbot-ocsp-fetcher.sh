#!/usr/bin/env bash

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

parse_cli_arguments() {
  while [[ ${#} -gt 1 ]]
    do
      local PARAMETER="${1}"; shift

      case ${PARAMETER} in
        -o|--output-dir)
          OUTPUT_DIR="$(readlink -fn -- "${1}")"; shift
          readonly OUTPUT_DIR
          ;;
        -c|--certbot-dir)
          CERTBOT_DIR="$(readlink -fn -- "${1}")"; shift
          readonly CERTBOT_DIR
          ;;
        *)
          echo \
            "USAGE: ${0} [-c/--certbot-dir DIRECTORY] [-o/--output-dir"\
            "DIRECTORY]" 1>&2
          exit 1
          ;;
      esac
    done
}

process_website_list() {
  if [[ -z ${OUTPUT_DIR+x} ]]; then
    readonly OUTPUT_DIR="/etc/nginx/ocsp-cache"
  fi
  if [[ -e ${OUTPUT_DIR} ]]; then
    if [[ ! -w ${OUTPUT_DIR} ]]; then
      echo "ERROR: You don't have write access"\
        "to the output directory (\"${OUTPUT_DIR}\")."\
        "Specify another folder using the -o/--output-dir flag or change"\
        "the permissions of the current output folder accordingly." 1>&2
      exit 1
    fi
  else
    mkdir -p -- ${OUTPUT_DIR}
  fi

  # These two environment variables are set if this script is invoked by Certbot
  if [[ -z ${RENEWED_DOMAINS+x} || -z ${RENEWED_LINEAGE+x} ]]; then
    run_standalone
  else
    run_as_deploy_hook
  fi
}

# Run in "check every certificate" mode
run_standalone() {
  if [[ -z ${CERTBOT_DIR+x} ]]; then
    readonly CERTBOT_DIR="/etc/letsencrypt"
  fi

  if [[ -r "${CERTBOT_DIR}/live" ]]; then
    declare LINEAGES; LINEAGES=$(ls "${CERTBOT_DIR}/live"); readonly LINEAGES
    for CERT_NAME in ${LINEAGES}
    do
      fetch_ocsp_response "--standalone" "${CERT_NAME}" 1>/dev/null
    done
    unset CERT_NAME
  else
    echo "ERROR: You don't have read access to the certificate folder!" 1>&2
    exit 1
  fi

  reload_nginx_and_print_result
}

# Run in Certbot mode, only checking the passed certificate
run_as_deploy_hook() {
  if [[ -n ${CERTBOT_DIR+x} ]]; then
    echo "ERROR: The -c/--certbot-dir parameter is not applicable when"\
      "Certbot is used as a Certbot hook, because the directory is already"\
      "inferred from the call that Certbot makes." 1>&2
    exit 1
  fi

  fetch_ocsp_response "--deploy_hook" \
    "$(echo "${RENEWED_LINEAGE}" | awk -F '/' '{print $NF}')" 1>/dev/null

  reload_nginx_and_print_result
}

# Generates file used by ssl_stapling_file in nginx config of websites
# $1 - Whether to run as a deploy hook for Certbot, or standalone
# $2 - Name of certificate lineage
fetch_ocsp_response() {
  if [[ "${1}" == "--standalone" ]]; then
    local -r CERT_DIR="${CERTBOT_DIR}/live/${CERT_NAME}"
  elif [[ "${1}" == "--deploy_hook" ]]; then
    local -r CERT_DIR="${RENEWED_LINEAGE}"
  fi
  local -r CERT_NAME="${2}"; shift; shift

  local -r OCSP_ENDPOINT="$(openssl x509 -noout -ocsp_uri -in \
    "${CERT_DIR}/cert.pem")"
  local -r OCSP_HOST="$(echo "${OCSP_ENDPOINT}" | awk -F '/' '{print $3}')"

  # Request, verify and save the actual OCSP response
  openssl ocsp \
    -no_nonce \
    -url "${OCSP_ENDPOINT}" \
    -header "Host" "${OCSP_HOST}" \
    -issuer "${CERT_DIR}/chain.pem" \
    -cert "${CERT_DIR}/cert.pem" \
    -verify_other "${CERT_DIR}/chain.pem" \
    -respout "${OUTPUT_DIR}/${CERT_NAME}.der" \
    2>/dev/null | grep -q "^${CERT_DIR}/cert.pem: good$"
}

reload_nginx_and_print_result() {
  # Reload nginx to cache the new OCSP responses in memory
  if pgrep -fu "${EUID}" 'nginx: master process' > /dev/null; then
    /usr/sbin/service nginx reload
    echo "Fetching of OCSP response(s) successful!"\
      "nginx is reloaded to cache any new responses."
  else
    echo "Fetching of OCSP responses successful!"\
      "WARNING: Script is run without root privileges, so nginx has to be"\
      "manually restarted to cache the new OCSP responses in memory."
  fi
}

main() {
  parse_cli_arguments "${@}"

  process_website_list
}

main "${@}"
