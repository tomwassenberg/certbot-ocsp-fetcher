set \
  -o errexit \
  -o errtrace \
  -o pipefail
IFS=$'\n'

setup() {
  CERTS_DIR="$(mktemp --directory)"
  readonly CERTS_DIR
  mkdir -- "${CERTS_DIR}/live"

  OUTPUT_DIR="$(mktemp --directory)"
  readonly -- OUTPUT_DIR
}

prepare_multiple_lineages() {
  CERTS_DIR_MULTIPLE="$(mktemp --directory)"
  readonly CERTS_DIR_MULTIPLE
  mkdir -- "${CERTS_DIR_MULTIPLE}/live"
  cp -R "${CERTS_DIR}/live/valid/" "${CERTS_DIR_MULTIPLE}/live/example1"
  cp -R "${CERTS_DIR}/live/valid/" "${CERTS_DIR_MULTIPLE}/live/example2"
}

fetch_sample_certs() {
  if ! command -v curl >/dev/null; then
    echo >&2 "This test expects \`curl\` to be available in \$PATH."
    exit 1
  fi

  local -A tls_handshakes lineages_host lineages_leaf

  while [[ ${#} -gt 0 ]]; do
    case ${1} in
      valid)
        lineages_host[valid]="mozilla-modern.badssl.com"; shift
        ;;
      expired)
        lineages_host[expired]="expired.badssl.com"; shift
        ;;
      revoked)
        lineages_host[revoked]="revoked.badssl.com"; shift
        ;;
      *)
        exit 1
        ;;
    esac
  done

  for lineage in "${!lineages_host[@]}"; do
    mkdir "${CERTS_DIR}/live/${lineage}"

    # Perform a TLS handshake
    tls_handshakes["${lineage}"]="$(openssl s_client \
      -connect "${lineages_host["${lineage}"]}:443" \
      -servername "${lineages_host["${lineage}"]}" \
      2>/dev/null \
      </dev/null)"
    # Strip leading and trailing output, retaining only the leaf certificate as
    # printed by OpenSSL
    lineages_leaf["${lineage}"]="${tls_handshakes["${lineage}"]/#*-----BEGIN CERTIFICATE-----/-----BEGIN CERTIFICATE-----}"
    lineages_leaf["${lineage}"]="${lineages_leaf["${lineage}"]/%-----END CERTIFICATE-----*/-----END CERTIFICATE-----}"
    echo -n "${lineages_leaf["${lineage}"]}" > \
      "${CERTS_DIR}/live/${lineage}/cert.pem"

    # We don't need the complete certificate chain to determine that the leaf
    # certificate is expired.
    if [[ ${lineage} == "expired" ]]; then
      continue
    fi

    # Perform AIA fetching to retrieve the issuer's certificate
    local lineage_issuer_cert_url
    lineage_issuer_cert_url="$(openssl \
      x509 \
      -text \
      <<< "${lineages_leaf["${lineage}"]}" | \
      grep \
        --only-matching \
        --perl-regexp \
        '(?<=CA Issuers - URI:).+')"
    curl \
      --fail \
      --silent \
      --show-error \
      --location \
      --retry 3 \
      "${lineage_issuer_cert_url}" | \
      openssl x509 -inform DER \
      >"${CERTS_DIR}/live/${lineage}/chain.pem"
  done
}

teardown() {
  rm -rf -- "${CERTS_DIR}"/live/{valid,expired,revoked} "${OUTPUT_DIR}"

  if [[ -n "${CERTS_DIR_MULTIPLE:-}" ]]; then
    rm -rf -- "${CERTS_DIR_MULTIPLE}"
  fi
}
