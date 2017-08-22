# certbot-ocsp-fetcher
This script fetches and verifies OCSP responses, to be used by nginx, utilizing
the OCSP URL embedded in a certificate. This primes the OCSP cache of nginx,
because the OCSP responses get saved in locations that can be referenced in the
nginx configurations of the websites that use the certificates. The script can
behave in two ways.

When this script is called by Certbot as a deploy/renew hook, this is recognized 
by checking if the variables are set that Certbot passes to its deploy hooks. In
this case only the OCSP response for the specific website whose certificate
is (re)issued by Certbot, is fetched.

When Certbot's variables are not passed, the script cycles through all sites
that have a certificate directory in Certbot's folder, and fetches an OCSP
response.


## Dependencies
- bash
- openssl (tested with 1.0.2g)
- Certbot >= 0.5.0
- nginx (tested with 1.10.3)

## Usage

The script should be run with superuser privileges, because it needs access to
the directory Certbot stores its certificates in (`/etc/letsencrypt/live`). It
can be run as follows:

```
# chmod a+x certbot-ocsp-fetcher.sh
# certbot-ocsp-fetcher.sh
```

Or alternatively:

`# bash certbot-ocsp-fetcher.sh`

When you want to use this as a deploy hook (Certbot >= 0.17.0), use the Certbot 
command you would normally use when requesting a certificate, but add 
`--deploy-hook "/path/to/certbot-ocsp-fetcher.sh"`.

When you can't use Certbot >= 0.17.0 yet, use the `--renew-hook` flag instead. 
The difference between `--deploy-hook` and `--renew-hook` is that a renew-hook 
is not invoked on the first issuance of a certificate, only on its renewals. Be 
aware that in Certbot < 0.10.0, hooks were [not saved] in the renewal 
configuration of a certificate.

 [not saved]: https://github.com/certbot/certbot/issues/3394
