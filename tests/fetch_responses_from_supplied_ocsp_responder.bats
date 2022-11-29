#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses from supplied OCSP responder" {
  fetch_sample_certs --multiple valid-example

  if [[ ${CI:-} == true ]]; then
    local ocsp_responder=http://stg-e1.o.lencr.org
  else
    local ocsp_responder=http://e1.o.lencr.org
  fi

  run "${TOOL_COMMAND_LINE[@]}" \
    --certbot-dir "${CERTBOT_CONFIG_DIR}" \
    --cert-name valid-example_1,valid-example_2 \
    --ocsp-responder "${ocsp_responder}" \
    --cert-name valid-example_3

  ((status == 0))

  for line in "${!lines[@]}"; do
    if ((line > 1)); then
      for lineage_name in "${CERTBOT_CONFIG_DIR}"/live/*; do
        # Skip non-directories, like Certbot's README file
        [[ -d ${lineage_name} ]] || continue

        [[ -f "${OUTPUT_DIR}/${lineage_name##*/}.der" ]]

        local -l cert_found=false
        if [[ ${lines[${line}]} =~ ^"${lineage_name##*/}"[[:blank:]]+updated[[:blank:]]*$ ]]; then
          cert_found=true
          break
        fi
      done

      # Skip lines that consist of the warning that's printed when formatting
      # dependency is not present on system.
      [[ ${cert_found} == true ]] ||
        ((line == -2 || line == -1)) && ! { command -v column >&-; }
      unset cert_found
    elif ((line == 1)); then
      [[ ${lines[${line}]} =~ ${HEADER_PATTERN} ]]
    fi
  done
}
