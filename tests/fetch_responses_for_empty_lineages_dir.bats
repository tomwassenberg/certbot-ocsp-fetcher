#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses for empty lineage directory" {
  output=$("${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}")

  [[ ${output:?} =~ ^LINEAGE[[:blank:]]+RESULT[[:blank:]]+REASON$ ]]
}
