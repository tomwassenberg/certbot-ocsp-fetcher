#!/usr/bin/env bats

load _test_helper

@test "do not replace fresh OCSP response when not forced" {
  fetch_sample_certs valid

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name valid

  [[ ${status} == 0 ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]
  chmod u-w "${OUTPUT_DIR}/valid.der"

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name valid

  [[ ${status} == 0 ]]
  [[ ${lines[1]} =~ ^valid[[:blank:]]+"not updated"[[:blank:]]+"valid staple file on disk"$ ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]
}
