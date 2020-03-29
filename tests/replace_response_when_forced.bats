#!/usr/bin/env bats

load _test_helper

@test "replace existing OCSP response when forced" {
  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${BATS_TEST_DIRNAME}/examples" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name valid

  [[ ${status} == 0 ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${BATS_TEST_DIRNAME}/examples" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name valid \
    --force-update

  [[ ${status} == 0 ]]
  [[ ${lines[1]} =~ ^valid[[:blank:]]+updated$ ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]
}
