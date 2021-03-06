#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP response for a single valid certificate lineage" {
  fetch_sample_certs "valid example"

  run "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}" \
    --cert-name "valid example"

  ((status == 0))
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+updated[[:blank:]]*$ ]]
  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]
}
