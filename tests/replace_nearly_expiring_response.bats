#!/usr/bin/env bats

load _test_helper

@test "replace nearly-expiring OCSP response" {
  fetch_sample_certs "valid example"

  run "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
    --no-reload-webserver \
    --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
    --output-dir "${OUTPUT_DIR:?}" \
    --cert-name "valid example"

  ((status == 0))
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+updated[[:blank:]]*$ ]]
  [[ -f "${OUTPUT_DIR:?}/valid example.der" ]]

  # Create hard link to initial staple file, so the device and inode
  # numbers match, and can be used after the second run to determine that the
  # staple file has been replaced.
  ln "${OUTPUT_DIR:?}/"{valid,initial}" example.der"
  [[ \
    "${OUTPUT_DIR:?}/valid example.der" -ef \
    "${OUTPUT_DIR:?}/initial example.der" ]]

  # We skew the time by 3,5 days in the future, because that is half of the
  # common lifetime of an OCSP response; 7 days. The tool is setup to renew
  # responses when they're over half of their lifetime, so this mimics that
  # scenario. Note that this would fail if:
  #   - a response's lifetime is <3,5 days, because then the skewed clock would
  #   make it fail the validity check on the replacement OCSP response.
  #  - a response's lifetime is >7 days, because then the pre-existing OCSP
  #    response wouldn't have reached its halftime yet.
  run faketime \
    -f "+3.5 days" \
    "${BATS_TEST_DIRNAME:?}/../certbot-ocsp-fetcher" \
      --no-reload-webserver \
      --certbot-dir "${CERTBOT_CONFIG_DIR:?}" \
      --output-dir "${OUTPUT_DIR:?}" \
      --cert-name "valid example"

  ((status == 0))
  [[ ${lines[1]} =~ ^"valid example"[[:blank:]]+updated[[:blank:]]*$ ]]

  # Compare device and inode numbers of staple file and temporary hard link, to
  # make sure that the staple file has been replaced.
  [[ ! \
    "${OUTPUT_DIR:?}/valid example.der" -ef \
    "${OUTPUT_DIR:?}/initial example.der" ]]
}
