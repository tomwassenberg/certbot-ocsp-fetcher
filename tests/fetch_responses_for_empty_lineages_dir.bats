#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses for empty lineage directory" {
  run "${TOOL_COMMAND_LINE[@]}" --certbot-dir "${CERTBOT_CONFIG_DIR}"
  [[ ${lines[1]} =~ ${HEADER_PATTERN} ]]

  output_stdout=$(2>/dev/null "${TOOL_COMMAND_LINE[@]}" --certbot-dir "${CERTBOT_CONFIG_DIR}")
  [[ -z ${output_stdout} ]]
}
