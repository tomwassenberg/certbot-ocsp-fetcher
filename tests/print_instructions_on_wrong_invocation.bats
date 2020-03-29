#!/usr/bin/env bats

@test "print usage instructions on wrong invocation" {
  run "${BATS_TEST_DIRNAME}/../certbot-ocsp-fetcher.sh" foo

  [[ ${status} != 0 ]]
  [[ ${output} =~ ^USAGE: ]]
}
