set \
  -o errexit \
  -o errtrace \
  -o pipefail
IFS=$'\n'

setup() {
  OUTPUT_DIR="$(mktemp -d)"
  readonly -- OUTPUT_DIR

  if [[ ${CI:-} == "true" ]]; then
    CERTS_DIR=~/cert_examples
  else
    CERTS_DIR="${BATS_TEST_DIRNAME}/examples"
  fi
  # Because ShellCheck isn't aware that this script is sourced:
  # shellcheck disable=SC2034
  readonly CERTS_DIR

  CERTS_DIR_EMPTY="$(mktemp -d)"
  readonly CERTS_DIR_EMPTY
  mkdir -- "${CERTS_DIR_EMPTY}/live"

  CERTS_DIR_MULTIPLE="$(mktemp -d)"
  readonly CERTS_DIR_MULTIPLE
  mkdir -- "${CERTS_DIR_MULTIPLE}/live"
  cp -R "${CERTS_DIR}/live/valid/" "${CERTS_DIR_MULTIPLE}/live/example1"
  cp -R "${CERTS_DIR}/live/valid/" "${CERTS_DIR_MULTIPLE}/live/example2"
}

teardown() {
  rm -rf -- "${CERTS_DIR_EMPTY}"
  rm -rf -- "${CERTS_DIR_MULTIPLE}"
  rm -rf -- "${OUTPUT_DIR}"
}
