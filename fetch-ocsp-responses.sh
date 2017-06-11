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

OCSP_HOST="ocsp.int-x3.letsencrypt.org"

for WEBSITE in $(find /etc/letsencrypt/live/ -type d | grep -o -P \
'(?<=/live/).+$')
do
  CERT_PATH="/etc/letsencrypt/live/${WEBSITE}" 1> /dev/null
  openssl ocsp -no_nonce -respout \
  "/etc/nginx/ocsp-cache/${WEBSITE}-ocsp-response.der" -issuer \
  "${CERT_PATH}/chain.pem" -cert "${CERT_PATH}/cert.pem" -verify_other \
  "${CERT_PATH}/chain.pem" -url "http://${OCSP_HOST}/" -header "HOST" \
  "${OCSP_HOST}" 1> /dev/null
done

echo "Fetching of OCSP responses successful!"