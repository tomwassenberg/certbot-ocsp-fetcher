#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses for empty lineage directory" {
  output=$("${TOOL_COMMAND_LINE[@]:?}" --certbot-dir "${CERTBOT_CONFIG_DIR:?}")

  [[ ${output:?} =~ ^LINEAGE[[:blank:]]+RESULT[[:blank:]]+REASON$ ]]
}
