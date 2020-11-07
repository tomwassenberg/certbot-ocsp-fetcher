#!/usr/bin/env bats

load _test_helper

@test "replace existing expired OCSP response" {
  fetch_sample_certs "valid example"

  cp \
    "${BATS_TEST_DIRNAME:?}/examples/ocsp_response_expired.der" \
    "${OUTPUT_DIR:?}/valid example.der"
  PREV_RESPONSE_CHECKSUM=$(sha256sum "${OUTPUT_DIR:?}/valid example.der")

  run "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}" \
    --cert-name "valid example"

  ((status == 0))
  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+updated$ ]]

  CUR_RESPONSE_CHECKSUM=$(sha256sum "${OUTPUT_DIR:?}/valid example.der")
  [[ ${CUR_RESPONSE_CHECKSUM:?} != "${PREV_RESPONSE_CHECKSUM:?}" ]]
}
