package require web-user 0.1.0
package require web-forum 0.1.0
package require web-wiki 0.1.0
package require web-blog 0.1.0
package require twebserver 1.47.55
namespace eval ::community {variable root [file dirname [file dirname [info script]]]}
foreach module {site server} {source [file join $::community::root library $module.tcl]}
package provide example-community 0.1.0
