#!/usr/bin/env bats

load _test_helper

@test "replace existing expired OCSP response" {
  cp tests/examples/expired_response.der "${OUTPUT_DIR}/valid.der"
  PREV_RESPONSE_CHECKSUM="$(sha256sum "${OUTPUT_DIR}/valid.der")"

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${BATS_TEST_DIRNAME}/examples" \
    --output-dir "${OUTPUT_DIR}" \
    --cert-name valid

  [[ ${status} == 0 ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]
  [[ ${lines[1]} =~ ^valid[[:blank:]]+updated$ ]]

  CUR_RESPONSE_CHECKSUM="$(sha256sum "${OUTPUT_DIR}/valid.der")"
  [[ ${CUR_RESPONSE_CHECKSUM} != "${PREV_RESPONSE_CHECKSUM}" ]]
}
