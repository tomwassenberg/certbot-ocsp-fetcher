#!/usr/bin/env bats

load _test_helper

@test "fail when fetching OCSP response for revoked certificate" {
  fetch_sample_certs "revoked example" "valid example"

  if [[ ${CI:-} == true ]]; then
    certbot \
      --config-dir "${CERTBOT_CONFIG_DIR:?}" \
      --logs-dir "${CERTBOT_LOGS_DIR:?}" \
      --work-dir "${CERTBOT_WORK_DIR:?}" \
      revoke \
      --non-interactive \
      --staging \
      --no-delete-after-revoke \
      --reason superseded \
      --cert-name "revoked example"
  fi

  run "${TOOL_COMMAND_LINE[@]:?}" \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --cert-name "revoked example" \
    --cert-name "valid example"

  ((status != 0))
  [[ ${lines[2]} =~ ^"revoked example"[[:blank:]]+"failed to update"[[:blank:]]+revoked$ ]]
  [[ ${lines[3]} =~ ^"valid example"[[:blank:]]+updated[[:blank:]]*$ ]]
  [[ ! -e "${OUTPUT_DIR:?}/revoked example.der" && -e "${OUTPUT_DIR:?}/valid example.der" ]]
}
