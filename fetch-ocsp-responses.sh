#!/usr/bin/env bash

##
## This script fetches OCSP responses, to be used by nginx, utilizing the OCSP
## URL embedded in a certificate. This primes the OCSP cache of nginx, because
## the OCSP responses get saved in locations that can be referenced in the nginx
## configurations of the websites that use the certificates. It can be used in
## two modes.
##
## When this script is called by Certbot as a deploy hook, Certbot passes the
## "--certbot-deploy-hook" flag. In this case only the OCSP response for the
## specific website whose certificate is (re)issued by Certbot, is fetched.
##
## When "--all" is passed, the script cycles through all sites that have a
## certificate directory in Certbot's folder, and fetches an OCSP response.
##
## USAGE: fetch-ocsp-responses.sh [--certbot-deploy-hook] [--all]
##

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

USAGE='USAGE: fetch-ocsp-responses.sh [--certbot-deploy-hook] [--all]'

print_to_stderr() {
  echo 1>&2 "${1}"
}

# Generates file used by ssl_stapling_file in nginx config of websites
fetch_ocsp_response() {
  # Enforce that the OCSP URL is always plain HTTP, because HTTPS URL's are not
  # explicitly prohibited by the BR, but they are by Mozilla's recommended
  # practices.
  OCSP_ENDPOINT="$(openssl x509 -noout -ocsp_uri -in \
  "${CERT_SUBDIRECTORY}/cert.pem" | sed -e 's|^https|http|' )"
  OCSP_HOST="$(echo "${OCSP_ENDPOINT}" | awk -F/ '{print $3}')"

  openssl ocsp \
    -no_nonce \
    -url "${OCSP_ENDPOINT}" \
    -header "HOST" "${OCSP_HOST}" \
    -issuer "${CERT_SUBDIRECTORY}/chain.pem" \
    -cert "${CERT_SUBDIRECTORY}/cert.pem" \
    -verify_other "${CERT_SUBDIRECTORY}/chain.pem" \
    -respout "/etc/nginx/ocsp-cache/${WEBSITE}-ocsp-response.der" \
    2> /dev/null
}

if [[ "${EUID}" != "0" ]]; then
  echo "This script can only be run with superuser privileges."
  exit 1
fi

if [[ -z ${1+x} ]]; then
  print_to_stderr "${USAGE}"
  exit 1
fi

case "${1}" in
  --certbot-deploy-hook)
    {
      if [[ -z ${RENEWED_DOMAINS+x} || -z ${RENEWED_LINEAGE+x} ]]; then
        print_to_stderr "ERROR: This parameter can only be used from Certbot, for when it runs this script as a deploy hook."
        exit 1
      fi

      WEBSITE="$(echo "${RENEWED_DOMAINS}" | awk '{print $1}')"
      CERT_SUBDIRECTORY="${RENEWED_LINEAGE}"

      fetch_ocsp_response
    } 1> /dev/null
    ;;
  --all)
    {
      CERT_DIRECTORY="/etc/letsencrypt/live"

      for WEBSITE in $(find ${CERT_DIRECTORY} -type d | grep -oP \
      '(?<=/live/).+$')
      do
        CERT_SUBDIRECTORY="${CERT_DIRECTORY}/${WEBSITE}"

        fetch_ocsp_response
      done
    } 1> /dev/null
    ;;
  *)
    print_to_stderr "${USAGE}"
    exit 1
esac

/usr/sbin/service nginx reload 1> /dev/null

if [[ "${1}" == "--all" ]]; then
  echo "Fetching of OCSP responses successful! nginx is reloaded to cache the new responses."
fi
