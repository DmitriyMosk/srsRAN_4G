set tcl_dir [file dirname [file normalize [info script]]]

set DO_PACKAGE 0
set RUN_TOP_SYNTH 1

source [file join $tcl_dir "system_bd.tcl"]

close_project
exit
