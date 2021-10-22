#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP response for a single valid certificate lineage" {
  fetch_sample_certs "valid example"

  run "${TOOL_COMMAND_LINE[@]}" \
    --certbot-dir "${CERTBOT_CONFIG_DIR}" \
    --cert-name "valid example"

  ((status == 0))
  [[ ${lines[2]} =~ ${SUCCESS_PATTERN} ]]
  [[ -f "${OUTPUT_DIR}/valid example.der" ]]
}
