#!/usr/bin/env bats

load _test_helper

@test "replace existing OCSP response when forced" {
  fetch_sample_certs "valid example"

  "${TOOL_COMMAND_LINE[@]:?}" \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --cert-name "valid example"

  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]

  run "${TOOL_COMMAND_LINE[@]:?}" \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --cert-name "valid example" \
    --force-update

  ((status == 0))
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+updated[[:blank:]]*$ ]]
  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]
}
