#!/usr/bin/env bash

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

parse_cli_arguments() {
  while [[ ${#} -gt 1 ]]
    do
      local -r PARAMETER="${1}"

      case ${PARAMETER} in
        -o|--output-dir)
          declare -gr OUTPUT_DIR="${2}"
          shift
          ;;
        -c|--certbot-dir)
          declare -gr CERTBOT_DIR="${2}"
          shift
          ;;
        *)
          echo "USAGE: ${0} [-o/--output-dir DIRECTORY]"
          exit 1
          ;;
      esac
    shift
  done
}

process_website_list() {
  if [[ -z ${OUTPUT_DIR+x} ]]; then
    local -r OUTPUT_DIR="/etc/nginx/ocsp-cache"
  fi
  mkdir -p ${OUTPUT_DIR}

  # These two variables are set if this script is invoked by Certbot
  if [[ -z ${RENEWED_DOMAINS+x} || -z ${RENEWED_LINEAGE+x} ]]; then
      # Run in "check every certificate" mode
      declare -gr FETCH_ALL="true"

      if [[ -z ${CERTBOT_DIR+x} ]]; then
        local -r CERTBOT_DIR="/etc/letsencrypt"
      fi

      for CERT_NAME in $(find ${CERTBOT_DIR}/live -type d | grep -oP \
      '(?<=/live/).+$')
      do
        fetch_ocsp_response "${CERTBOT_DIR}/live/${CERT_NAME}" "${OUTPUT_DIR}" \
        "${CERT_NAME}"
      done
      unset CERT_NAME
  else
      # Run in Certbot mode, only checking the passed certificate
      declare -gr FETCH_ALL="false"

      if [[ -n ${CERTBOT_DIR+x} ]]; then
        echo "The -c/--certbot-dir parameter is not applicable when Certbot is"\
        "used as a Certbot hook, because the directory is already inferred"\
        "from the call that Certbot makes."
        exit 1
      fi

      fetch_ocsp_response "${RENEWED_LINEAGE}" "${OUTPUT_DIR}" \
      "$(echo "${RENEWED_LINEAGE}" | awk -F '/' '{print $NF}')"
  fi 1> /dev/null
}

# Generates file used by ssl_stapling_file in nginx config of websites
fetch_ocsp_response() {
  # Enforce that the OCSP URL is always plain HTTP, because HTTPS URL's are not
  # explicitly prohibited by the Baseline Requirements, but they *are* by
  # Mozilla's recommended practices.
  local -r OCSP_ENDPOINT="$(openssl x509 -noout -ocsp_uri -in "${1}/cert.pem" |\
  sed -e 's|^https|http|')"
  local -r OCSP_HOST="$(echo "${OCSP_ENDPOINT}" | awk -F '/' '{print $3}')"

  # Request, verify and save the actual OCSP response
  openssl ocsp \
    -no_nonce \
    -url "${OCSP_ENDPOINT}" \
    -header "HOST" "${OCSP_HOST}" \
    -issuer "${1}/chain.pem" \
    -cert "${1}/cert.pem" \
    -verify_other "${1}/chain.pem" \
    -respout "${2}/${3}.der" \
    2> /dev/null
}

main() {
  # Check for sudo/root access, because it needs to access certificates, write
  # to the output directory which is probably not world-writeable and reload the
  # nginx service.
  if [[ "${EUID}" != "0" ]]; then
    echo "This script can only be run with superuser privileges."
    exit 1
  fi

  parse_cli_arguments "${@}"

  process_website_list

  # Reload nginx to cache the new OCSP responses in memory
  /usr/sbin/service nginx reload 1> /dev/null

  # Only output success message if not run as Certbot hook
  if [[ "${FETCH_ALL}" == "true" ]]; then
    echo "Fetching of OCSP response(s) successful! nginx is reloaded to cache"\
    "any new responses."
  fi
}

main "${@}"
