#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses for empty lineage directory" {
  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTS_DIR}" \
    --output-dir "${OUTPUT_DIR}"

  [[ ${status} == 0 ]]
  [[ ${output} =~ ^LINEAGE[[:blank:]]+RESULT[[:blank:]]+REASON$ ]]
}
