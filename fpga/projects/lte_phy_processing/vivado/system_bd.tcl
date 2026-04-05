# -----------------------------------------------------------------------------
# create project
# add source RTL
# create sim sets when DO_PACKAGE == 0
# package custom IP when DO_PACKAGE == 1
# -----------------------------------------------------------------------------

set DO_PACKAGE 0

if {![info exists RUN_TOP_SYNTH]} {
    set RUN_TOP_SYNTH 0
}

set ZEDBOARD_ZYNQ "xc7z020clg484-1"

set tcl_dir   [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $tcl_dir ..]]

set LTE_PHY_MATH [file normalize [file join $repo_root .. "lte_phy_math"]]
set LTE_PHY_FFT  [file normalize [file join $repo_root .. "lte_phy_fft"]]

set required_vivado "2023.2"
set current_vivado  [version -short]
if {![string equal $current_vivado $required_vivado]} {
    puts "ERROR: Vivado version mismatch. Required: $required_vivado, current: $current_vivado"
    exit 1
} else {
    puts {INFO: [check version] OK}
}

puts "INFO: repo_root    = $repo_root"
puts "INFO: LTE_PHY_MATH = $LTE_PHY_MATH"
puts "INFO: LTE_PHY_FFT  = $LTE_PHY_FFT"

set IP_PKG_ROOT [file normalize [file join $repo_root "ip_pkg"]]
set IP_NAME     "lte_phy_processing"
set IP_PKG_DIR  [file join $IP_PKG_ROOT $IP_NAME]
set IP_PKG_SRC_PATH [file join $IP_PKG_DIR "src"]

# -----------------------------------------------------------------------------
# helper procs
# -----------------------------------------------------------------------------

proc require_file_exists {path} {
    if {![file exists $path]} {
        error "ERROR: required file not found: $path"
    }
}

proc mark_header_as_global_include {hdr_path} {
    set hdr_obj [get_files -quiet [file normalize $hdr_path]]
    if {[llength $hdr_obj] > 0} {
        set_property file_type {Verilog Header} $hdr_obj
        set_property is_global_include true      $hdr_obj
        puts "INFO: global include set for $hdr_path"
    } else {
        error "ERROR: header file was not added to project: $hdr_path"
    }
}

proc report_project_coe_refs {} {
    puts "INFO: COE refs currently visible in project:"
    foreach f [lsort -unique [get_files -quiet *]] {
        set fn [file normalize $f]
        if {[string equal -nocase [file extension $fn] ".coe"]} {
            puts "  $fn"
        }
    }
}

proc purge_stale_coe_refs {repo_root} {
    set good_dir [string tolower [file normalize [file join $repo_root "coe"]]]

    foreach f [lsort -unique [get_files -quiet *]] {
        set fn [file normalize $f]

        if {![string equal -nocase [file extension $fn] ".coe"]} {
            continue
        }

        set fn_l [string tolower $fn]
        if {[string first "${good_dir}/" $fn_l] != 0} {
            puts "INFO: removing stale COE reference $fn"
            catch {remove_files $f}
        }
    }
}

proc add_clean_coe_files {srcset repo_root} {
    set clean_coe_list [list \
        [file join $repo_root "coe" "pss_0_td_128.coe"] \
        [file join $repo_root "coe" "pss_0_td_256.coe"] \
        [file join $repo_root "coe" "pss_1_td_128.coe"] \
        [file join $repo_root "coe" "pss_1_td_256.coe"] \
        [file join $repo_root "coe" "pss_2_td_128.coe"] \
        [file join $repo_root "coe" "pss_2_td_256.coe"] \
    ]

    foreach f $clean_coe_list {
        require_file_exists $f
        if {[llength [get_files -quiet [file normalize $f]]] == 0} {
            puts "INFO: adding clean COE $f"
            add_files -fileset $srcset -norecurse $f
        }
    }
}

proc maybe_fix_coe_path_for_ip {ip_name repo_root} {
    array set coe_map {
        pss_0_rom_td_128sps pss_0_td_128.coe
        pss_0_rom_td_256sps pss_0_td_256.coe
        pss_1_rom_td_128sps pss_1_td_128.coe
        pss_1_rom_td_256sps pss_1_td_256.coe
        pss_2_rom_td_128sps pss_2_td_128.coe
        pss_2_rom_td_256sps pss_2_td_256.coe
    }

    if {[info exists coe_map($ip_name)]} {
        set coe_path [file normalize [file join $repo_root "coe" $coe_map($ip_name)]]
        require_file_exists $coe_path

        set ip_obj [get_ips -quiet $ip_name]
        if {[llength $ip_obj] == 0} {
            error "ERROR: IP object not found for $ip_name"
        }

        puts "INFO: setting $ip_name CONFIG.Coe_File = $coe_path"
        set_property -dict [list CONFIG.Coe_File $coe_path] $ip_obj
        catch {set_property -dict [list CONFIG.Load_Init_File true] $ip_obj}
    }
}

proc add_generated_ip_synth_sources {srcset project_dir ip_name} {
    set gen_ip_dir [file join $project_dir "lte_phy_processing.gen" "sources_1" "ip" $ip_name]
    set shared_vhdl [list \
        [file join $gen_ip_dir "misc" "blk_mem_gen_v8_4.vhd"] \
        [file join $gen_ip_dir "hdl"  "blk_mem_gen_v8_4_vhsyn_rfs.vhd"] \
    ]

    foreach f $shared_vhdl {
        if {[file exists $f]} {
            set f_obj [get_files -quiet [file normalize $f]]
            if {[llength $f_obj] > 0} {
                set_property library blk_mem_gen_v8_4_7 $f_obj
            }
        }
    }
}

proc import_and_build_ip_list {srcset ip_dir ip_names repo_root project_dir} {
    set imported_ip_files [list]

    foreach ip_name $ip_names {
        set xci_path [file join $ip_dir $ip_name]
        require_file_exists $xci_path

        puts "INFO: IP import $xci_path"
        set ip_xci_list [import_ip -quiet -srcset $srcset $xci_path]
        if {[llength $ip_xci_list] == 0} {
            error "ERROR: import_ip returned empty list for: $xci_path"
        }

        set ip_xci [lindex $ip_xci_list 0]
        lappend imported_ip_files $ip_xci

        set ip_base [file rootname [file tail $xci_path]]
        maybe_fix_coe_path_for_ip $ip_base $repo_root

        generate_target all -force $ip_xci
        catch {export_ip_user_files -of_objects $ip_xci -no_script -sync -force}
        add_generated_ip_synth_sources $srcset $project_dir $ip_base
    }

    return $imported_ip_files
}

proc run_top_synth_reports {srcset top_name reports_dir part_name} {
    puts "INFO: starting synthesis for top=$top_name"

    set_property top $top_name [get_filesets $srcset]
    update_compile_order -fileset $srcset

    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1

    set synth_run [get_runs synth_1]
    set synth_status [get_property STATUS $synth_run]
    if {![string match "*Complete*" $synth_status]} {
        error "ERROR: synthesis run failed for top=$top_name with status '$synth_status'"
    }

    open_run synth_1

    report_utilization               -file [file join $reports_dir "${top_name}_utilization.rpt"]
    report_utilization -hierarchical -file [file join $reports_dir "${top_name}_utilization_hier.rpt"]
    report_timing_summary            -file [file join $reports_dir "${top_name}_timing_summary.rpt"]
    write_checkpoint -force [file join $reports_dir "${top_name}_synth.dcp"]

    close_design
}

# -----------------------------------------------------------------------------
# project creation
# -----------------------------------------------------------------------------

set PROJECT_DIR [file join $repo_root "vivado"]
file mkdir [file dirname $PROJECT_DIR]

create_project lte_phy_processing $PROJECT_DIR -force -part $ZEDBOARD_ZYNQ
set_property target_simulator XSim [current_project]

set IP_PATH       [file join $repo_root "ip"]
set HDL_V_PATH    [file join $repo_root "hdl/verilog"]
set HDL_SV_PATH   [file join $repo_root "hdl/systemverilog"]
set HDL_INC_PATH  [file join $repo_root "hdl/include"]
set MATH_INC_PATH [file join $LTE_PHY_MATH "hdl/include"]

require_file_exists [file join $repo_root "coe" "pss_0_td_128.coe"]
require_file_exists [file join $repo_root "coe" "pss_0_td_256.coe"]
require_file_exists [file join $repo_root "coe" "pss_1_td_128.coe"]
require_file_exists [file join $repo_root "coe" "pss_1_td_256.coe"]
require_file_exists [file join $repo_root "coe" "pss_2_td_128.coe"]
require_file_exists [file join $repo_root "coe" "pss_2_td_256.coe"]

require_file_exists [file join $HDL_INC_PATH "lte_hw_params.vh"]
require_file_exists [file join $HDL_SV_PATH  "lte_phy_sync.sv"]
require_file_exists [file join $HDL_SV_PATH  "lte_phy_pss_corr.sv"]
require_file_exists [file join $HDL_SV_PATH  "mem_ring_buffer.sv"]
require_file_exists [file join $HDL_SV_PATH  "system_lte.sv"]
require_file_exists [file join $HDL_V_PATH   "system_lte_bd.v"]

# -----------------------------------------------------------------------------
# sources_1
# -----------------------------------------------------------------------------

set inc_dirs [list \
    $HDL_V_PATH \
    $HDL_SV_PATH \
    $HDL_INC_PATH \
    $MATH_INC_PATH \
]

add_files -fileset sources_1 -norecurse [list                               \
    [file join $HDL_INC_PATH "lte_hw_params.vh"]                            \
    [file join $HDL_SV_PATH "mem_ring_buffer.sv"]                           \
    [file join $HDL_SV_PATH "lte_phy_pss_corr.sv"]                          \
    [file join $HDL_SV_PATH "lte_phy_sync.sv"]                              \
    [file join $HDL_SV_PATH "system_lte.sv"]                                \
    [file join $HDL_V_PATH  "system_lte_bd.v"]                              \
    [file join $HDL_SV_PATH "mem_sdpram_wrap.sv"]                           \
    [file join $LTE_PHY_MATH "hdl" "systemverilog" "math_complex_corr.sv"]  \
    [file join $LTE_PHY_MATH "hdl" "systemverilog" "math_mac_macro.sv"]     \
    [file join $LTE_PHY_MATH "hdl" "include" "lte_phy_math.vh"]             \
]

set_property include_dirs $inc_dirs [get_filesets sources_1]

mark_header_as_global_include [file join $HDL_INC_PATH "lte_hw_params.vh"]
mark_header_as_global_include [file join $LTE_PHY_MATH "hdl" "include" "lte_phy_math.vh"]

# -----------------------------------------------------------------------------
# import prebuilt XCI and regenerate output products
# -----------------------------------------------------------------------------

set MEM_IP_XCI [list \
    "mem_gen_256k32.xci" \
    "mem_gen_512k32.xci" \
]

set PSS_IP_XCI [list \
    [file join "pss_0_rom_td_128sps" "pss_0_rom_td_128sps.xci"] \
    [file join "pss_0_rom_td_256sps" "pss_0_rom_td_256sps.xci"] \
    [file join "pss_1_rom_td_128sps" "pss_1_rom_td_128sps.xci"] \
    [file join "pss_1_rom_td_256sps" "pss_1_rom_td_256sps.xci"] \
    [file join "pss_2_rom_td_128sps" "pss_2_rom_td_128sps.xci"] \
    [file join "pss_2_rom_td_256sps" "pss_2_rom_td_256sps.xci"] \
]

set imported_ip_files [list]
set imported_ip_files [concat $imported_ip_files [import_and_build_ip_list sources_1 $IP_PATH $MEM_IP_XCI $repo_root $PROJECT_DIR]]
set imported_ip_files [concat $imported_ip_files [import_and_build_ip_list sources_1 $IP_PKG_SRC_PATH $PSS_IP_XCI $repo_root $PROJECT_DIR]]

puts "INFO: COE refs before purge"
report_project_coe_refs

purge_stale_coe_refs $repo_root
add_clean_coe_files sources_1 $repo_root

puts "INFO: COE refs after purge/re-add"
report_project_coe_refs

# -----------------------------------------------------------------------------
# top / compile order
# -----------------------------------------------------------------------------

set_property top system_lte_bd [get_filesets sources_1]
update_compile_order -fileset sources_1

puts {INFO: [RTL] sources_1 filled OK}

if {$RUN_TOP_SYNTH} {
    set REPORTS_DIR [file join $repo_root "vivado" "reports"]
    file mkdir $REPORTS_DIR

    run_top_synth_reports sources_1 lte_phy_pss_corr $REPORTS_DIR $ZEDBOARD_ZYNQ
    run_top_synth_reports sources_1 system_lte_bd $REPORTS_DIR $ZEDBOARD_ZYNQ
    run_top_synth_reports sources_1 system_lte    $REPORTS_DIR $ZEDBOARD_ZYNQ

    set_property top system_lte_bd [get_filesets sources_1]
    update_compile_order -fileset sources_1

    puts "INFO: synthesis reports are in $REPORTS_DIR"
}

# -----------------------------------------------------------------------------
# simulation filesets (only when not packaging)
# -----------------------------------------------------------------------------

set TB_EBMG  [file join $repo_root "devl" "example_blk_mem_gen_0"]
set TB_LPPMT [file join $repo_root "devl" "lte_phy_pss_mem_test"]
set TB_LPPC  [file join $repo_root "devl" "lte_phy_pss_corr"]
set TB_LPS   [file join $repo_root "devl" "lte_phy_sync"]

if {!$DO_PACKAGE} {

    if {[string equal [get_filesets -quiet sim_lte_system] ""]} {
        create_fileset -simset sim_lte_system
    }

    if {[string equal [get_filesets -quiet example_blk_mem_gen_0] ""]} {
        set s_set example_blk_mem_gen_0
        create_fileset -simset $s_set

        add_files -fileset $s_set -norecurse [list \
            [file join $TB_EBMG "testbench.sv"] \
        ]

        set_property include_dirs $inc_dirs [get_filesets $s_set]
        set_property top testbench          [get_filesets $s_set]

        update_compile_order -fileset $s_set
    }

    if {[string equal [get_filesets -quiet lte_phy_pss_mem_test] ""]} {
        set s_set lte_phy_pss_mem_test
        create_fileset -simset $s_set

        add_files -fileset $s_set -norecurse [list \
            [file join $TB_LPPMT "testbench.sv"]         \
            [file join $TB_LPPMT "testbench_behav.wcfg"] \
        ]

        set_property xsim.view    [file join $TB_LPPMT "testbench_behav.wcfg"] [get_filesets $s_set]
        set_property include_dirs $inc_dirs                                    [get_filesets $s_set]
        set_property top testbench                                             [get_filesets $s_set]

        update_compile_order -fileset $s_set
    }

    if {[string equal [get_filesets -quiet lte_phy_sync] ""]} {
        set s_set lte_phy_sync
        create_fileset -simset $s_set

        add_files -fileset $s_set -norecurse [list \
            [file join $TB_LPS "testbench.sv"]          \
            [file join $TB_LPS "testbench_behav.wcfg"]  \
            [file join $TB_LPS "input_signal.hex"]      \
            [file join $TB_LPS "input_awgn.hex"]        \
        ]

        set_property xsim.view    [file join $TB_LPS "testbench_behav.wcfg"] [get_filesets $s_set]
        set_property include_dirs $inc_dirs                                  [get_filesets $s_set]
        set_property top testbench                                           [get_filesets $s_set]

        update_compile_order -fileset $s_set
    }

    if {[string equal [get_filesets -quiet lte_phy_pss_corr] ""]} {
        set s_set lte_phy_pss_corr
        create_fileset -simset $s_set

        add_files -fileset $s_set -norecurse [list \
            [file join $TB_LPPC "testbench.sv"]          \
            [file join $TB_LPS  "input_signal.hex"]      \
        ]

        set_property include_dirs $inc_dirs             [get_filesets $s_set]
        set_property top tb_lte_phy_pss_corr            [get_filesets $s_set]

        update_compile_order -fileset $s_set
    }
}

# -----------------------------------------------------------------------------
# package project into custom IP
# -----------------------------------------------------------------------------

if {$DO_PACKAGE} {

    if {[file exists $IP_PKG_DIR]} {
        file delete -force $IP_PKG_DIR
    }
    file mkdir $IP_PKG_DIR

    ipx::package_project                        \
        -root_dir    $IP_PKG_DIR                \
        -vendor      aes-technology.ru          \
        -library     user                       \
        -taxonomy    /UserIP                    \
        -import_files                           \
        -set_current true

    set core [ipx::current_core]

    set_property name         $IP_NAME                 $core
    set_property display_name "LTE PHY Processing"    $core
    set_property description  "LTE PHY processing IP" $core
    set_property version      "1.2"                   $core

    ipx::update_checksums $core
    ipx::save_core        $core

    puts "INFO: IP packaged into: $IP_PKG_DIR"
}
