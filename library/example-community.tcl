package require web-user 0.1.4
package require web-forum 0.1.4
package require web-wiki 0.1.1
package require web-blog 0.1.1
package require twebserver 1.47.56
package require tconfig::decrypt 1.0.0
namespace eval ::community {variable root [file dirname [file dirname [info script]]]}
foreach module {config site server} {source [file join $::community::root library $module.tcl]}
package provide example-community 0.1.4
