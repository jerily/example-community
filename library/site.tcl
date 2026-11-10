proc ::community::settings {args} {
    variable root
    set mode [::web::user::environment]
    set base [expr {[info exists ::env(PROJECT_HOME)] ? $::env(PROJECT_HOME) : [pwd]}]
    set config [::web::user::options [dict create port 8080 tenant community \
        sqlite_path [file join $base data community.sqlite3] postgresql {} \
        key_file [file join $base data community.keyset] origin http://localhost:8080 \
        master_template [::web::user::read_text [file join $root assets page.html.jinja]] \
        home_path /a-little-space-to-grow user {} forum {} wiki {allow_create true} blog {allow_create true}] {*}$args]
    ::web::wiki::canonical_path [dict get $config home_path]
    if {$mode eq "PROD" && [dict get $config postgresql] eq {}} {
        set pg {}
        foreach {envName option} {PGHOST -host PGPORT -port PGDATABASE -database PGUSER -user PGPASSWORD -password PGSSLMODE -sslmode} {
            if {[info exists ::env($envName)]} {dict set pg $option $::env($envName)}
        }
        dict set config postgresql $pg
    }
    return $config
}
proc ::community::connection {config} {
    ::web::user::connect [dict create sqlite_path [dict get $config sqlite_path] postgresql [dict get $config postgresql]]
}
# One persistent key bundle, never regenerated over an existing file or in PROD.
proc ::community::keys {config {create 0}} {
    set path [dict get $config key_file]
    if {![file exists $path]} {
        if {!$create || [::web::user::environment] ne "LOCAL"} {error "Provision key_file before starting PROD."}
        file mkdir [file dirname $path]
        set f [open $path {WRONLY CREAT EXCL} 0600]
        try {
            fconfigure $f -encoding utf-8
            puts $f [dict create aead [::tink::aead::create_keyset AES256_GCM] mac [::tink::mac::create_keyset HMAC_SHA256]]
        } finally {close $f}
    }
    set keys [::web::user::read_text $path]
    dict create aead [::tink::register_keyset [dict get $keys aead]] mac [::tink::register_keyset [dict get $keys mac]]
}
proc ::community::initialize {connection config} {
    variable root
    ::tpersist::db_transaction $connection {
        ::web::user::initdb $connection
        ::web::forum::initdb $connection
        ::web::wiki::initdb $connection
        ::web::blog::initdb $connection
        foreach kind {wiki blog} {
            set store [::web::${kind}::create -connection $connection -domain [dict get $config tenant] -title [string totitle $kind]]
            ::web::${kind}::sync $store [file join $root content $kind]
        }
    }
}
proc ::community::router {connection config keys} {
    set router [::tpathexp::router]
    set store [::web::user::create -connection $connection -tenant [dict get $config tenant] \
        -aead [dict get $keys aead] -mac [dict get $keys mac]]
    set shared [dict create master_template [dict get $config master_template]]
    set auth [::web::user::mount $router -store $store -prefix /user -config \
        [dict merge $shared [dict create origin [dict get $config origin] title {Juniper Yard} issuer {Juniper Yard}] [dict get $config user]]]
    ::web::forum::mount $router -store $store -user $auth -prefix /forum -config [dict merge $shared [dict get $config forum]]
    foreach kind {wiki blog} {
        set content [::web::${kind}::create -connection $connection -domain [dict get $config tenant] -title [string totitle $kind]]
        if {$kind eq "wiki"} {set homeStore $content}
        ::web::${kind}::mount $router -store $content -prefix /$kind \
            -authorize [list ::web::user::authorize $auth] -csrf [list ::web::user::csrf $auth] \
            -context [list ::community::template_context $auth] \
            -config [dict merge $shared [dict get $config $kind]]
    }
    $router add GET / [list ::community::home $config $homeStore $auth] -strict true
    $router add GET /site.css ::community::stylesheet -strict true
    $router add GET /yard.svg ::community::illustration -strict true
    return $router
}
# Host-owned properties are evaluated for this request, never saved globally.
proc ::community::template_context {auth request context} {
    set user [::web::user::current_user $auth $request $context]
    dict create signed_in [list BOOL [expr {$user ne {}}]] \
        show_edit_controls [list BOOL [expr {$user ne {}}]] \
        site_name [list S {Juniper Yard}]
}
proc ::community::home {config store auth request context params} {
    variable root
    try {
        set item [::web::wiki::load $store [dict get $config home_path]]
        if {[dict get $item item_type] ne "page"} {::web::wiki::fail 404 "Home must be a wiki page."}
    } trap {WEB WIKI} {message options} {
        return [::web::user::response [lindex [dict get $options -errorcode] 2] $message text/plain]
    }
    set templates [dict create page.html.jinja [dict get $config master_template] home.html.jinja [::web::user::read_text [file join $root assets home.html.jinja]]]
    set fields [::web::user::text_fields [dict create title [dict get $item title] \
        markdown_html [::cmark_gfm::render_gfm_html [dict get $item markdown]] \
        edit_url /wiki/_edit[dict get $item path]]]
    set fields [dict merge $fields [template_context $auth $request $context]]
    ::web::user::response 200 [::jinja2::render [dict get $templates home.html.jinja] \
        [::tjson::typed_to_json [list M $fields]] -templates $templates -path home.html.jinja]
}
proc ::community::illustration {request context params} {
    variable root
    ::web::user::response 200 [::web::user::read_text [file join $root assets yard.svg]] image/svg+xml
}
proc ::community::stylesheet {request context params} {
    variable root
    ::web::user::response 200 [::web::user::read_text [file join $root assets site.css]] {text/css; charset=utf-8}
}
proc ::community::dispatch {routes config request context} {
    if {![dict exists $request method]} {dict set request method [dict get $request httpMethod]}
    set expected [lindex [split [dict get $config origin] /] 2]
    if {![string equal -nocase [::web::user::header $request host] $expected]} {
        return [::web::user::response 403 {Use the configured site origin.} text/plain]
    }
    $routes dispatch $request $context
}
