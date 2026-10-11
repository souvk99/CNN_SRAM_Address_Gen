create_project -force CNN_SRAM_Address_Gen . -part xc7a35tcpg236-1
add_files -fileset sources_1 [file normalize "sram_4bank_cnn.v"]
add_files -fileset sources_1 [file normalize "cnn_addr_gen.v"]
add_files -fileset sim_1 [file normalize "tb_cnn_addr_gen.v"]
set_property top cnn_addr_gen [get_filesets sources_1]
set_property top tb_cnn_addr_gen [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit
