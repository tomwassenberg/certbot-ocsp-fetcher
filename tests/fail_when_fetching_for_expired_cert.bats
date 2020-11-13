#!/usr/bin/env bats

load _test_helper

@test "fail when fetching OCSP response for expired certificate" {
  local -ar tool_command_line=(
    "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}"
  )

  if [[ ${CI:-} == true ]]; then
    fetch_sample_certs "expired example"

    # Use `faketime` to trick the tool into thinking this is an expired
    # certificate, by setting the system time to 90 days in the future. In
    # other words: hack time.
    # This does mean that we can't test that a _valid_ example is still fetched
    # for successfully, because this affects all lineages in the run.
    run faketime "+90 days" "${tool_command_line[@]}"

    ((status != 0))
  else
    fetch_sample_certs "expired example" "valid example"

    run "${tool_command_line[@]}"

    ((status != 0))
    [[ ${lines[2]} =~ ^"valid example"[[:blank:]]+updated[[:blank:]]*$ ]]
    [[ -e "${OUTPUT_DIR:?}/valid example.der" ]]
  fi
  [[ ${lines[1]} =~ ^"expired example"[[:blank:]]+"not updated"[[:blank:]]+"leaf certificate expired"$ ]]
  [[ ! -e "${OUTPUT_DIR:?}/expired example.der" ]]
}
