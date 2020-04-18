#!/usr/bin/env bash

# Unofficial Bash strict mode
set \
  -o errexit \
  -o errtrace \
  -o noglob \
  -o nounset \
  -o pipefail
IFS=$'\n\t'

exit_with_error() {
  echo "${@}" >&2
  exit 1
}

parse_cli_arguments() {
  local -r usage=(
    "USAGE: ${0}"
    "[-c/--certbot-dir DIRECTORY]"
    "[-f/--force-update]"
    "[-h/--help]"
    "[-n/--cert-name CERT_NAME[,CERT_NAME...]]"
    "[-o/--output-dir DIRECTORY]"
    "[-q/--quiet]"
    "[-v/--verbose]"
    "[-w/--no-reload-webserver]"
  )

  declare -gi VERBOSITY=1

  while [[ ${#} -gt 0 ]]; do
    local parameter="${1}"

    case ${parameter} in
      -c|--certbot-dir)
        if [[ -n ${2:-} ]]; then
          CERTBOT_DIR="$(realpath \
            --canonicalize-missing \
            --relative-base . \
            -- "${2}")"; shift 2
        else
          exit_with_error "${usage[@]}"
        fi
        ;;
      -f|--force-update)
        FORCE_UPDATE="true"; shift
        ;;
      -h|--help)
        echo >&2 "${usage[@]}"
        exit
        ;;
      -n|--cert-name)
        if [[ -n ${2:-} ]]; then
          declare -ag CERT_LINEAGES
          OLDIFS="${IFS}"
          IFS=,
          for lineage_name in ${2}; do
            CERT_LINEAGES+=("${lineage_name}")
          done
          IFS="${OLDIFS}"
          shift 2
        else
          exit_with_error "${usage[@]}"
        fi
        ;;
      -o|--output-dir)
        if [[ -n ${2:-} ]]; then
          OUTPUT_DIR="$(realpath \
            --canonicalize-missing \
            --relative-base . \
            -- "${2}")"; shift 2
        else
          exit_with_error "${usage[@]}"
        fi
        ;;
      -q|--quiet)
        VERBOSITY=0
        ;;
      -v|--verbose)
        VERBOSITY+=1; shift
        ;;
      -w|--no-reload-webserver)
        declare -glr RELOAD_WEBSERVER="false"; shift
        ;;
      *)
        exit_with_error "${usage[@]}"
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
      mkdir \
        --parents \
        -- "${OUTPUT_DIR}" || true
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
  # Create temporary directory to store OCSP staple file,
  # before having checked the certificate status in the response
  local temp_output_dir
  temp_output_dir="$(mktemp --directory)"
  readonly temp_output_dir

  declare -A lineages_processed

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
      "error:"$'\t\t'"can't access ${CERTBOT_DIR}/live"
  fi

  # Check specific lineage if passed on CLI,
  # or otherwise all lineages in Certbot's dir
  if [[ -v CERT_LINEAGES[*] ]]; then
    for lineage_name in "${CERT_LINEAGES[@]}"; do
      if [[ -r "${CERTBOT_DIR}/live/${lineage_name}" ]]; then
        fetch_ocsp_response \
          "--standalone" "${lineage_name}" "${temp_output_dir}"
      else
        exit_with_error \
        "error:"$'\t\t'"can't access ${CERTBOT_DIR}/live/${lineage_name}"
      fi
    done
  else
    set +f; shopt -s nullglob
    for lineage_dir in "${CERTBOT_DIR}"/live/*
    do
      fetch_ocsp_response \
        "--standalone" "${lineage_dir##*/}" "${temp_output_dir}"
    done
    unset lineage_dir
    set -f
  fi
}

# Run in deploy-hook mode, only processing the passed lineage
# $1 - Path to temporary output directory
run_as_deploy_hook() {
  if [[ -n ${CERTBOT_DIR:-} ]]; then
    # The directory is already inferred from the environment variable that
    # Certbot passes
    exit_with_error \
      "error:"$'\t\t'"-c/--certbot-dir cannot be passed" \
      "when run as Certbot hook"
  fi

  if [[ -n ${FORCE_UPDATE:-} ]]; then
    # When run as deploy hook the behavior of this flag is used by default.
    # Therefore passing this flag would not have any effect.
    exit_with_error \
      "error:"$'\t\t'"-f/--force-update cannot be passed" \
      "when run as Certbot hook"
  fi

  if [[ -v CERT_LINEAGES[*] ]]; then
    # The certificate lineage is already inferred from the environment
    # variable that Certbot passes
    exit_with_error \
      "error:"$'\t\t'"-n/--cert-name cannot be passed when run as Certbot hook"
  fi

  fetch_ocsp_response \
    "--deploy_hook" "${RENEWED_LINEAGE##*/}" "${temp_output_dir}"
}

# Check if it's necessary to fetch a new OCSP response
check_for_existing_ocsp_staple_file() {
  [[ -f ${OUTPUT_DIR}/${lineage_name}.der ]] || return 1

  # Validate and verify the existing local OCSP staple file
  local existing_ocsp_response
  set +e
  existing_ocsp_response="$(openssl ocsp \
    -no_nonce \
    -issuer "${lineage_dir}/chain.pem" \
    -cert "${lineage_dir}/cert.pem" \
    -verify_other "${lineage_dir}/chain.pem" \
    -respin "${OUTPUT_DIR}/${lineage_name}.der" 2>&3)"
  local -r existing_ocsp_response_rc=${?}
  set -e
  readonly existing_ocsp_response


  [[ "${existing_ocsp_response_rc}" == 0 ]] || return 1

  for existing_ocsp_response_line in ${existing_ocsp_response}; do
    if [[ ${existing_ocsp_response_line} =~ "This Update: "(.+) ]]; then
      local -r this_update="${BASH_REMATCH[1]}"
    elif [[ ${existing_ocsp_response_line} =~ "Next Update: "(.+) ]]; then
      local -r next_update="${BASH_REMATCH[1]}"
    fi
  done
  [[ -n "${this_update:-}" && -n "${next_update:-}" ]] || return 1

  # Only continue fetching OCSP response if existing response expires within
  # half of its lifetime.
  # Note: A non-zero return code of one of the `date` calls is not caught by
  # Strict Mode, but this isn't critical, since it essentially skips the date
  # check then and always fetches the OCSP response.
  local -ri response_lifetime_in_seconds=$(( \
    $(date +%s --date "${next_update}") - $(date +%s --date "${this_update}") ))
  (( $(date +%s) < \
    $(date +%s --date "${this_update}") + response_lifetime_in_seconds / 2 )) \
    || return 1
}

# Generate file used by ssl_stapling_file in nginx config of websites
# $1 - Whether to run as a deploy hook for Certbot, or standalone
# $2 - Name of certificate lineage
# $3 - Path to temporary output directory
fetch_ocsp_response() {
  local -r lineage_name="${2}";
  local -r temp_output_dir="${3}"
  case ${1} in
    --standalone)
      local -r lineage_dir="${CERTBOT_DIR}/live/${lineage_name}"

      if [[ ${FORCE_UPDATE:-} != "true" ]] && \
        check_for_existing_ocsp_staple_file; then
        lineages_processed["${lineage_name}"]="not updated"$'\t'"valid staple file on disk"
        return
      fi
      ;;
    --deploy_hook)
      local -r lineage_dir="${RENEWED_LINEAGE}"
      ;;
    *)
      return 1
      ;;
  esac
  shift 3

  # Verify that the leaf certificate is still valid. If the certificate is
  # expired, we don't have to request a (new) OCSP response.
  if ! openssl x509 \
    -in "${lineage_dir}/cert.pem" \
    -checkend 0 \
    -noout >&3 2>&1; then

    ERROR_ENCOUNTERED="true"
    lineages_processed["${lineage_name}"]="not updated"$'\t'"leaf certificate expired"
    return
  fi

  local ocsp_endpoint
  ocsp_endpoint="$(openssl x509 \
    -noout \
    -ocsp_uri \
    -in "${lineage_dir}/cert.pem" \
    2>&3)"
  readonly ocsp_endpoint

  # Request, verify and temporarily save the actual OCSP response,
  # and check whether the certificate status is "good"
  local ocsp_call_output
  set +e
  ocsp_call_output="$(openssl ocsp \
    -no_nonce \
    -url "${ocsp_endpoint}" \
    -issuer "${lineage_dir}/chain.pem" \
    -cert "${lineage_dir}/cert.pem" \
    -verify_other "${lineage_dir}/chain.pem" \
    -respout "${temp_output_dir}/${lineage_name}.der" 2>&3)"
  local -r ocsp_call_rc=${?}
  set -e
  readonly ocsp_call_output="${ocsp_call_output#${lineage_dir}/cert.pem: }"
  local -r cert_status="${ocsp_call_output%%$'\n'*}"

  if [[ ${ocsp_call_rc} != 0 || ${cert_status} != good ]]; then
    ERROR_ENCOUNTERED="true"
    if (( "${VERBOSITY}" >= 2 )); then
      lineages_processed["${lineage_name}"]="not updated"$'\t'"${ocsp_call_output//[[:space:]]/ }"
    else
      lineages_processed["${lineage_name}"]="not updated"$'\t'"${cert_status}"
    fi
    return
  fi

  # If arrived here status was good, so move OCSP staple file to definitive
  # folder
  mv "${temp_output_dir}/${lineage_name}.der" "${OUTPUT_DIR}/"

  lineages_processed["${lineage_name}"]="updated"
}

print_and_handle_result() {
  local header="LINEAGE"$'\t'"RESULT"$'\t'"REASON"

  for lineage_name in "${!lineages_processed[@]}"; do
    local lineages_processed_formatted+=$'\n'"${lineage_name}"$'\t'"${lineages_processed["${lineage_name}"]}"
  done
  unset lineage_name
  lineages_processed_formatted="$(sort <<< "${lineages_processed_formatted:-}")"
  readonly lineages_processed_formatted
  local output="${header}${lineages_processed_formatted:-}"

  if [[ ${RELOAD_WEBSERVER:-} != "false" ]]; then
    reload_webserver
  fi

  if (( "${VERBOSITY}" >= 1 )); then
    if command -v column >&-; then
      column -ents$'\t' <<< "${output}"
    else
      echo >&2 \
        "Install BSD \"column\" for properly formatted output. On Ubuntu," \
        "this can be done by installing the \"bsdmainutils\" package."$'\n'
      echo "${output}"
    fi
  fi

  [[ "${ERROR_ENCOUNTERED:-}" != "true" ]]
}

reload_webserver() {
  for lineage_name in "${!lineages_processed[@]}"; do
    if [[ "${lineages_processed["${lineage_name}"]}" == "updated" ]]; then
      if service nginx reload >&3 2>&1; then
        local -r nginx_status=$'\n\n\t'"nginx reloaded"
        break
      else
        ERROR_ENCOUNTERED="true"
        local -r nginx_status=$'\n\n\t'"nginx not reloaded"$'\t'"unable to reload nginx service, try manually"
        break
      fi
    fi
  done
  unset lineage_name
  readonly output+="${nginx_status:-}"
}

main() {
  parse_cli_arguments "${@}"

  prepare_output_dir

  start_in_correct_mode
}

main "${@}"
