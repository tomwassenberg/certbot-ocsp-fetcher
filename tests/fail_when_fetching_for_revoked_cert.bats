#!/usr/bin/env bats

load _test_helper

@test "fail when fetching OCSP response for revoked certificate" {
  fetch_sample_certs revoked

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name "revoked"

  [[ ${status} != 0 ]]
  [[ ${lines[1]} =~ ^revoked[[:blank:]]+"not updated"[[:blank:]]+revoked$ ]]
  [[ ! -e "${OUTPUT_DIR}/revoked.der" ]]
}
