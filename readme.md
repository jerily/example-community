# example-community

Juniper Yard is a fictional neighborhood garden and workshop in Alderwick: a runnable Tcl community site with one shared Jinja master template and four
mounted packages: `/user` (accounts), `/forum` (discussions), `/wiki` (shared
handbook), and `/blog` (journal). The host passes per-request template properties to `web-wiki` and `web-blog`.
LOCAL persists to SQLite; PROD uses PostgreSQL through `web-user::connect` and
`tpersist`. All ordinary record IDs introduced by the account/forum packages are
KSUIDs; session and recovery tokens use `twebserver::random_bytes`. Passwords use
`bcrypt-tcl` at cost 12 (15-character minimum, 72 UTF-8 bytes maximum).

The site pins `web-wiki` and `web-blog` to exactly `0.1.1` in `ttrek.json`.

## Run locally

Use Tcl 9.1 or newer and source checkouts of this site and
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

## Site properties

`--config path` reads a trusted Tcl dictionary (data only, not an evaluated script):

```tcl
port 8080
tenant community
site_name {Juniper Yard}
listen_host 127.0.0.1
num_threads 1
home_path /a-little-space-to-grow
origin http://localhost:8080
sqlite_path ./data/community.sqlite3
key_file ./data/community.keyset
account {
    bcrypt_cost 12 password_min_length 15
    totp_digits 6 totp_period 30 totp_algorithm SHA1 totp_window 1
    session_ttl 43200 code_ttl 900 challenge_ttl 600
    throttle_window 900 browse_limit 120 post_limit 60 account_limit 10 challenge_limit 5
    form_max_bytes 32768
}
user {prefix /user title Account issuer {Juniper Yard} deliver {}}
forum {prefix /forum title Discussions page_size 100 body_max_length 10000 title_max_length 160 post_limit 30}
wiki {allow_create true}
blog {allow_create true}
```

The `account` dictionary configures web-user store policy. The host supplies
its tenant and registers the `aead`/`mac` keysets from `key_file` in each worker;
no secret is embedded in source. `user` configures the account mount, including
issuer and optional delivery callback; `forum` configures the discussion mount.
`site_name` populates account title/issuer and layout properties unless overridden.
`listen_host`, `num_threads`, and `server_options` configure the listener.
See [config.example.tcl](config.example.tcl) for a data-only starting point.

The `master_template` property contains template **source**, shared with all four
mounts. Omit it for `assets/page.html.jinja`. For programmatic configuration:

```tcl
set config [::community::settings \
    master_template [::web::user::read_text /path/to/site-master.html.jinja]]
::community::serve $config
```

Per-package dictionaries may override their own `master_template` and `templates`.
The common layout uses `{% block body %}` and supports `editing`/`assets` supplied
by the wiki/blog/forum packages. Their package-owned editor assets are served
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

The package manifest uses `scripts.start.file: start.sh`. The script launches
the installed command using `PROJECT_INSTALL_DIR`.

## Production

Set `ENV=PROD`, an explicit HTTPS `origin`, and `postgresql` options in the config
dictionary. Supply credentials from your secret store when creating this
dictionary; the package does not substitute environment variables implicitly.
Keep deployment configuration and key files outside version control.
Provide a persistent `key_file` in advance. Generate fresh Tink AES256_GCM and
HMAC_SHA256 keysets using your trusted provisioning process and write a Tcl dict
with `aead` and `mac` keys, restricted to the service account. PROD never silently
generates missing keys or falls back to SQLite. TLS terminates at the host's
reverse proxy; the example listener defaults to loopback. Configure the proxy
Host to equal `origin`'s authority and pass trusted client context in a production
adapter to avoid sharing a per-peer limit across all proxied users.

Initialize a new database explicitly before starting workers:

```sh
ENV=PROD tclsh main.tcl --config production.tcl --initdb true
ENV=PROD tclsh main.tcl --config production.tcl
```

PROD startup validates routes/keys/configuration and does not create schema.
Set the `user.deliver` command prefix in the config before enabling real email
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
