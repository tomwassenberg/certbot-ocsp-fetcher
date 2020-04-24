#!/usr/bin/env bats

load _test_helper

@test "fail when fetching OCSP response for expired certificate" {
  fetch_sample_certs "expired example"

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name "expired example"

  [[ ${status} != 0 ]]
  [[ ${lines[1]} =~ ^"expired example"[[:blank:]]+"not updated"[[:blank:]]+"leaf certificate expired"$ ]]
  [[ ! -e "${OUTPUT_DIR}/expired example.der" ]]
}
