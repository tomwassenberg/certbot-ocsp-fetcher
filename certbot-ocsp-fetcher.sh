#!/usr/bin/env bash

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

exit_with_error() {
  echo "${@}" >&2
  exit 1
}

print_usage() {
  echo \
    "USAGE: ${0}"\
    "[-c/--certbot-dir DIRECTORY]"\
    "[-f/--force-fetch"\
    "[-h/--help]"\
    "[-n/--cert-name CERTNAME]"\
    "[-o/--output-dir DIRECTORY]"\
    "[-v/--verbose] [-v/--verbose]"
}

parse_cli_arguments() {
  declare -gi VERBOSITY=0

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
      -f|--force)
        FORCE_FETCH="true"; shift
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
        VERBOSITY+=1; shift
        ;;
      *)
        # shellcheck disable=SC2046
        exit_with_error $(print_usage)
        ;;
    esac
  done

  # When not parsed, the stdout and/or stderr output of all external commands
  # we call in the script is redirected to file descriptor 3.  Depending on the
  # desired verbosity, we redirect this file descriptor to either stderr or to
  # /dev/null.
  if (( "${VERBOSITY}" >= 2 )); then
    exec 3>&2
  else
    exec 3>/dev/null
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
      "error:"$'\t\t'"no write access to output directory (\"${OUTPUT_DIR}\")"
  fi
}

start_in_correct_mode() {
  # Create temporary directory to store OCSP response,
  # before having checked the certificate status therein
  local temp_output_dir
  temp_output_dir="$(mktemp -d)"
  readonly temp_output_dir

  declare -A CERTS_PROCESSED

  # These two environment variables are set if this script is invoked by Certbot
  if [[ -z ${RENEWED_DOMAINS:-} || -z ${RENEWED_LINEAGE:-} ]]; then
    run_standalone
  else
    run_as_deploy_hook
  fi

  print_and_handle_result
}

# Run in "check one or all certificate lineage(s) managed by Certbot" mode
# $1 - Path to temporary output directory
run_standalone() {
  readonly CERTBOT_DIR="${CERTBOT_DIR:-/etc/letsencrypt}"

  if [[ ! -r "${CERTBOT_DIR}/live" ]]; then
    exit_with_error \
      "error:"$'\t\t'"can't access Certbot directory"
  fi

  # Check specific lineage if passed on CLI,
  # or otherwise all lineages in Certbot's dir
  if [[ -n "${CERT_LINEAGE:-}" ]]; then
    fetch_ocsp_response \
      "--standalone" "${CERT_LINEAGE}" "${temp_output_dir}"
  else
    set +f; shopt -s nullglob
    for cert_name in "${CERTBOT_DIR}"/live/*
    do
      fetch_ocsp_response \
        "--standalone" "${cert_name##*/}" "${temp_output_dir}"
    done
    unset cert_name
    set -f
  fi
}

# Run in deploy-hook mode, only checking the passed certificate
# $1 - Path to temporary output directory
run_as_deploy_hook() {
  if [[ -n ${CERTBOT_DIR:-} ]]; then
    # The directory is already inferred from the environment variable that
    # Certbot passes
    exit_with_error \
      "error:"$'\t\t'"-c/--certbot-dir cannot be passed when run as Certbot hook"
  fi

  if [[ -n ${FORCE_FETCH:-} ]]; then
    # When run as deploy hook the behavior of this flag is used by default.
    # Therefore passing this flag would not have any effect.
    exit_with_error \
      "error:"$'\t\t'"-f/--force-fetch cannot be passed when run as Certbot hook"
  fi

  if [[ -n ${CERT_LINEAGE:-} ]]; then
    # The certificate lineage is already inferred from the environment
    # variable that Certbot passes
    exit_with_error \
      "error:"$'\t\t'"-n/--cert-name cannot be passed when run as Certbot hook"
  fi

  fetch_ocsp_response \
    "--deploy_hook" "${RENEWED_LINEAGE##*/}" "${temp_output_dir}"
}

# Check if it's necessary to fetch a new OCSP response
check_for_existing_ocsp_response() {
  [[ -f ${OUTPUT_DIR}/${cert_name}.der ]] || return 1

  # Inspect the existing local OCSP response, and parse its expiry date
  local ocsp_response_next_update
  set +e
  ocsp_response_next_update="$(openssl ocsp \
    -no_nonce \
    -issuer "${cert_dir}/chain.pem" \
    -cert "${cert_dir}/cert.pem" \
    -verify_other "${cert_dir}/chain.pem" \
    -respin "${OUTPUT_DIR}/${cert_name}.der" 2>&3)"
  local -r ocsp_response_next_update_rc=${?}
  set -e
  readonly ocsp_response_next_update


  local -r expiry_regex='^\s*Next Update: (.+)$'
  if [[ "${ocsp_response_next_update_rc}" != 0 || ! ${ocsp_response_next_update##*$'\n'} =~ ${expiry_regex} ]]; then
    echo >&2 \
      "Error encountered in parsing previously existing OCSP response," \
      "located at ${OUTPUT_DIR}/${cert_name}.der. Planning to request new" \
      "OCSP response."
    return 1
  else
    local -r expiry_date="${BASH_REMATCH[1]}"
  fi

  # Only continue fetching OCSP response if existing response expires within
  # two days.
  # Note: A non-zero return code of either `date` command is not caught by
  # Strict Mode, but this isn't critical, since it essentially skips the date
  # check then and always fetches the OCSP response.
  (( $(date -d "${expiry_date}" +%s) > ($(date +%s) + 2*24*60*60) )) || \
    return 1
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

      if [[ ${FORCE_FETCH:-} != "true" ]] && check_for_existing_ocsp_response; then
        CERTS_PROCESSED["${cert_name}"]="unfetched"$'\t'"valid response on disk"
        return
      fi
      ;;
    --deploy_hook)
      local -r cert_dir="${RENEWED_LINEAGE}"
      ;;
    *)
      return 1
      ;;
  esac
  shift 3

  # Verify that the leaf certificate is still valid. If the certificate is
  # expired, we don't have to request a (new) OCSP response.
  if ! openssl x509 \
    -in "${cert_dir}/cert.pem" \
    -checkend 0 \
    -noout >&3 2>&1; then

    ERROR_ENCOUNTERED="true"
    CERTS_PROCESSED["${cert_name}"]="unfetched"$'\t'"leaf certificate expired"
    return
  fi

  local ocsp_endpoint
  ocsp_endpoint="$(openssl x509 -noout -ocsp_uri -in "${cert_dir}/cert.pem" 2>&3)"
  readonly ocsp_endpoint
  local ocsp_host="${ocsp_endpoint##*://}"
  readonly ocsp_host="${ocsp_host%%/*}"

  # Request, verify and temporarily save the actual OCSP response,
  # and check whether the certificate status is "good"
  local cert_status
  set +e
  cert_status="$(openssl ocsp \
    -no_nonce \
    -url "${ocsp_endpoint}" \
    -header "Host=${ocsp_host}" \
    -issuer "${cert_dir}/chain.pem" \
    -cert "${cert_dir}/cert.pem" \
    -verify_other "${cert_dir}/chain.pem" \
    -respout "${temp_output_dir}/${cert_name}.der" 2>&-)"
  local -r cert_status_rc=${?}
  set -e
  readonly cert_status
  if [[ "${cert_status_rc}" != 0 ]]; then
    ERROR_ENCOUNTERED="true"
    CERTS_PROCESSED["${cert_name}"]="unfetched"$'\t'"{cert_status//[[:space:]]/ }"
    return
  fi
  if ! [[ ${cert_status%%$'\n'*} =~ ^"${cert_dir}/cert.pem: good"$ ]]; then
    exit_with_error \
      "Error encountered in the request, verification and/or validation of the" \
      "OCSP response for the certificate lineage located at \"${cert_dir}\""
  fi

  # If arrived here status was good, so move OCSP response to definitive folder
  mv "${temp_output_dir}/${cert_name}.der" "${OUTPUT_DIR}/"

  CERTS_PROCESSED["${cert_name}"]="fetched"
}

print_and_handle_result() {
  local header="LINEAGE"$'\t'"FETCH RESULT"$'\t'"REASON"

  for cert_name in "${!CERTS_PROCESSED[@]}"; do
    local certs_processed_formatted+=$'\n'"${cert_name}"$'\t'"${CERTS_PROCESSED["${cert_name}"]}"
  done
  readonly certs_processed_formatted
  unset cert_name
  local output="${header}${certs_processed_formatted}"

  for cert_name in "${!CERTS_PROCESSED[@]}"; do
    if [[ "${CERTS_PROCESSED["${cert_name}"]}" == "fetched" ]]; then
      if pgrep -fu "${EUID}" 'nginx: master process' >&3 2>&1; then
        /usr/sbin/service nginx reload
        local -r nginx_status=$'\n\n\t'"nginx reloaded"
      else
        local -r nginx_status=$'\n\n\t'"nginx not reloaded"$'\t'"unprivileged, reload manually"
      fi
      readonly output+="${nginx_status}"
      break
    fi
  done
  unset cert_name

  if (( "${VERBOSITY}" >= 1 )); then
    column -ents$'\t' <<< "${output}"
  fi

  [[ "${ERROR_ENCOUNTERED:-}" != "true" ]]
}

main() {
  parse_cli_arguments "${@}"

  prepare_output_dir

  start_in_correct_mode
}

main "${@}"
