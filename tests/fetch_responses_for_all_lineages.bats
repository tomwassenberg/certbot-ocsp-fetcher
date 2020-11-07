#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses for all certificate lineages" {
  fetch_sample_certs --multiple "valid example"

  run "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}"

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
        if [[ ${lines[${line:?}]} =~ ^"${lineage_name##*/}"[[:blank:]]+updated$ ]]
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
