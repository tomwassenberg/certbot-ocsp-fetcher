#!/usr/bin/env bats

load _test_helper

@test "fail when passing incompatible flags when ran as a deploy hook for Certbot" {
  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTBOT_DIR}/live/valid example" \
    run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher" \
      --cert-name "example"

  ((status != 0))
  [[ ${lines[0]} =~ ^error: ]]

  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTBOT_DIR}/live/valid example" \
    run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher" \
      --certbot-dir "${CERTBOT_DIR}"

  ((status != 0))
  [[ ${lines[0]} =~ ^error: ]]

  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTBOT_DIR}/live/valid example" \
    run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher" \
      --force-update

  ((status != 0))
  [[ ${lines[0]} =~ ^error: ]]

  [[ ! -e "${OUTPUT_DIR}/valid example.der" ]]
}
