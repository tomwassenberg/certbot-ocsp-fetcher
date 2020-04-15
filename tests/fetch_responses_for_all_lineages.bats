#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses for all certificate lineages" {
  fetch_sample_certs --multiple valid

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}"

  [[ ${status} == 0 ]]

  for line in "${!lines[@]}"; do
    if [[ ${line} == 0 ]]; then
      [[ ${lines[${line}]} =~ ^LINEAGE[[:blank:]]+RESULT[[:blank:]]+REASON$ ]]
    else
      for lineage in "${CERTBOT_DIR}"/live/*; do
        [[ -f "${OUTPUT_DIR}/${lineage##*/}.der" ]]

        local -l cert_found=false
        if [[ ${lines[${line}]} =~ ^"${lineage##*/}"[[:blank:]]+updated$ ]]
        then
          cert_found=true
          break
        fi
      done

      [[ ${cert_found} == true ]]
      unset cert_found
    fi
  done
}
