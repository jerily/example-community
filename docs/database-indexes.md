# Database access and indexes

All persistent access in web-user, web-forum, web-blog, web-wiki and tsession's
SQL stores uses tpersist. Connections are borrowed, and parameter binding and
schema/index creation go through tpersist. tsession 2 has no global middleware,
MemoryStore or separate signature API; its current APIs are per-mount cookies
and tenant-scoped SQL stores.

| Package/table | Access path | Index |
| --- | --- | --- |
| web-user/users | ID lookup and revision-checked writes | Primary key `(tenant, id)` |
| web-user/users | Admin registration-order listing | `web_user_registered (tenant, created_at, id)` |
| web-user/users | Admin last sign-in / visit ordering | `web_user_last_login (tenant, last_login_at, id)`, `web_user_last_visit (tenant, last_seen_at, id)` |
| web-user/users | Normalized email lookup | Unique `(tenant, email_key)` |
| web-user/profiles | Account/profile widget lookup | Primary key `(tenant, id)` |
| web-user/registrations | Expired pending registration selection | `web_user_registrations_expiry (tenant, expires)` |
| web-user/registrations | Delete selected registration | Primary key `(tenant, id)` |
| web-user/limits | Counter lookup/update | Primary key `(tenant, id)` |
| web-user/limits | Expired counter cleanup | `web_user_limits_expiry (tenant, expires)` |
| web-forum/topics | Topic lookup | Primary key `(tenant, id)` |
| web-forum/topics | Visible topics with count and pagination | `web_forum_topics_visibility (tenant, status, hidden, created_at, id)` |
| web-forum/topics | Latest public activity | `web_forum_topics_activity (tenant, status, hidden, last_activity_at, id)` |
| web-forum/topics | Public member discussions | `web_forum_topics_author_visible (tenant, author, status, hidden, created_at, id)` |
| web-forum/replies | Visible chronological replies with pagination | `web_forum_replies_topic_visible (tenant, topic, status, hidden, created_at, id)` |
| web-forum/moderation | Action history, optionally by discussion | `(tenant, created_at, id)` and `(tenant, topic_id, created_at, id)` |
| web-user/group_members | Membership by keyed email | `web_user_group_email (tenant, email_key, group_name)` |
| web-user/group_permissions | Grants for a group | Primary key `(tenant, group_name, permission)` |
| web-wiki/items | Active/inactive page lookup | Primary key `(domain, path)` |
| web-wiki/items | Active children of a folder | `web_wiki_children (domain, parent_path, active)` |
| web-blog/items | Active/inactive post lookup | Primary key `(domain, path)` |
| web-blog/items | Active children of a folder | `web_blog_children (domain, parent_path, active)` |
| web-blog/items | Published posts, newest date then ascending path | `web_blog_posts (domain, active, item_type, published_at DESC, path)` |
| Both content revision tables | Per-path history, newest revision first | Primary key `(domain, path, revision)` scanned backward |
| Both content item tables | Full domain read during source synchronization | Leading `domain` column of the primary/secondary indexes |
| tsession/sessions | Live session lookup, update and deletion | Primary key `(tenant, id)` |
| tsession/sessions | Revoke a user's sessions | `tsession_subject (tenant, subject)` |
| tsession/sessions | Expired session cleanup | `tsession_expiry (tenant, expires)` |

Folder indexes filter the selected folder before sorting its entries by type,
title and path. They deliberately avoid putting large titles and both full paths
in one PostgreSQL index tuple. The other ordered lists need no separate sort in
the audited plans.

`tests/indexes.test` captures the packages' actual tpersist statements and runs
EXPLAIN with the same bound parameters on SQLite and PostgreSQL. It covers 41
read/cleanup plans using 32 tenants/domains and 2,048 rows per table, after
ANALYZE. Cleanup checks cover bounded expiry selection, individual deletions,
and revocation of sessions for removed pending registrations.
It does not disable sequential scans or force an index. Planners may
choose a sequential scan for small tables or a full-domain synchronization that
reads most of a table; matching indexes do not guarantee every optimizer choice.

Run the complete test suite with an isolated PostgreSQL database:

```sh
INDEX_TEST_PG='-host localhost -database index_tests -user test' \
  ENV=LOCAL tclsh tests/all.tcl
```

Set `INDEX_PLAN_DIR` to an existing directory to retain the explained plans.
PostgreSQL fixtures use a temporary schema and remove it on completion.

All new indexes are created by the packages' idempotent `initdb` procedures.
Existing deployments must rerun explicit initialization before serving; LOCAL
startup already does so. For example-community in PROD, run the documented
`--initdb true` maintenance step. No request handler creates indexes.
