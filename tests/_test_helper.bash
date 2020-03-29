set \
  -o errexit \
  -o errtrace \
  -o pipefail
IFS=$'\n'

setup() {
  OUTPUT_DIR="$(mktemp -d)"
  readonly -- OUTPUT_DIR
}

teardown() {
  rm -rf -- "${OUTPUT_DIR}"
}
