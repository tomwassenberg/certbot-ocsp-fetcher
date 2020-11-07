#!/usr/bin/env bats

load _test_helper

@test "do not replace fresh OCSP response when not forced" {
  fetch_sample_certs "valid example"

  run "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}" \
    --cert-name "valid example"

  ((status == 0))
  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]
  chmod u-w "${OUTPUT_DIR:?}/valid example.der"

  run "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}" \
    --cert-name "valid example"

  ((status == 0))
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+"not updated"[[:blank:]]+"valid staple file on disk"$ ]]
  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]
}
