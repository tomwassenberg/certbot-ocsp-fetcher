#!/usr/bin/env bash

set -eEfuo pipefail
IFS=$'\n\t'
shopt -s inherit_errexit

(
  set +f
  shopt -s globstar nullglob

  shellcheck --enable all -- certbot-ocsp-fetcher ./**/*.{ba,}sh

  # We need to exclude SC2154 because of
  # https://github.com/koalaman/shellcheck/issues/1823
  shellcheck --enable all --exclude 2154 -- ./**/*.bats
)

shfmt -d -s .

# On CI we use Ubuntu 18.04, whose Bats version doesn't support parallelism
# yet.
if [[ ${CI:-} == true ]]; then
  bats --pretty ./tests
else
  bats --pretty --jobs 8 ./tests
fi
