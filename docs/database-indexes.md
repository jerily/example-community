# Database access and indexes

All persistent access in web-user, web-forum, web-blog, web-wiki and tsession's
SQL stores uses tpersist. Connections are borrowed, and parameter binding and
schema/index creation go through tpersist. tsession 2 has no global middleware,
MemoryStore or separate signature API; its current APIs are per-mount cookies
and tenant-scoped SQL stores.

| Package/table | Access path | Index |
| --- | --- | --- |
| web-user/users | ID lookup and revision-checked writes | Primary key `(tenant, id)` |
| web-user/users | Normalized email lookup | Unique `(tenant, email_key)` |
| web-user/profiles | Account/profile widget lookup | Primary key `(tenant, id)` |
| web-user/limits | Counter lookup/update | Primary key `(tenant, id)` |
| web-user/limits | Expired counter cleanup | `web_user_limits_expiry (tenant, expires)` |
| web-forum/topics | Topic lookup | Primary key `(tenant, id)` |
| web-forum/topics | Recent topics with a page limit | `web_forum_topics_recent (tenant, created_at, id)` scanned backward |
| web-forum/replies | Recent replies for a topic | `web_forum_replies_topic_recent (tenant, topic, created_at, id)` scanned backward |
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
EXPLAIN with the same bound parameters on SQLite and PostgreSQL. It covers 22
read/cleanup plans using 32 tenants/domains and 2,048 rows per table, after
ANALYZE. It does not disable sequential scans or force an index. Planners may
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
