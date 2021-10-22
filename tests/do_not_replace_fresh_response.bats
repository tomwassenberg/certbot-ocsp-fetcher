#!/usr/bin/env bats

load _test_helper

@test "do not replace fresh OCSP response when not forced" {
  fetch_sample_certs "valid example"

  "${TOOL_COMMAND_LINE[@]}" \
    --certbot-dir "${CERTBOT_CONFIG_DIR}" \
    --cert-name "valid example"

  [[ -f "${OUTPUT_DIR}/valid example.der" ]]
  chmod u-w "${OUTPUT_DIR}/valid example.der"

  run "${TOOL_COMMAND_LINE[@]}" \
    --certbot-dir "${CERTBOT_CONFIG_DIR}" \
    --cert-name "valid example"

  ((status == 0))
  [[ ${lines[2]} =~ ^"valid example"[[:blank:]]+"not updated"[[:blank:]]+"valid staple file on disk"$ ]]
  [[ -f "${OUTPUT_DIR}/valid example.der" ]]
}
