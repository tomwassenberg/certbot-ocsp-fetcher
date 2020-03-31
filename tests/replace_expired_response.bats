#!/usr/bin/env bats

load _test_helper

@test "replace existing expired OCSP response" {
  cp "${CERTS_DIR}/ocsp_response_expired.der" "${OUTPUT_DIR}/valid.der"
  PREV_RESPONSE_CHECKSUM="$(sha256sum "${OUTPUT_DIR}/valid.der")"

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERTS_DIR}" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name valid

  [[ ${status} == 0 ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]
  [[ ${lines[1]} =~ ^valid[[:blank:]]+updated$ ]]

  CUR_RESPONSE_CHECKSUM="$(sha256sum "${OUTPUT_DIR}/valid.der")"
  [[ ${CUR_RESPONSE_CHECKSUM} != "${PREV_RESPONSE_CHECKSUM}" ]]
}
