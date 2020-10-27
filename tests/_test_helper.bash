set \
  -o errexit \
  -o errtrace \
  -o pipefail
IFS=$'\n'

# Use folders with trailing newlines in them, to test that these are
# handled properly as well. This employs a workaround, because trailing
# newlines are always stripped in a command substitution.
setup() {
  CERTBOT_DIR=$(
    mktemp --directory --suffix $'\n'
    echo x
  )
  CERTBOT_DIR=${CERTBOT_DIR%??}
  readonly CERTBOT_DIR
  mkdir -- "${CERTBOT_DIR}/live"
  touch -- "${CERTBOT_DIR}/live/dummy_file"

  OUTPUT_DIR=$(
    mktemp --directory --suffix $'\n'
    echo x
  )
  OUTPUT_DIR=${OUTPUT_DIR%??}
  readonly OUTPUT_DIR
}

fetch_sample_certs() {
  local -A lineages_host

  while ((${#} > 0)); do
    case ${1} in
      "valid example")
        lineages_host["${1}"]="mozilla-modern.badssl.com"
        shift
        ;;
      "expired example")
        lineages_host["${1}"]="expired.badssl.com"
        shift
        ;;
      "revoked example")
        lineages_host["${1}"]="revoked.badssl.com"
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
    local tls_handshake lineage_chain lineage_leaf

    mkdir -- "${CERTBOT_DIR}/live/${lineage_name}"

    # Perform a TLS handshake
    tls_handshake="$(openssl s_client \
      -connect "${lineages_host["${lineage_name}"]}:443" \
      -servername "${lineages_host["${lineage_name}"]}" \
      -showcerts \
      2>/dev/null \
      </dev/null)"

    # Strip leading and trailing output, retaining only the certificate chain
    # as printed by OpenSSL
    lineage_chain="${tls_handshake#*-----BEGIN CERTIFICATE-----}"
    lineage_chain="-----BEGIN CERTIFICATE-----${lineage_chain}"
    lineage_chain="${lineage_chain%-----END CERTIFICATE-----*}"
    lineage_chain="${lineage_chain}-----END CERTIFICATE-----"

    # Strip all certificates except the first, retaining only the leaf
    # certificate as printed by OpenSSL
    lineage_leaf="${lineage_chain/%-----END CERTIFICATE-----*/-----END CERTIFICATE-----}"
    printf '%s\n' "${lineage_leaf}" > \
      "${CERTBOT_DIR}/live/${lineage_name}/cert.pem"

    # Strip first (i.e. leaf) certificate from chain
    lineage_chain="${lineage_chain#*-----END CERTIFICATE-----$'\n'}"
    printf '%s\n' "${lineage_chain}" > \
      "${CERTBOT_DIR}/live/${lineage_name}/chain.pem"

    if [[ ${multiple} == true ]]; then
      mv "${CERTBOT_DIR}/live/${lineage_name}/" "${CERTBOT_DIR}/live/${lineage_name} 1"
      cp -R "${CERTBOT_DIR}/live/${lineage_name} 1/" "${CERTBOT_DIR}/live/${lineage_name} 2"
      cp -R "${CERTBOT_DIR}/live/${lineage_name} 1/" "${CERTBOT_DIR}/live/${lineage_name} 3"
    fi

    unset tls_handshake lineage_chain lineage_leaf
  done
}

teardown() {
  rm -rf -- "${CERTBOT_DIR}" "${OUTPUT_DIR}"
}
