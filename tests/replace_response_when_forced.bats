#!/usr/bin/env bats

load _test_helper

@test "replace existing OCSP response when forced" {
  fetch_sample_certs "valid example"

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name "valid example"

  [[ ${status} == 0 ]]
  [[ -f "${OUTPUT_DIR}/valid example.der" ]]

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name "valid example" \
    --force-update

  [[ ${status} == 0 ]]
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+updated$ ]]
  [[ -f "${OUTPUT_DIR}/valid example.der" ]]
}
