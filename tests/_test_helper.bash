set \
  -o errexit \
  -o errtrace \
  -o pipefail
IFS=$'\n'

setup() {
  CERTBOT_DIR="$(mktemp --directory)"
  readonly CERTBOT_DIR
  mkdir -- "${CERTBOT_DIR}/live"

  OUTPUT_DIR="$(mktemp --directory)"
  readonly -- OUTPUT_DIR
}

fetch_sample_certs() {
  if ! command -v curl >/dev/null; then
    # shellcheck disable=2016
    echo >&2 'This test expects `curl` to be available in $PATH.'
    exit 1
  fi

  local -A tls_handshakes lineages_host lineages_leaf

  while [[ ${#} -gt 0 ]]; do
    case ${1} in
      valid)
        lineages_host[valid]="mozilla-modern.badssl.com"
        shift
        ;;
      expired)
        lineages_host[expired]="expired.badssl.com"
        shift
        ;;
      revoked)
        lineages_host[revoked]="revoked.badssl.com"
        shift
        ;;
      --multiple)
        local -l multiple=true
        shift
        ;;
      *)
        exit 1
        ;;
    esac
  done

  for lineage_name in "${!lineages_host[@]}"; do
    mkdir -- "${CERTBOT_DIR}/live/${lineage_name}"

    # Perform a TLS handshake
    tls_handshakes["${lineage_name}"]="$(openssl s_client \
      -connect "${lineages_host["${lineage_name}"]}:443" \
      -servername "${lineages_host["${lineage_name}"]}" \
      2>/dev/null \
      </dev/null)"
    # Strip leading and trailing output, retaining only the leaf certificate as
    # printed by OpenSSL
    lineages_leaf["${lineage_name}"]="${tls_handshakes["${lineage_name}"]/#*-----BEGIN CERTIFICATE-----/-----BEGIN CERTIFICATE-----}"
    lineages_leaf["${lineage_name}"]="${lineages_leaf["${lineage_name}"]/%-----END CERTIFICATE-----*/-----END CERTIFICATE-----}"
    echo -n "${lineages_leaf["${lineage_name}"]}" > \
      "${CERTBOT_DIR}/live/${lineage_name}/cert.pem"

    # We don't need the complete certificate chain to determine that the leaf
    # certificate is expired.
    if [[ ${lineage_name} == "expired" ]]; then
      continue
    fi

    # Perform AIA fetching to retrieve the issuer's certificate
    local lineage_issuer_cert_url
    lineage_issuer_cert_url="$(openssl \
      x509 \
      -text \
      <<<"${lineages_leaf["${lineage_name}"]}" |
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
      "${lineage_issuer_cert_url}" |
      openssl x509 -inform DER \
        >"${CERTBOT_DIR}/live/${lineage_name}/chain.pem"

    if [[ ${multiple} == "true" ]]; then
      mv "${CERTBOT_DIR}/live/${lineage_name}/" "${CERTBOT_DIR}/live/${lineage_name}1"
      cp -R "${CERTBOT_DIR}/live/${lineage_name}1/" "${CERTBOT_DIR}/live/${lineage_name}2"
      cp -R "${CERTBOT_DIR}/live/${lineage_name}1/" "${CERTBOT_DIR}/live/${lineage_name}3"
    fi
  done
}

teardown() {
  rm -rf -- "${CERTBOT_DIR}"/live/{valid,expired,revoked} "${OUTPUT_DIR}"
}
