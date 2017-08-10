#!/usr/bin/env bash

##
## This script cycles through all sites that have a certificate directory in
## Certbot's folder, and fetches an OCSP response from the OCSP URL embedded in
## the certificate. This primes the OCSP cache of nginx, because the OCSP
## responses get saved in locations that are referenced in the nginx
## configurations of the websites that use the certificates.
##
## USAGE: fetch-ocsp-responses.sh
##

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

# Generates file used by ssl_stapling_file in nginx config of websites
fetch_ocsp_response() {
  openssl ocsp \
    -no_nonce \
    -url "${OCSP_ENDPOINT}/" \
    -header "HOST" "${OCSP_HOST}" \
    -issuer "${CERT_DIRECTORY}/chain.pem" \
    -cert "${CERT_DIRECTORY}/cert.pem" \
    -verify_other "${CERT_DIRECTORY}/chain.pem" \
    -respout "/etc/nginx/ocsp-cache/${WEBSITE}-ocsp-response.der"
}

for WEBSITE in $(find /etc/letsencrypt/live/ -type d | grep -oP \
'(?<=/live/).+$')
do
  {
    CERT_DIRECTORY="/etc/letsencrypt/live/${WEBSITE}"
    OCSP_ENDPOINT="$(openssl x509 -noout -ocsp_uri -in \
    "${CERT_DIRECTORY}/cert.pem")"
    OCSP_HOST="$(echo "${OCSP_ENDPOINT}" | sed -e 's|^https://||' -e \
    's|^http://||')"

    fetch_ocsp_response
  } 1> /dev/null

done

/usr/sbin/service nginx reload

echo -e "\nFetching of OCSP responses successful! Nginx is reloaded to cache \
the new responses."
