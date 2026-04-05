set tcl_dir [file dirname [file normalize [info script]]]

set DO_PACKAGE 0
set RUN_TOP_SYNTH 0

source [file join $tcl_dir "system_bd.tcl"]

set top_file [file join $repo_root "hdl" "systemverilog" "lte_phy_sync_k2_top.sv"]
if {[llength [get_files -quiet [file normalize $top_file]]] == 0} {
    add_files -fileset sources_1 -norecurse $top_file
}

set REPORTS_DIR [file join $repo_root "vivado" "reports"]
file mkdir $REPORTS_DIR

set gen_ip_root [file join $repo_root "vivado" "lte_phy_processing.gen" "sources_1" "ip"]
set pss_ip_names [list \
    pss_0_rom_td_128sps \
    pss_1_rom_td_128sps \
    pss_2_rom_td_128sps \
]

set shared_v_read 0
foreach ip_name $pss_ip_names {
    set shared_v [file join $gen_ip_root $ip_name "simulation" "blk_mem_gen_v8_4.v"]
    set wrap_v   [file join $gen_ip_root $ip_name "sim" "${ip_name}.v"]

    if {!$shared_v_read && [file exists $shared_v]} {
        read_verilog -quiet $shared_v
        set shared_v_read 1
    }
    if {[file exists $wrap_v]} {
        read_verilog -quiet $wrap_v
    }
}

set top_name lte_phy_sync_k2_top
set_property top $top_name [get_filesets sources_1]
update_compile_order -fileset sources_1

catch {close_design}
synth_design -top $top_name -part $ZEDBOARD_ZYNQ

report_utilization               -file [file join $REPORTS_DIR "${top_name}_utilization.rpt"]
report_utilization -hierarchical -file [file join $REPORTS_DIR "${top_name}_utilization_hier.rpt"]
report_timing_summary            -file [file join $REPORTS_DIR "${top_name}_timing_summary.rpt"]
write_checkpoint -force [file join $REPORTS_DIR "${top_name}_synth.dcp"]

close_design
close_project
exit
