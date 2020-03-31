#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP response as a deploy hook for Certbot" {
  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTS_DIR}/live/valid" \
    run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
      --no-reload-webserver \
      --output-dir "${OUTPUT_DIR}"

  [[ ${status} == 0 ]]
  [[ ${lines[1]} =~ ^valid[[:blank:]]+updated$ ]]
  [[ -f "${OUTPUT_DIR}/valid.der" ]]
}
