#!/usr/bin/env bats

load _test_helper

@test "fail when passing incompatible flags when ran as a deploy hook for Certbot" {
  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTS_DIR}/live/valid" \
    run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
      --cert-name "example"

  [[ ${status} != 0 ]]
  [[ ${lines[0]} =~ ^error: ]]

  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTS_DIR}/live/valid" \
    run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
      --certbot-dir "${CERTS_DIR}"

  [[ ${status} != 0 ]]
  [[ ${lines[0]} =~ ^error: ]]

  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTS_DIR}/live/valid" \
    run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
      --force-update

  [[ ${status} != 0 ]]
  [[ ${lines[0]} =~ ^error: ]]

  [[ ! -e "${OUTPUT_DIR}/valid.der" ]]
}
