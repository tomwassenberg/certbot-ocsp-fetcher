#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses from supplied OCSP responder" {
  fetch_sample_certs --multiple "valid example"

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name "valid example 1,valid example 2" \
    --ocsp-responder http://ocsp.digicert.com

  ((status == 0))

  for line in "${!lines[@]}"; do
    if ((line == 0)); then
      [[ ${lines[${line}]} =~ ^LINEAGE[[:blank:]]+RESULT[[:blank:]]+REASON$ ]]
    else
      for lineage_name in "${CERTBOT_DIR}"/live/*; do
        # Skip non-directories, like Certbot's README file
        [[ -d ${lineage_name} ]] || continue

        [[ -f "${OUTPUT_DIR}/${lineage_name##*/}.der" ]]

        local -l cert_found=false
        if [[ ${lines[${line}]} =~ ^"${lineage_name##*/}"[[:blank:]]+updated$ ]]
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
