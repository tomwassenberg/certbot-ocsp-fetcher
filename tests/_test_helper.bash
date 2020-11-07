set \
  -o errexit \
  -o errtrace \
  -o pipefail
IFS=$'\n'

# Use folders with trailing newlines in them, to test that these are
# handled properly as well. This employs a workaround, because trailing
# newlines are always stripped in a command substitution.
setup() {
  if [[ ${CI:-} == true ]]; then
    readonly CERTBOT_CONFIG_DIR=${CERTBOT_BASE_DIR:?}/conf
    readonly CERTBOT_LOGS_DIR=${CERTBOT_BASE_DIR:?}/logs
    readonly CERTBOT_WORK_DIR=${CERTBOT_BASE_DIR:?}/work
  else
    CERTBOT_CONFIG_DIR=$(
      mktemp --directory --suffix $'\n'
      echo x
    )
    CERTBOT_CONFIG_DIR=${CERTBOT_CONFIG_DIR%??}
    readonly CERTBOT_CONFIG_DIR
    [[ -d "${CERTBOT_CONFIG_DIR:?}/live" ]] ||
      mkdir "${CERTBOT_CONFIG_DIR:?}/live"
  fi

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
    case ${1:?} in
      "valid example")
        if [[ ${CI:-} == true ]]; then
          lineages_host["${1:?}"]="${CERT_DOMAIN_FOR_CI:?}"
        else
          lineages_host["${1:?}"]="mozilla-modern.badssl.com"
        fi
        shift
        ;;
      "expired example")
        if [[ ${CI:-} == true ]]; then
          lineages_host["${1:?}"]="${CERT_DOMAIN_FOR_CI:?}"
        else
          lineages_host["${1:?}"]="expired.badssl.com"
        fi
        shift
        ;;
      "revoked example")
        if [[ ${CI:-} == true ]]; then
          lineages_host["${1:?}"]="${CERT_DOMAIN_FOR_CI:?}"
        else
          lineages_host["${1:?}"]="revoked.badssl.com"
        fi
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
    if [[ ${CI:-} == true ]]; then
      certbot \
        --config-dir "${CERTBOT_CONFIG_DIR:?}" \
        --logs-dir "${CERTBOT_LOGS_DIR:?}" \
        --work-dir "${CERTBOT_WORK_DIR:?}" \
        certonly \
        --non-interactive \
        --staging \
        --manual \
        --preferred-challenges=http \
        --manual-auth-hook /bin/true \
        --domains "${lineages_host["${lineage_name:?}"]}" \
        --cert-name "${lineage_name:?}"
    else
      local tls_handshake lineage_chain lineage_leaf

      mkdir -- "${CERTBOT_CONFIG_DIR:?}/live/${lineage_name:?}"

      # Perform a TLS handshake
      tls_handshake="$(openssl s_client \
        -connect "${lineages_host["${lineage_name:?}"]}:443" \
        -servername "${lineages_host["${lineage_name:?}"]}" \
        -showcerts \
        2>/dev/null \
        </dev/null)"

      # Strip leading and trailing output, retaining only the certificate chain
      # as printed by OpenSSL
      lineage_chain="${tls_handshake#*-----BEGIN CERTIFICATE-----}"
      lineage_chain="-----BEGIN CERTIFICATE-----${lineage_chain:?}"
      lineage_chain="${lineage_chain%-----END CERTIFICATE-----*}"
      lineage_chain="${lineage_chain:?}-----END CERTIFICATE-----"

      # Strip all certificates except the first, retaining only the leaf
      # certificate as printed by OpenSSL
      lineage_leaf="${lineage_chain/%-----END CERTIFICATE-----*/-----END CERTIFICATE-----}"
      printf '%s\n' "${lineage_leaf:?}" > \
        "${CERTBOT_CONFIG_DIR:?}/live/${lineage_name:?}/cert.pem"

      # Strip first (i.e. leaf) certificate from chain
      lineage_chain="${lineage_chain#*-----END CERTIFICATE-----$'\n'}"
      printf '%s\n' "${lineage_chain:?}" > \
        "${CERTBOT_CONFIG_DIR:?}/live/${lineage_name:?}/chain.pem"

      unset tls_handshake lineage_chain lineage_leaf
    fi
  done

  if [[ ${multiple:-} == true ]]; then
    mv \
      "${CERTBOT_CONFIG_DIR:?}/live/valid example/" \
      "${CERTBOT_CONFIG_DIR:?}/live/valid example 1"
    cp -R \
      "${CERTBOT_CONFIG_DIR:?}/live/valid example 1/" \
      "${CERTBOT_CONFIG_DIR:?}/live/valid example 2"
    cp -R \
      "${CERTBOT_CONFIG_DIR:?}/live/valid example 1/" \
      "${CERTBOT_CONFIG_DIR:?}/live/valid example 3"
  fi

  # To test for the bug that was fixed in 87fbdcc.
  touch -- "${CERTBOT_CONFIG_DIR:?}/live/dummy_file"
}

teardown() {
  rm -fr -- \
    "${CERTBOT_CONFIG_DIR:?}"/{archive,csr,live,keys,renewal} \
    "${OUTPUT_DIR:?}"
}
