#!/usr/bin/env bats

load _test_helper

@test "fail when fetching OCSP response for expired certificate" {
  fetch_sample_certs "expired example"

  local -ar tool_command_line=(
    "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}" \
    --cert-name "expired example"
  )

  if [[ ${CI:-} == true ]]; then
    # Use `faketime` to trick the tool into thinking this is an expired
    # certificate, by setting the system time to 90 days in the future. In
    # other words: hack time.
    run faketime "+90 days" "${tool_command_line[@]}"
  else
    run "${tool_command_line[@]}"
  fi

  ((status != 0))
  [[ ${lines[1]} =~ ^"expired example"[[:blank:]]+"not updated"[[:blank:]]+"leaf certificate expired"$ ]]
  [[ ! -e "${OUTPUT_DIR:?}/expired example.der" ]]
}
