# tconfig owns INI parsing and KMS decryption. The host adapts its sections to
# the dictionaries accepted by the database, listener and mounted packages.
proc ::community::load_config {{filename {}} {port {}}} {
    variable root
    set mode [::web::user::environment]
    if {$mode eq "PROD" && $filename eq {}} {error "ENV=PROD requires --config"}
    set files [list [file join $root config.ini]]
    if {$filename ne {}} {lappend files [file normalize $filename]}
    set sections {}
    set explicitOrigin 0
    foreach configFile $files {
        set loaded [::tconfig::read_config $configFile]
        if {[dict exists $loaded tconfig]} {
            set loaded [::tconfig::load_config $configFile]
        }
        if {$filename ne {} && $configFile eq [file normalize $filename]} {
            set explicitOrigin [dict exists $loaded site origin]
        }
        dict for {section properties} $loaded {
            if {$section ni {site account user forum wiki blog server postgresql}} {
                error "unknown configuration section: $section"
            }
            if {[dict exists $properties master_template_file]} {
                set template [file join [file dirname $configFile] [dict get $properties master_template_file]]
                dict unset properties master_template_file
                dict set properties master_template [::web::user::read_text $template]
            }
            if {![dict exists $sections $section]} {dict set sections $section {}}
            dict set sections $section [dict merge [dict get $sections $section] $properties]
        }
    }
    set config [dict get $sections site]
    if {$port ne {}} {
        dict set config port $port
        if {$mode eq "LOCAL" && !$explicitOrigin} {
            # Preserve the configured default hostname when overriding the port.
            set origin [regsub {:[0-9]+$} [dict get $config origin] {}]
            dict set config origin $origin:$port
        }
    }
    set port [dict get $config port]
    if {![string is integer -strict $port] || $port < 1 || $port > 65535} {error "invalid port"}
    if {![string is integer -strict [dict get $config num_threads]] || [dict get $config num_threads] < 1} {
        error "num_threads must be a positive integer"
    }
    if {$mode eq "PROD" && ![string match https://* [dict get $config origin]]} {
        error "ENV=PROD requires an HTTPS origin in the configuration file"
    }
    set base [expr {[info exists ::env(PROJECT_HOME)] ? $::env(PROJECT_HOME) : [pwd]}]
    foreach name {sqlite_path key_file} {
        dict set config $name [file join $base [dict get $config $name]]
    }
    ::web::wiki::canonical_path [dict get $config home_path]
    dict set config account [::web::user::settings [dict merge [dict get $sections account] \
        [dict create tenant [dict get $config tenant]]]]
    dict set config user [dict merge [dict create title [dict get $config site_name] \
        issuer [dict get $config site_name]] [dict get $sections user]]
    dict set config user origin [dict get $config origin]
    foreach section {forum wiki blog} {dict set config $section [dict get $sections $section]}
    dict set config server_options [dict get $sections server]
    set postgresql {}
    dict for {name value} [dict get $sections postgresql] {
        if {$name ni {host port database user password sslmode timeout encoding}} {error "unknown PostgreSQL setting: $name"}
        if {$value ne {}} {dict set postgresql -$name $value}
    }
    dict set config postgresql $postgresql
    return $config
}
