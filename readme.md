# example-community (private)

A runnable Tcl community site with one shared Jinja master template and four
mounted packages: `/user` (accounts), `/forum` (discussions), `/wiki` (shared
handbook), and `/blog` (journal). `web-wiki` and `web-blog` are consumed unchanged.
LOCAL persists to SQLite; PROD uses PostgreSQL through `web-user::connect` and
`tpersist`. All ordinary record IDs introduced by the account/forum packages are
KSUIDs; session and recovery tokens use cryptographic randomness.

## Run locally

```sh
ttrek install -y -registry /path/to/private-ttrek-registry -add-pubreg example-community
ENV=LOCAL ttrek run -package example-community -script start -- --port 8080
```

Open http://localhost:8080. Create an account, use the displayed LOCAL email code,
sign in, and enable an authenticator from Account. LOCAL also displays reset and
current TOTP codes. Email delivery is a TODO in web-user. Account/recovery codes
remain subject to expiry and replay checks. Site runtime data stays under the
consuming project's `data/`, outside installed package directories.

From a checkout with native dependencies and sibling packages on `TCLLIBPATH`:

```sh
ENV=LOCAL tclsh main.tcl --port 8080
```

LOCAL startup creates schema, synchronizes the bundled wiki/blog Markdown and
creates `data/community.keyset` once with mode 0600. Keep this key file with the
database: replacing it makes encrypted fields unreadable and revokes sessions.
No demo users or hard-coded passwords are created. Account, discussion and edited
content records persist across restarts. The host does not launch Docker.

## Site properties

`--config path` reads a trusted Tcl dictionary (data only, not an evaluated script):

```tcl
port 8080
tenant community
origin http://localhost:8080
sqlite_path ./data/community.sqlite3
key_file ./data/community.keyset
user {title Account issuer {Common Ground}}
forum {title Discussions}
wiki {allow_create true}
blog {allow_create true}
```

The `master_template` property contains template **source**, shared with all four
mounts. Omit it for `assets/page.html.jinja`. For programmatic configuration:

```tcl
set config [::community::settings \
    master_template [::web::user::read_text /path/to/site-master.html.jinja]]
::community::serve $config
```

Per-package dictionaries may override their own `master_template` and `templates`.
The common layout uses `{% block body %}` and supports `editing`/`assets` supplied
by the unchanged wiki/blog packages. Their package-owned editor assets are served
by their own mounts. The host registers `/` and `/site.css` after mounting packages.
All verified members can create/edit wiki/blog content in this example. Replace
the authorization callback in `library/site.tcl` for a different editorial policy.

## Production

Set `ENV=PROD`, an explicit HTTPS `origin`, and `postgresql` options in the config
(or PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD, PGSSLMODE). Credentials should
come from the runtime environment/secret store rather than version control.
Provide a persistent `key_file` in advance. Generate fresh Tink AES256_GCM and
HMAC_SHA256 keysets using your trusted provisioning process and write a Tcl dict
with `aead` and `mac` keys, restricted to the service account. PROD never silently
generates missing keys or falls back to SQLite. TLS terminates at the host's
reverse proxy; the example listener always binds loopback. Configure the proxy
Host to equal `origin`'s authority and pass trusted client context in a production
adapter to avoid sharing a per-peer limit across all proxied users.

Initialize a new database explicitly before starting workers:

```sh
ENV=PROD tclsh main.tcl --config production.tcl --initdb true
ENV=PROD tclsh main.tcl --config production.tcl
```

PROD startup validates routes/keys/configuration and does not create schema.
Integrate `web-user -deliver` in `library/site.tcl` before enabling real email
registration/recovery. The default intentionally sends nothing. There is no
production publishing/deployment step in this example package.

## Verification

```sh
ENV=LOCAL tclsh tests/all.tcl
ENV=LOCAL python3 tests/http_test.py /path/to/tclsh
```

HTTP checks start/stop a temporary loopback server and temporary SQLite database.
They cover all four mounts, shared master templates, registration/login/recovery,
forum XSS escaping, wiki/blog writes through web-user callbacks, rejected CSRF and
session revocation, and data/key persistence across server restarts. The web-user
suite separately exercises both SQLite and optional PostgreSQL, MFA and replay.
See [web-user mounting documentation](../web-user/MOUNTING.md) for the reusable
package-to-site contract (installed as part of web-user as well).
