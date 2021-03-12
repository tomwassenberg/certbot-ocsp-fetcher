#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP response as a deploy hook for Certbot" {
  fetch_sample_certs "valid example"

  RENEWED_DOMAINS=foo \
    RENEWED_LINEAGE="${CERTBOT_CONFIG_DIR:?}/live/valid example" \
    run "${TOOL_COMMAND_LINE[@]:?}"

  ((status == 0))
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+updated[[:blank:]]*$ ]]
  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]
}
