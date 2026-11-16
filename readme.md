# example-community

Juniper Yard is a fictional neighborhood garden and workshop in Alderwick: a runnable Tcl community site with one shared Jinja master template and four
mounted packages: `/user` (accounts), `/forum` (discussions), `/wiki` (shared
handbook), and `/blog` (journal). The host passes per-request template properties to `web-wiki` and `web-blog`.
LOCAL persists accounts and sessions to SQLite (`tsession-sqlite`); PROD uses
PostgreSQL (`tsession-postgres`) through `web-user::connect` and
`tpersist`. All ordinary record IDs introduced by the account/forum packages are
prefixed KSUIDs (`user_`, `topic_`, `reply_`, `moderation_`); session and recovery tokens use `twebserver::random_bytes`. Passwords use
`bcrypt-tcl` at cost 12 (6-character minimum, 72 UTF-8 bytes maximum).

The site pins `web-user` to `=0.5.2`, `web-forum` to `=0.3.0`, and `web-wiki`
and `web-blog` to `=0.1.5` in `ttrek.json`. The Tcl runtime also requires exactly
`web-user` 0.5.2. Forum topics and replies show their creation dates and times in UTC.

## Run locally

From a cloned source package:

```sh
ttrek clone example-community -outdir my-community
cd my-community
ttrek install -y
ttrek run -script start
```

Command-line startup defaults to `ENV=LOCAL` when `ENV` is unset. An explicit
`ENV=PROD` still requires production configuration; other values are rejected.
The project script runs the launcher in the cloned source, so edits to that
source take effect after restarting. Pass options after `--`, for example
`ttrek run -script start -- --port 8081`.

The bundled `config.ini` includes a sample `[account] email_hash_salt` for local
development. For your own site, generate a salt with `openssl rand -hex 32`, save
it in a private `site.ini`, and reuse the file across restarts. You can also install
the example as a dependency in an initialized ttrek project:

```sh
ttrek install -y example-community
ttrek run -package example-community -script start -- --config /path/to/site.ini --port 8080
```

For development, use Tcl 9.1 or newer and source checkouts of this site and
`web-user`, `web-forum`, `web-wiki`, `web-blog` and `web-static-wiki`, with their native dependencies
installed. Put the checkout directories and the native install prefix's `lib`
directory on `TCLLIBPATH`, then run:

```sh
tclsh main.tcl --config /path/to/site.ini --port 8080
```

Open http://localhost:8080. Create an account, use the displayed LOCAL email code,
sign in, and enable an authenticator from Account. LOCAL also displays reset and
current TOTP codes. From Account, choose **Change password** to confirm the
current password and set a new one. It signs out other sessions and preserves
MFA; the account routes and forms are supplied by web-user. SES email is opt-in
in PROD and remains off in LOCAL. Account/recovery codes
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
email_hash_salt = <paste the generated salt here>
password_min_length = 6
bcrypt_cost = 12
collect_names = true

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
`email_hash_salt` is required in LOCAL and PROD. Encrypted tconfig deployments
can supply `[account] enc:email_hash_salt`; the host decrypts it before creating
the account store. Keep it stable alongside the keysets. Email and names are
encrypted; email lookup uses a salted, keyed digest.

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

`[account] collect_names = true` enables first/last name collection and the
account profile-edit form. Names are encrypted at rest; the forum shows only the
first name through web-user's reusable profile widget. Existing members can use
**Your account → Edit profile**. Set the property to `false` to omit name collection.
The host binds the widget in `library/site.tcl`; see the
[shared widget contract](https://github.com/jerily/web-user/blob/main/WIDGETS.md).
Run the explicit PROD `--initdb true` step to create the schema before serving.
LOCAL initialization does this automatically.

Creating and editing wiki pages requires `wiki.edit`; blog posts require
`blog.edit`. The homepage uses the wiki permission. Configure these grants through
groups as described below; signing in or moderating the forum does not grant
editorial access.

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
request. It supplies `signed_in` from the current account session. Wiki/blog
packages generate edit and create links only when the permission callback allows
them; the home template checks `wiki.edit` for its edit link. Every form submission
checks permission again, as well as CSRF, so revocation applies to open forms.

The package manifest uses `scripts.start.file: start.sh`. The script launches
the source command using `PROJECT_HOME`. The registry recipe supplies a separate
package script that launches the installed command using `PROJECT_INSTALL_DIR`.
The launcher uses the checkout's `main.tcl` when present, otherwise discovers it
under `lib/example-community*` without a fixed package version. It reports a
missing or ambiguous installation instead of choosing an arbitrary directory.

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
Enable account email in the private deployment INI when desired:

```ini
[user]
email_enabled = true
email_from = accounts@example.com
email_region = us-east-1
```

`pure-tcl-aws-ses` uses the AWS credential provider chain. Configure the sender
identity and sending permissions in that region. Enabled PROD delivery sends
email confirmation/recovery codes, authenticator enabled/disabled notices, and
password-change notices (including resets). Passwords and authenticator secrets
are never emailed. `email_enabled` defaults to false; when off, PROD has no
verification/recovery email delivery. LOCAL continues showing development codes
and never calls SES. An optional `deliver` callback can override transport.

Delivery follows the account transaction. Failures produce a generic server log
and preserve the successful account change/cookie; there is no persistent email
queue or application retry worker. Monitor delivery failures. Session schema
initialization creates `tsession_sessions`; no old sessions are migrated. There
is no production publishing/deployment step in this example package.

## Verification

```sh
ENV=LOCAL tclsh tests/all.tcl
python3 tests/http_test.py /path/to/tclsh
```

HTTP checks start/stop a temporary loopback server and temporary SQLite database.
They launch the source `start.sh` without `ENV` or an installed site launcher,
and check that explicit production and invalid modes still fail closed.
They cover all four mounts, shared master templates, registration/login/recovery,
forum Markdown rendering and XSS prevention, wiki/blog writes through web-user callbacks, rejected CSRF and
session revocation, and data/key persistence across server restarts. The web-user
suite separately exercises both SQLite and optional PostgreSQL, MFA and replay.
See [web-user mounting documentation](https://github.com/jerily/web-user/blob/main/MOUNTING.md) for the reusable
package-to-site contract (installed as part of web-user as well).

Database access in all mounted packages and SQL session stores uses `tpersist`.
See [database indexes](docs/database-indexes.md) for the access-path inventory
and the SQLite/PostgreSQL EXPLAIN audit. Rerun explicit initialization to create
new indexes in an existing database before serving with this release.

## Groups, moderation, and CAPTCHA

Add comma-separated member emails to your configuration:

```ini
[groups]
admin = mira@example.com, rowan@example.com
moderator = alex@example.com
editor = robin@example.com

[permissions]
admin = forum.moderate, wiki.edit, blog.edit, users.manage
moderator = forum.moderate
editor = wiki.edit, blog.edit

[forum]
moderation = true
posting_captcha = true
page_size = 20
```

Restart to sync the groups and permissions through `web-user`. You can list an
email before its owner registers; the account must verify that email before it
receives permissions. Removing an email or permission and restarting revokes
access for existing sessions too. This applies in both LOCAL and PROD; run
`--initdb true` to initialize the database before first PROD startup.

Administrators with `users.manage` see **Your account → Manage users**. The
directory shows registration, last sign-in and last visit times, authenticator
status and configured groups. Choose **Recently signed in**, **Recently active**,
or **Newest registrations** to sort it.
It is private to that permission and lists all accounts across pages.

An editor may create and edit notebook pages and journal posts. Grant only
`wiki.edit` or only `blog.edit` to limit someone to one collection. The group
name itself grants nothing; the permission list is authoritative.

With moderation enabled, all new topics and replies wait for approval. Members
can see their own pending submissions. Moderators get links to pending posts,
hidden posts, and the moderation history. They can approve/reject submissions,
hide/restore topics or replies, and lock/unlock discussions. Each action needs a
reason and records the moderator and time. Restoring a hidden pending post does
not approve it.

Posting CAPTCHA is a separate switch. When enabled, `tcaptcha` supplies a
single-use challenge on both new-topic and reply forms. Account settings control
its length, lifetime, and attempt limits. Both switches default to false.

Topic lists offer **Newest topics** (default) and **Latest activity**. Replies are
chronological, lists are paginated, and author names link to forum profiles.

## Images

Put images in `content/images/` and reference them as `![A garden](yard.svg)`.
The same renderer handles notebook pages, journal posts, forum messages and the
homepage. It produces `/images/yard.svg`, including from nested pages. Restart
after adding files. `[site] images_directory` selects another image folder.

`web-static-wiki` supplies the shared validated image inventory and renderer;
`web-wiki`, `web-blog`, and `web-forum` receive it as a rendering callback.
`tpathexp` owns all routing, including images; `twebserver` calls `process_conn`
and sends the resulting responses. The example uses `tpathexp` ^1.2.0.
