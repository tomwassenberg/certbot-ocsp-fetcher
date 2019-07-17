#!/usr/bin/env bash

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

exit_with_error() {
  echo -e "${@}" >&2
  exit 1
}

print_usage() {
  echo \
    "USAGE: ${0}"\
    "[-c/--certbot-dir DIRECTORY]"\
    "[-h/--help]"\
    "[-n/--cert-name CERTNAME]"\
    "[-o/--output-dir DIRECTORY]"\
    "[-v/--verbose]"
}

parse_cli_arguments() {
  while [[ ${#} -gt 0 ]]; do
    local PARAMETER="${1}"

    case ${PARAMETER} in
      -c|--certbot-dir)
        if [[ -n ${2:-} ]]; then
          CERTBOT_DIR="$(readlink -mn -- "${2}")"; shift 2
        else
          # shellcheck disable=SC2046
          exit_with_error $(print_usage)
        fi
        ;;
      -h|--help)
        print_usage
        exit
        ;;
      -n|--cert-name)
        if [[ -n ${2:-} ]]; then
          declare -gr CERT_LINEAGE="${2}"; shift 2
        else
          # shellcheck disable=SC2046
          exit_with_error $(print_usage)
        fi
        ;;
      -o|--output-dir)
        if [[ -n ${2:-} ]]; then
          OUTPUT_DIR="$(readlink -mn -- "${2}")"; shift 2
        else
          # shellcheck disable=SC2046
          exit_with_error $(print_usage)
        fi
        ;;
      -v|--verbose)
        declare -gr VERBOSE_MODE="true"; shift
        ;;
      *)
        # shellcheck disable=SC2046
        exit_with_error $(print_usage)
        ;;
    esac
  done
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
      "error:\t\tno write access to output directory (\"${OUTPUT_DIR}\")"
  fi
}

start_in_correct_mode() {
  # Create temporary directory to store OCSP response,
  # before having checked the certificate status therein
  local TEMP_OUTPUT_DIR
  TEMP_OUTPUT_DIR="$(mktemp -d)"
  local RESPONSES_FETCHED

  # These two environment variables are set if this script is invoked by Certbot
  if [[ -z ${RENEWED_DOMAINS:-} || -z ${RENEWED_LINEAGE:-} ]]; then
    RESPONSES_FETCHED="$(run_standalone "${TEMP_OUTPUT_DIR}")"
  else
    RESPONSES_FETCHED="$(run_as_deploy_hook "${TEMP_OUTPUT_DIR}")"
  fi

  print_and_handle_result "${RESPONSES_FETCHED}"
}

# Run in "check one or all certificate lineage(s) managed by Certbot" mode
# $1 - Path to temporary output directory
run_standalone() {
  local -r TEMP_OUTPUT_DIR="${1}"
  readonly CERTBOT_DIR="${CERTBOT_DIR:-/etc/letsencrypt}"

  if [[ ! -r "${CERTBOT_DIR}/live" ]]; then
    exit_with_error \
      "error:\t\tcan't access Certbot directory"
  fi

  # Check specific lineage if passed on CLI,
  # or otherwise all lineages in Certbot's dir
  if [[ -n "${CERT_LINEAGE:-}" ]]; then
    fetch_ocsp_response \
      "--standalone" "${CERT_LINEAGE}" "${TEMP_OUTPUT_DIR}"

    local -r RESPONSES_FETCHED=1
  else
    local RESPONSES_FETCHED
    set +f; shopt -s nullglob
    for CERT_NAME in ${CERTBOT_DIR}/live/*
    do
      fetch_ocsp_response \
        "--standalone" "${CERT_NAME##*/}" "${TEMP_OUTPUT_DIR}"

      RESPONSES_FETCHED=$((${RESPONSES_FETCHED:-0}+1))
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
      # The directory is already inferred from the call that Certbot makes
      "error:\t\tCertbot directory cannot be passed when run as Certbot hook"
  fi

  fetch_ocsp_response \
    "--deploy_hook" "${RENEWED_LINEAGE##*/}" "${TEMP_OUTPUT_DIR}"

  local -r RESPONSES_FETCHED=1
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
      if [[ "${VERBOSE_MODE:-}" == "true" ]]; then
        echo -e "${CERT_NAME}:\t\tunfetched\tvalid response on disk" >&2
      fi
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
    -header "Host=${OCSP_HOST}" \
    -issuer "${CERT_DIR}/chain.pem" \
    -cert "${CERT_DIR}/cert.pem" \
    -verify_other "${CERT_DIR}/chain.pem" \
    -respout "${TEMP_OUTPUT_DIR}/${CERT_NAME}.der" 2>&- \
    | grep -q "^${CERT_DIR}/cert.pem: good$"

  # If arrived here status was good, so move OCSP response to definitive folder
  mv "${TEMP_OUTPUT_DIR}/${CERT_NAME}.der" "${OUTPUT_DIR}/"

  if [[ "${VERBOSE_MODE:-}" == "true" ]]; then
    echo -e "${CERT_NAME}:\t\tfetched" >&2
  fi
}

print_and_handle_result() {
  local -r RESPONSES_FETCHED="${1}"

  if [[ -n ${RESPONSES_FETCHED:-} && ${RESPONSES_FETCHED} -gt 0 ]]; then
    if pgrep -fu "${EUID}" 'nginx: master process' 1>/dev/null; then
      /usr/sbin/service nginx reload
      if [[ "${VERBOSE_MODE:-}" == "true" ]]; then
        echo -e "\nnginx:\t\treloaded" >&2
      fi
    else
      if [[ "${VERBOSE_MODE:-}" == "true" ]]; then
        echo -e "\nnginx:\t\tnot reloaded\tunprivileged, reload manually" >&2
      fi
    fi
  fi
}

main() {
  parse_cli_arguments "${@}"

  prepare_output_dir

  start_in_correct_mode
}

main "${@}"
