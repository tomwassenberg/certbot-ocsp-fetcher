# certbot-ocsp-fetcher
`certbot-ocsp-fetcher` helps you setup OCSP stapling in nginx. It's a Bash
script that fetches and verifies OCSP responses for TLS certificates issued with
[Certbot], to be used by nginx. This primes the OCSP cache of nginx, which is
needed because of nginx's flawed implementation (see bug [#812]). In order for
all this to be useful, you should know how to correctly set up OCSP stapling in
nginx, for which you can take a look at [Mozilla's SSL Configuration Generator]
for instance. If you use Certbot's `nginx` plugin, you can also add the
`--staple-ocsp` flag to your `certbot --nginx` command(s) to configure OCSP
stapling.

The script works by utilizing the OCSP URL embedded in a certificate, and saving
the OCSP responses in staples that can be referenced in the nginx
configurations of the websites that use the certificates. The script can behave
in two ways.

When this script is called by Certbot as a deploy/renew hook, this is
recognized by checking if the variables are set that Certbot passes to its
deploy hooks. In this case only the OCSP response for the specific certificate
that is (re)issued by Certbot, is fetched.

When Certbot's variables are not passed, the script cycles through all sites
that have a certificate lineage in Certbot's folder, and fetches an OCSP
response.

The use of this script makes sure OCSP stapling in nginx works reliably, which
makes e.g. the adoption of [OCSP Must-Staple] possible.

## Dependencies
- bash
- openssl (tested with 1.0.2g)
- Certbot >=0.5.0
- nginx (tested with 1.10.3)

## Usage
The script should be run with privileges that allow it to access the directory
that Certbot stores its certificates in (by default `/etc/letsencrypt/live`).
You should run it daily, for instance by using the included systemd service +
timer, or by adding it to the user's crontab. It can be run as follows:

`# ./certbot-ocsp-fetcher.sh [-c/--certbot-dir DIRECTORY]
[-n/--cert-name CERTNAME] [-o/--output-dir DIRECTORY]`

The filename of the OCSP staple is the name of the certificate lineage (as used
by Certbot) with the DER extension. Be sure to point nginx to the staple(s) by
using the `ssl_stapling_file` directive in the nginx configuration of the
website, so e.g. `ssl_stapling_file /etc/nginx/ocsp-cache/example.com.der;`.

When you want to use this tool as a deploy hook (available in Certbot >=0.17.0),
append `--deploy-hook "/path/to/certbot-ocsp-fetcher.sh"` to the Certbot command
you would normally use when requesting a certificate.

When you can't use Certbot >=0.17.0, use the `--renew-hook` flag instead. The
difference between `--deploy-hook` and `--renew-hook` is that a renew hook is
not invoked during the first issuance in a certificate lineage, but only during
its renewals. Be aware that in Certbot <0.10.0, hooks were [not saved] in the
renewal configuration of a certificate.

**Note:** If there is an OCSP staple with the target name already existing in
the output directory which doesn't expire within two days, a new OCSP response
will **not** be fetched.

### CLI parameters
- `-c, --certbot-dir`\
  Specify the configuration directory of the Certbot instance, that is used to
  process the certificates. When not passed, this defaults to
  `/etc/letsencrypt`.\
  Note that this doesn't apply when the script is used as a Certbot hook, since
  the path to Certbot and the certificate is inferred from the call that Certbot
  makes.

- `-n,--cert-name`\
  Specify the name of the certificate lineage (as used by Certbot) that you want
  to fetch an OCSP response for.

- `-o,--output-dir`\
  Specify the directory where OCSP staple files are saved. When not passed, this
  defaults to `/etc/nginx/ocsp-cache`.

 [Certbot]: https://github.com/certbot/certbot
 [#812]: https://trac.nginx.org/nginx/ticket/812
 [Mozilla's SSL Configuration Generator]: https://mozilla.github.io/server-side-tls/ssl-config-generator/
 [OCSP Must-Staple]: https://scotthelme.co.uk/ocsp-must-staple/
 [not saved]: https://github.com/certbot/certbot/issues/3394
