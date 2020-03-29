#!/usr/bin/env bats

load _test_helper

@test "fetch OCSP responses for empty lineage directory" {
  readonly CERT_DIR="$(mktemp -d)"
  mkdir "${CERT_DIR}/live"

  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" \
    --no-reload-webserver \
    --certbot-dir "${CERT_DIR}" \
    --output-dir "${OUTPUT_DIR}"

  [[ ${status} == 0 ]]
  [[ ${output} =~ ^LINEAGE[[:blank:]]+RESULT[[:blank:]]+REASON$ ]]

  rm -rf -- "${CERT_DIR}"
}
