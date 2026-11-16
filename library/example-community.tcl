# 
# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2026 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.
# 

# Register the package and load its dependencies.
package require -exact web-user 0.5.2
package require web-forum 0.3.0
package require web-wiki 0.1.5
package require web-blog 0.1.5
package require -exact web-static-wiki 0.1.9
package require tpathexp 1.2.0
package require twebserver 1.47.58
package require tconfig::decrypt 1.0.1
namespace eval ::community {variable root [file dirname [file dirname [info script]]]}
foreach module {config site server} {source [file join $::community::root library $module.tcl]}
package provide example-community 0.3.1
