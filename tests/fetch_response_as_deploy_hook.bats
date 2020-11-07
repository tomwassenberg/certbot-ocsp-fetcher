#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP response as a deploy hook for Certbot" {
  fetch_sample_certs "valid example"

  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTBOT_CONFIG_DIR:?}/live/valid example" \
    run "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
      --no-reload-webserver \
      --output-dir "${OUTPUT_DIR:?}"

  ((status == 0))
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+updated$ ]]
  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]
}
