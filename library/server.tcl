proc ::community::worker {config} {
    variable connection [connection $config]
    variable key_handles [keys $config]
    variable routes [router $connection $config $key_handles]
    variable settings $config
}
proc ::community::process {context request} {
    variable routes
    variable settings
    try {set response [dispatch $routes $settings $request $context]} on error {message opts} {
        # Do not log submitted credentials, tokens, key material, or SQL parameters.
        puts stderr {example-community: request failed; internal server error}
        set response [::web::user::response 500 {Internal server error.} text/plain]
    }
    ::twebserver::return_response [dict get $context conn] $response
}
proc ::community::serve {config {initialize 0}} {
    set mode [::web::user::environment]
    if {$mode eq "LOCAL"} {file mkdir [file dirname [dict get $config sqlite_path]]}
    set keyHandles [keys $config 1]
    set db [connection $config]
    try {
        if {$mode eq "LOCAL" || $initialize} {initialize $db $config}
        # Validate mounts/configuration before opening a listener.
        set check [router $db $config $keyHandles]
        $check destroy
    } finally {
        ::tpersist::db_disconnect $db
        dict for {name handle} $keyHandles {::tink::unregister_keyset $handle}
    }
    if {$initialize} {puts {Community schema initialized.}; return}
    set init [join [list [list set auto_path $::auto_path] {package require example-community} [list ::community::worker $config]] \n]
    set server [::twebserver::create_server [dict merge [dict create rootdir [pwd]] [dict get $config server_options]] ::community::process $init]
    try {
        # Loopback only. In PROD terminate HTTPS at a trusted reverse proxy.
        ::twebserver::listen_server -http -host [dict get $config listen_host] -num_threads [dict get $config num_threads] $server [dict get $config port]
        puts "Community: [dict get $config origin]"
        flush stdout
        ::twebserver::wait_signal
    } finally {::twebserver::destroy_server $server}
}
proc ::community::main {arguments} {
    if {$arguments eq {--help}} {
        puts {ENV=LOCAL example-community --config site.ini [--port 8080] [--initdb true]
Configuration uses tconfig INI files; encrypted values use AWS KMS.
Both environments require [account] email_hash_salt in the config file.
ENV=PROD requires --config with an HTTPS site origin, key_file and PostgreSQL settings.
--initdb true initializes schema/content and exits. No automatic PROD migrations.}
        return
    }
    set args [::web::user::options {--config {} --port {} --initdb false} {*}$arguments]
    set config [load_config [dict get $args --config] [dict get $args --port]]
    if {![string is boolean -strict [dict get $args --initdb]]} {error "--initdb must be a boolean"}
    serve $config [dict get $args --initdb]
}
