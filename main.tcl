lappend auto_path [file dirname [file normalize [info script]]]
package require example-community
try {::community::main $argv} on error {message options} {
    puts stderr "example-community: $message"
    exit 1
}
