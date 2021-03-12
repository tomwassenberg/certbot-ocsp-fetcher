#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses for all certificate lineages" {
  fetch_sample_certs --multiple "valid example"

  run "${TOOL_COMMAND_LINE[@]:?}" \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}"

  ((status == 0))

  for line in "${!lines[@]}"; do
    if ((line == 0)); then
      [[ ${lines[${line:?}]} =~ ^LINEAGE[[:blank:]]+RESULT[[:blank:]]+REASON$ ]]
    else
      for lineage_name in "${CERTBOT_CONFIG_DIR:?}"/live/*; do
        # Skip non-directories, like Certbot's README file
        [[ -d ${lineage_name:?} ]] || continue

        [[ -f "${OUTPUT_DIR:?}/${lineage_name##*/}.der" ]]

        local -l cert_found=false
        if [[ ${lines[${line:?}]} =~ ^"${lineage_name##*/}"[[:blank:]]+updated[[:blank:]]*$ ]]
        then
          cert_found=true
          break
        fi
      done

      [[ ${cert_found:?} == true ]]
      unset cert_found
    fi
  done
}
