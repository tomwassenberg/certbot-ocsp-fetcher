#!/usr/bin/env bash

##
## This script fetches OCSP responses, to be used by nginx, utilizing the OCSP
## URL embedded in a certificate. This primes the OCSP cache of nginx, because
## the OCSP responses get saved in locations that can be referenced in the nginx
## configurations of the websites that use the certificates. The script can
## behave in two ways.
##
## When this script is called by Certbot as a deploy hook, this is recognized by
## checking if the variables are set that Certbot passes to its deploy hooks. In
## this case only the OCSP response for the specific website whose certificate
## is (re)issued by Certbot, is fetched.
##
## When Certbot's variables are not passed, the script cycles through all sites
## that have a certificate directory in Certbot's folder, and fetches an OCSP
## response.
##
## USAGE: fetch-ocsp-responses.sh
##

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

process_website_list() {
  # These two variables are set if this script is invoked by Certbot
  if [[ -z ${RENEWED_DOMAINS+x} || -z ${RENEWED_LINEAGE+x} ]]; then
      # Run in "check every certificate" mode
      FETCH_ALL="1"
      CERT_DIRECTORY="/etc/letsencrypt/live"

      for CERT_NAME in $(find ${CERT_DIRECTORY} -type d | grep -oP \
      '(?<=/live/).+$')
      do
        fetch_ocsp_response "${CERT_DIRECTORY}/${CERT_NAME}" "${CERT_NAME}"
      done
      unset CERT_NAME
  else
      # Run in Certbot mode, only checking the passed certificate
      FETCH_ALL="0"

      fetch_ocsp_response "${RENEWED_LINEAGE}" "$(echo "${RENEWED_LINEAGE}" | \
      awk -F '/' '{print $NF}')"
  fi 1> /dev/null
}

# Generates file used by ssl_stapling_file in nginx config of websites
fetch_ocsp_response() {
  # Enforce that the OCSP URL is always plain HTTP, because HTTPS URL's are not
  # explicitly prohibited by the BR, but they are by Mozilla's recommended
  # practices.
  local OCSP_ENDPOINT
  OCSP_ENDPOINT="$(openssl x509 -noout -ocsp_uri -in "${1}/cert.pem" | sed -e \
  's|^https|http|')"
  local OCSP_HOST
  OCSP_HOST="$(echo "${OCSP_ENDPOINT}" | awk -F '/' '{print $3}')"

  # Request, verify and save the actual OCSP response
  openssl ocsp \
    -no_nonce \
    -url "${OCSP_ENDPOINT}" \
    -header "HOST" "${OCSP_HOST}" \
    -issuer "${1}/chain.pem" \
    -cert "${1}/cert.pem" \
    -verify_other "${1}/chain.pem" \
    -respout "/etc/nginx/ocsp-cache/${2}-ocsp-response.der" \
    2> /dev/null
}

# Check for sudo/root access, because it needs to access certificates,
# write to /etc/nginx and reload the nginx service.
if [[ "${EUID}" != "0" ]]; then
  echo "This script can only be run with superuser privileges."
  exit 1
fi

process_website_list

# Reload nginx to cache the new OCSP responses in memory
/usr/sbin/service nginx reload 1> /dev/null

# Only output success message if not run as Certbot hook
if [[ "${FETCH_ALL}" == "1" ]]; then
  echo "Fetching of OCSP response(s) successful! nginx is reloaded to cache any new responses."
fi
