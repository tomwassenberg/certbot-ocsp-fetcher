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
    local parameter="${1}"

    case ${parameter} in
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
  local temp_output_dir
  temp_output_dir="$(mktemp -d)"
  local responses_fetched

  # These two environment variables are set if this script is invoked by Certbot
  if [[ -z ${RENEWED_DOMAINS:-} || -z ${RENEWED_LINEAGE:-} ]]; then
    responses_fetched="$(run_standalone "${temp_output_dir}")"
  else
    responses_fetched="$(run_as_deploy_hook "${temp_output_dir}")"
  fi

  print_and_handle_result "${responses_fetched}"
}

# Run in "check one or all certificate lineage(s) managed by Certbot" mode
# $1 - Path to temporary output directory
run_standalone() {
  local -r temp_output_dir="${1}"
  readonly CERTBOT_DIR="${CERTBOT_DIR:-/etc/letsencrypt}"

  if [[ ! -r "${CERTBOT_DIR}/live" ]]; then
    exit_with_error \
      "error:\t\tcan't access Certbot directory"
  fi

  # Check specific lineage if passed on CLI,
  # or otherwise all lineages in Certbot's dir
  if [[ -n "${CERT_LINEAGE:-}" ]]; then
    fetch_ocsp_response \
      "--standalone" "${CERT_LINEAGE}" "${temp_output_dir}"

    local -r responses_fetched=1
  else
    local responses_fetched
    set +f; shopt -s nullglob
    for cert_name in "${CERTBOT_DIR}"/live/*
    do
      if fetch_ocsp_response \
        "--standalone" "${cert_name##*/}" "${temp_output_dir}"; then
	      responses_fetched=$((${responses_fetched:-0}+1))
      fi
    done
    unset cert_name
    set -f
    echo "${responses_fetched:-0}"
  fi
}

# Run in deploy-hook mode, only checking the passed certificate
# $1 - Path to temporary output directory
run_as_deploy_hook() {
  local -r temp_output_dir="${1}"

  if [[ -n ${CERTBOT_DIR:-} ]]; then
    exit_with_error \
      # The directory is already inferred from the call that Certbot makes
      "error:\t\tCertbot directory cannot be passed when run as Certbot hook"
  fi

  fetch_ocsp_response \
    "--deploy_hook" "${RENEWED_LINEAGE##*/}" "${temp_output_dir}"

  local -r responses_fetched=1
}

# Check if it's necessary to fetch a new OCSP response
check_for_existing_ocsp_response() {
  if [[ -f ${OUTPUT_DIR}/${cert_name}.der ]]; then
    local -r expiry_regex='^\s*Next Update: (.+)$'
    local expiry_date

    # Inspect the existing local OCSP response, and parse its expiry date
    if ! [[ $(openssl ocsp \
      -no_nonce \
      -issuer "${cert_dir}/chain.pem" \
      -cert "${cert_dir}/cert.pem" \
      -verify_other "${cert_dir}/chain.pem" \
      -respin "${OUTPUT_DIR}/${cert_name}.der" 2>&- | \
      tail -n1) \
      =~ ${expiry_regex} ]]; then
      echo >&2 \
        "Error encountered in parsing previously existing OCSP response," \
        "located at ${OUTPUT_DIR}/${cert_name}.der. Planning to request new" \
        "OCSP response."
      return
    fi
    expiry_date="${BASH_REMATCH[1]}"

    # Only continue fetching OCSP response if existing response expires within
    # two days.
    # Note: A non-zero return code of either `date` command is not caught by
    # Strict Mode, but this isn't critical, since it essentially skips the date
    # check then and always fetches the OCSP response.
    if (( $(date -d "${expiry_date}" +%s) > ($(date +%s) + 2*24*60*60) )); then
      if [[ "${VERBOSE_MODE:-}" == "true" ]]; then
        echo -e "${cert_name}:\t\tunfetched\tvalid response on disk" >&2
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
  local -r cert_name="${2}";
  local -r temp_output_dir="${3}"
  case ${1} in
    --standalone)
      local -r cert_dir="${CERTBOT_DIR}/live/${cert_name}"

      if ! check_for_existing_ocsp_response; then
        return 1
      fi
      ;;
    --deploy_hook)
      local -r cert_dir="${RENEWED_LINEAGE}"
      ;;
  esac
  shift 3

  local ocsp_endpoint
  ocsp_endpoint="$(openssl x509 -noout -ocsp_uri -in "${cert_dir}/cert.pem")"
  local -r ocsp_host="${ocsp_endpoint#*://}"

  # Request, verify and temporarily save the actual OCSP response,
  # and check whether the certificate status is "good"
  if ! [[ "$(openssl ocsp \
    -no_nonce \
    -url "${ocsp_endpoint}" \
    -header "Host=${ocsp_host}" \
    -issuer "${cert_dir}/chain.pem" \
    -cert "${cert_dir}/cert.pem" \
    -verify_other "${cert_dir}/chain.pem" \
    -respout "${temp_output_dir}/${cert_name}.der" 2>&- | \
    head -n1)" \
    =~ ^"${cert_dir}/cert.pem: good"$ ]]; then
    exit_with_error \
      "Error encountered in the request, verification and/or validation of the" \
      "OCSP response for the certificate lineage located at \"${cert_dir}\""
  fi

  # If arrived here status was good, so move OCSP response to definitive folder
  mv "${temp_output_dir}/${cert_name}.der" "${OUTPUT_DIR}/"

  if [[ "${VERBOSE_MODE:-}" == "true" ]]; then
    echo -e "${cert_name}:\t\tfetched" >&2
  fi
}

print_and_handle_result() {
  local -r responses_fetched="${1}"

  if [[ -n ${responses_fetched:-} && ${responses_fetched} -gt 0 ]]; then
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
