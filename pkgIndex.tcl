# 
# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2026 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.
# 

# Register the package and load its dependencies.
if {![package vsatisfies [package provide Tcl] 9.1-10]} {return}
package ifneeded example-community 0.3.2 [list source [file join $dir library example-community.tcl]]
