#!/usr/bin/env bats

load _test_helper

@test "replace existing OCSP response when forced" {
  fetch_sample_certs valid

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name valid

  [[ ${status} == 0 ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name valid \
    --force-update

  [[ ${status} == 0 ]]
  [[ ${lines[1]} =~ ^valid[[:blank:]]+updated$ ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]
}
