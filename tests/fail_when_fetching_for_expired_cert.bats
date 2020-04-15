#!/usr/bin/env bats

load _test_helper

@test "fail when fetching OCSP response for expired certificate" {
  fetch_sample_certs expired

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name expired

  [[ ${status} != 0 ]]
  [[ ${lines[1]} =~ ^expired[[:blank:]]+"not updated"[[:blank:]]+"leaf certificate expired"$ ]]
  [[ ! -e "${OUTPUT_DIR}/expired.der" ]]
}
