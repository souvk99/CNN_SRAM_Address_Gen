open_project [file normalize "CNN_SRAM_Address_Gen.xpr"]
set_property top cnn_addr_gen [get_filesets sources_1]
set_property top tb_cnn_addr_gen [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit

