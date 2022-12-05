# certbot-ocsp-fetcher
`certbot-ocsp-fetcher` helps you setup OCSP stapling in nginx. The tool primes
nginx's OCSP cache to work around nginx's flawed OCSP stapling implementation
(see bug [#812]). The tool does this by fetching and saving OCSP responses for
TLS certificates issued with [Certbot].

In order for all this to be useful, you should know how to set up OCSP stapling
in nginx. For this, you can take a look at [Mozilla's SSL Configuration
Generator] for instance. If you use Certbot's `nginx` plugin, you can also add
the `--staple-ocsp` flag to your `certbot --nginx` command(s) to configure OCSP
stapling.

The tool works by utilizing the OCSP Responder URL embedded in a certificate
and saving the OCSP responses in staple files. These staple files can be
referenced in the nginx configurations of the websites that use the
certificates. The tool can behave in two ways:

- Certbot can invoke the tool as a deploy/renew hook (possible in Certbot
  \>=0.17.0). In this case, the tool ensures an up-to-date OCSP staple file is
  present on disk for the specific certificate that was issued using Certbot.

- You can invoke the tool directly. In this case, the tool cycles through all
  sites that have a certificate lineage in Certbot's folder and ensures an
  up-to-date OCSP staple file is present on disk.

The use of this tool makes sure OCSP stapling in nginx works reliably. As a
consequence, this allows you to use [OCSP Must-Staple].

## Dependencies
- Bash 4.3+
- Certbot 0.5.0+
- nginx (tested with 1.14.0)\
  Optional if `--no-reload-webserver` (see below) is passed.
- OpenSSL 1.1.0+
- BSD's `column`\
  Optional. For machine-readable TSV output, the version needs to support the
  `--output-separator` flag. This is satisfied in e.g. Debian 11 and Ubuntu
  20.10+.

For running the tests, [Bats] is also required.

## Usage
Invoke the tool as follows:

`# ./certbot-ocsp-fetcher [OPTION]...`

The filename of a resulting OCSP staple is the name of the certificate lineage
(as used by Certbot) with the `der` extension appended. Be sure to point nginx
to the staple file(s) by using the `ssl_stapling_file` directive in the nginx
configuration of the website. For instance, by including: `ssl_stapling_file
/var/cache/certbot-ocsp-fetcher/example.com.der;`, where
`/var/cache/certbot-ocsp-fetcher` is the default output directory when using
the [supplied systemd service].

Invoke the tool with privileges that allow it to access the directory that
Certbot stores its certificates in (by default `/etc/letsencrypt/live`). You
should run the tool daily, for instance by one of the following options:

- using the included systemd service + timer
- adding an entry for the tool to the user's crontab

As mentioned above, you can use this tool as a deploy hook for Certbot. To do
this, append `--deploy-hook "/path/to/certbot-ocsp-fetcher"` to the Certbot
command you currently use when requesting a certificate.

**Note:** If an existing OCSP staple file is still valid for more than half of
its lifetime, it will **not** be updated. If you need to override this
behavior, use the`-f/--force-update` flag (see below).

### Command line options
This is a listing of all the command line options that can be passed to the
tool:

- `-c DIRECTORY, --certbot-dir=DIRECTORY`\
  Specify the configuration directory of the Certbot instance that is used to
  process the certificates. When not specified, this defaults to
  `/etc/letsencrypt`.\
  This flag cannot be used when the tool is invoked as a deploy hook by
  Certbot. In that case, the tool infers the path to Certbot's configuration
  directory and the certificate from Certbot's invocation of the tool.

- `-f, --force-update`\
  Replace possibly existing valid OCSP responses in staple files on disk by
  fresh responses from the OCSP responder.\
  This flag cannot be used when Certbot invokes the tool as a deploy hook.

- `-h, --help`\
  Print the correct usage of the tool.

- `-l, --no-color`\
  Do not use colored text output. This applies to both stdout and stderr. By
  default, the tool's output might use color, as long as none of the following
  conditions are true:
    - no TTY is attached to the file descriptor in question
    - [`$NO_COLOR`] is set
    - `$TERM` is set to `dumb`

- `-n NAME, --cert-name=NAME`\
  Specify the name of the certificate lineage(s) (as used by Certbot) that you
  want to process. Express multiple lineages by delimiting these with a comma,
  or specify the flag multiple times. When not specified, the tool processes
  all certificate lineages in Certbot's configuration directory.\
  This flag cannot be used when the tool is invoked as a deploy hook by
  Certbot.

- `-u URL, --ocsp-responder=URL` \
  Specify the URL of the OCSP responder to query for the certificate lineage(s)
  that were specified *directly* before this flag on the command line. This is
  required when the certificate in question does not use the AIA extension to
  include the OCSP responder of its issuer. For instance, you could invoke the
  command as follows: `./certbot-ocsp-fetcher --cert-name
  1.example.com,2.example.com --ocsp-responder ocsp.ca.example.com`

- `-o DIRECTORY, --output-dir=DIRECTORY`\
  Specify the directory where OCSP staple files are saved. When not specified,
  this defaults to the `$CACHE_DIRECTORY` environment variable, as is set by
  the [supplied systemd service]. If this environment variable is not set
  either, this defaults to the working directory.

- `-q, --quiet`\
  Do not print any output, including the list of certificates the tool
  processed and the actions the tool took.
  This flag and the `-v/--verbose` flag are mutually exclusive.

- `-v, --verbose`\
  Makes the tool verbose by printing specific (error) messages. These messages
  can be used for debugging purposes. Specify this flag multiple times for more
  verbosity.
  This flag and the `-q/--quiet` flag are mutually exclusive.

- `-w, --no-reload-webserver`\
  Do not reload `nginx`. When not specified and the tool created or updated at
  least one OCSP staple file, the tool will attempt to reload `nginx`.

## Distribution

* Upstream: https://github.com/tomwassenberg/certbot-ocsp-fetcher

The channels below are not maintained by me.

* Arch Linux: https://aur.archlinux.org/packages/certbot-ocsp-fetcher-git/
* Debian: we are looking for a packager
* Ubuntu: we are looking for a packager

 [Certbot]: https://github.com/certbot/certbot
 [#812]: https://trac.nginx.org/nginx/ticket/812
 [Mozilla's SSL Configuration Generator]: https://mozilla.github.io/server-side-tls/ssl-config-generator/
 [OCSP Must-Staple]: https://scotthelme.co.uk/ocsp-must-staple/
 [Bats]: https://github.com/bats-core/bats-core
 [supplied systemd service]: systemd-units/certbot-ocsp-fetcher.service#11
 [`$NO_COLOR`]: https://no-color.org/
