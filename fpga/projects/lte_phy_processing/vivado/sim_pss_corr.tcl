set tcl_dir [file dirname [file normalize [info script]]]

set DO_PACKAGE 0
set RUN_TOP_SYNTH 0

source [file join $tcl_dir "system_bd.tcl"]

set simset_name lte_phy_pss_corr
set sim_fileset [get_filesets $simset_name]

if {[llength $sim_fileset] == 0} {
    error "ERROR: simulation fileset '$simset_name' was not created"
}

current_fileset -simset $sim_fileset
set_property top tb_lte_phy_pss_corr $sim_fileset
update_compile_order -fileset $simset_name

launch_simulation -simset $simset_name -mode behavioral
run all
close_sim

puts "INFO: lte_phy_pss_corr simulation finished"
close_project
exit
