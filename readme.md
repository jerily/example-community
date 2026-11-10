# example-community (private)

Juniper Yard is a fictional neighborhood garden and workshop in Alderwick: a runnable Tcl community site with one shared Jinja master template and four
mounted packages: `/user` (accounts), `/forum` (discussions), `/wiki` (shared
handbook), and `/blog` (journal). The host passes per-request template properties to `web-wiki` and `web-blog`.
LOCAL persists to SQLite; PROD uses PostgreSQL through `web-user::connect` and
`tpersist`. All ordinary record IDs introduced by the account/forum packages are
KSUIDs; session and recovery tokens use `twebserver::random_bytes`. Passwords use
`bcrypt-tcl` at cost 12 (15-character minimum, 72 UTF-8 bytes maximum).

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
home_path /a-little-space-to-grow
origin http://localhost:8080
sqlite_path ./data/community.sqlite3
key_file ./data/community.keyset
user {title Account issuer {Juniper Yard}}
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
by the wiki/blog packages. Their package-owned editor assets are served
by their own mounts. The host registers `/` and `/site.css` after mounting packages.
All verified members can create/edit wiki/blog content in this example. Replace
the authorization callback in `library/site.tcl` for a different editorial policy.

## Home page and dynamic properties

The home page loads the wiki item selected by `home_path`; its body is never
hard-coded in the Jinja template. `content/wiki/home.md` seeds that item. LOCAL
startup syncs `content/wiki` and `content/blog`. In PROD, run `--initdb true`
explicitly to sync. The wiki slug comes from the Markdown's first heading, so
update `home_path` if you change that heading in the source file.

A browser edit creates a revision and appears immediately on `/`. Restarting
with an unchanged source file preserves that edit. Changing the source file
creates a new revision and replaces the imported item with the changed source.
Removing the source hides its imported item; a missing home item returns 404.

The host's `template_context` callback returns typed Jinja properties for each
request. It supplies `signed_in` and `show_edit_controls` based on the current
account session. The wiki/blog defaults still show configured editing controls
for hosts that do not pass a callback. Authorization and CSRF remain independent
server-side checks. The home template uses the same property for its edit link.

The package and registry manifests use `scripts.start.file: start.sh`.
The registry stores that script beside its recipe, and ttrek caches its contents
for offline use. It launches the installed command using `PROJECT_INSTALL_DIR`.

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
