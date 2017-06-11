#!/usr/bin/env bash

##
## This script cycles through all sites that have a certificate directory in
## Certbot's folder, and fetches an OCSP response from the OCSP URL embedded
## in the certificate. This primes the OCSP cache of nginx, because the OCSP
## responses get saved in locations that are referenced in the nginx
## configurations of the websites that use the certificates.
##
## USAGE: fetch-ocsp-responses.sh
##

# Unofficial Bash strict mode
set -eEfuo pipefail
IFS=$'\n\t'

for WEBSITE in $(find /etc/letsencrypt/live/ -type d | grep -o -P \
'(?<=/live/).+$')
do
  CERT_DIRECTORY="/etc/letsencrypt/live/${WEBSITE}" 1> /dev/null
  OCSP_HOST="$(openssl x509 -in "${CERT_DIRECTORY}/cert.pem" -text | grep \
  "OCSP - URI:" | cut -d/ -f3)"
  openssl ocsp -no_nonce -respout \
  "/etc/nginx/ocsp-cache/${WEBSITE}-ocsp-response.der" -issuer \
  "${CERT_DIRECTORY}/chain.pem" -cert "${CERT_DIRECTORY}/cert.pem" -verify_other \
  "${CERT_DIRECTORY}/chain.pem" -url "http://${OCSP_HOST}/" -header "HOST" \
  "${OCSP_HOST}" 1> /dev/null
done

echo "Fetching of OCSP responses successful!"