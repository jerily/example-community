# example-community

Juniper Yard is a fictional neighborhood garden and workshop in Alderwick: a runnable Tcl community site with one shared Jinja master template and four
mounted packages: `/user` (accounts), `/forum` (discussions), `/wiki` (shared
handbook), and `/blog` (journal). The host passes per-request template properties to `web-wiki` and `web-blog`.
LOCAL persists to SQLite; PROD uses PostgreSQL through `web-user::connect` and
`tpersist`. All ordinary record IDs introduced by the account/forum packages are
KSUIDs; session and recovery tokens use `twebserver::random_bytes`. Passwords use
`bcrypt-tcl` at cost 12 (6-character minimum, 72 UTF-8 bytes maximum).

The site pins `web-user` and `web-forum` to `=0.1.3`, and `web-wiki` and
`web-blog` to `=0.1.1`, in `ttrek.json`.

## Run locally

Install and run the released site with ttrek:

```sh
ttrek install -y example-community@0.1.3
ENV=LOCAL ttrek run -package example-community -script start -- --port 8080
```

For development, use Tcl 9.1 or newer and source checkouts of this site and
`web-user`, `web-forum`, `web-wiki` and `web-blog`, with their native dependencies
installed. Put the checkout directories and the native install prefix's `lib`
directory on `TCLLIBPATH`, then run:

```sh
ENV=LOCAL tclsh main.tcl --port 8080
```

Open http://localhost:8080. Create an account, use the displayed LOCAL email code,
sign in, and enable an authenticator from Account. LOCAL also displays reset and
current TOTP codes. Email delivery is a TODO in web-user. Account/recovery codes
remain subject to expiry and replay checks. Site runtime data stays under the
consuming project's `data/`, outside installed package directories.

LOCAL startup creates schema, synchronizes the bundled wiki/blog Markdown and
creates `data/community.keyset` once with mode 0600. Keep this key file with the
database: replacing it makes encrypted fields unreadable and revokes sessions.
No demo users or hard-coded passwords are created. Account, discussion and edited
content records persist across restarts. The host does not launch Docker.

## Configuration with tconfig

The site loads [config.ini](config.ini) through `tconfig`. `--config site.ini`
overrides selected values by section; there is no Tcl dictionary configuration
file or evaluated configuration script. Plain INI uses `tconfig::read_config`
without an AWS request. Files containing tconfig's encrypted key envelope use
`tconfig::load_config` and the standard AWS credential/profile configuration.

```ini
[site]
site_name = Juniper Yard
origin = http://localhost:8080
port = 8080
sqlite_path = data/community.sqlite3
key_file = data/community.keyset

[account]
password_min_length = 6
bcrypt_cost = 12

[user]
issuer = Juniper Yard
prefix = /user

[forum]
prefix = /forum
title = Discussions
```

`[site]` owns the origin, identity, paths and listener address/port. `[account]`
sets web-user policy; `[user]`, `[forum]`, `[wiki]` and `[blog]` supply each mount's
properties. `[server]` holds twebserver options and `[postgresql]` contains database
connection properties such as `host`, `port`, `database`, `user`, `password` and
`sslmode`. Omitted values keep the defaults from the bundled INI file.

The host loads persistent `aead`/`mac` keysets from `key_file` per worker; no secret
is embedded in application code. Runtime data paths are relative to `PROJECT_HOME`
or the working directory. `--port` updates the default LOCAL origin's port unless
the override file explicitly supplies `[site] origin`.

Set `master_template_file` in `[site]` to share a custom master, or in an individual
mount section to override only that package. Template paths are relative to the
INI file declaring them. The host reads the template source and passes it to the
mount. The master defines `{% block body %}` and loads `editing`/`assets` supplied
by wiki/blog/forum. Their editor assets remain owned by their own mounts.

```tcl
set config [::community::load_config /path/to/site.ini]
::community::serve $config
```

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

The package manifest uses `scripts.start.file: start.sh`. The script launches
the installed command using `PROJECT_INSTALL_DIR`.

## Production

Set `ENV=PROD` and supply `--config production.ini` with an explicit HTTPS
`[site] origin` and `[postgresql]` connection settings. Use tconfig's
`encrypt_config`/`tconfig-encrypt.tcl` provisioning tool to populate settings from
SSM and encrypt SecureString values with KMS. Keep deployment files and keysets
outside version control. LOCAL plain INI needs no AWS access.
Provide a persistent `key_file` in advance. Generate fresh Tink AES256_GCM and
HMAC_SHA256 keysets using your trusted provisioning process and write a Tcl dict
with `aead` and `mac` keys, restricted to the service account. PROD never silently
generates missing keys or falls back to SQLite. TLS terminates at the host's
reverse proxy; the example listener defaults to loopback. Configure the proxy
Host to equal `origin`'s authority and pass trusted client context in a production
adapter to avoid sharing a per-peer limit across all proxied users.

Initialize a new database explicitly before starting workers:

```sh
ENV=PROD tclsh main.tcl --config production.ini --initdb true
ENV=PROD tclsh main.tcl --config production.ini
```

PROD startup validates routes/keys/configuration and does not create schema.
Set the `deliver` command prefix in the `[user]` section before enabling real email
registration/recovery. The default intentionally sends nothing. There is no
production publishing/deployment step in this example package.

## Verification

```sh
ENV=LOCAL tclsh tests/all.tcl
ENV=LOCAL python3 tests/http_test.py /path/to/tclsh
```

HTTP checks start/stop a temporary loopback server and temporary SQLite database.
They cover all four mounts, shared master templates, registration/login/recovery,
forum Markdown rendering and XSS prevention, wiki/blog writes through web-user callbacks, rejected CSRF and
session revocation, and data/key persistence across server restarts. The web-user
suite separately exercises both SQLite and optional PostgreSQL, MFA and replay.
See [web-user mounting documentation](https://github.com/jerily/web-user/blob/main/MOUNTING.md) for the reusable
package-to-site contract (installed as part of web-user as well).
