# Current makefile path
# PS: MAKEFILE_LIST - массив MAKEFILE_LIST 
# которые участвовали в стеке вызова. От первого, который запустился (firstword)
# до последнего, это если firstword замеить на lastword 
# т.к. этот makefile НЕ БУДЕТ корневым (т.е. он будет запускаться другим makefile), то lastword
# если я вызываю из директории lte_phy_math, то THIS_MAKE будет хранить .\vivado\Makefile
THIS_MAKE = $(lastword $(MAKEFILE_LIST)) 

# с помощью realpath мы получаем не относительный путь, а абсолютный путь до ФАЙЛА
# и с помощью dir возвращаем не путь до файла, а путь до директории, где лежит этот файл
# вот так вот
MAKE_DIR  = $(dir $(realpath $(THIS_MAKE)))

# корень проекта (просто алиас к переменной)
REPO_ROOT = $(MAKE_DIR)

VIVADO ?= vivado

project:
	@echo "Create project" 
	@cd $(REPO_ROOT)/devl/lte_phy_sync && tar -xzf ./compressed/input_files.tar.gz -C ./
	@cd $(REPO_ROOT)/vivado/ && "$(VIVADO)" -mode batch -notrace -source "system_bd.tcl" && cd ..

synth:
	@echo "Create project and run synthesis/resource reports"
	@cd $(REPO_ROOT)/devl/lte_phy_sync && tar -xzf ./compressed/input_files.tar.gz -C ./
	@cd $(REPO_ROOT)/vivado/ && "$(VIVADO)" -mode batch -notrace -source "synth_resources.tcl" && cd ..

synth_k8:
	@echo "Create project and run K=8 synthesis/resource report"
	@cd $(REPO_ROOT)/devl/lte_phy_sync && tar -xzf ./compressed/input_files.tar.gz -C ./
	@cd $(REPO_ROOT)/vivado/ && "$(VIVADO)" -mode batch -notrace -source "synth_k8_resources.tcl" && cd ..

synth_k2:
	@echo "Create project and run K=2 synthesis/resource report"
	@cd $(REPO_ROOT)/devl/lte_phy_sync && tar -xzf ./compressed/input_files.tar.gz -C ./
	@cd $(REPO_ROOT)/vivado/ && "$(VIVADO)" -mode batch -notrace -source "synth_k2_resources.tcl" && cd ..

sim_pss_corr:
	@echo "Create project and run lte_phy_pss_corr simulation"
	@cd $(REPO_ROOT)/devl/lte_phy_sync && tar -xzf ./compressed/input_files.tar.gz -C ./
	@cd $(REPO_ROOT)/vivado/ && "$(VIVADO)" -mode batch -notrace -source "sim_pss_corr.tcl" && cd ..

clean: 
	@echo "Clean project"
	rm -rf $(REPO_ROOT)vivado/lte_phy_processing.*
	rm -rf $(REPO_ROOT)vivado/.Xil
	rm -f $(REPO_ROOT)vivado/vivado_*.backup.log
	rm -f $(REPO_ROOT)vivado/vivado_*.backup.jou
	rm -f $(REPO_ROOT)vivado/vivado_pid*.str
	rm -f $(REPO_ROOT)vivado/vivado.log
	rm -f $(REPO_ROOT)vivado/vivado.jou
	rm -f $(REPO_ROOT)vivado/*.tmp

finaly:
	@echo "Create finaly build"
	cd $(REPO_ROOT)../ && git clone https://github.com/analogdevicesinc/hdl.git ./hw_hdl 
	cd $(REPO_ROOT)../hw_hdl && git fetch --tags origin && git checkout hdl_2023_r2
	cd $(REPO_ROOT)../hw_hdl/projects/fmcomms2/zed && make

	cd $(REPO_ROOT)

help:
	@echo "make project"
	@echo "make synth"
	@echo "make synth_k2"
	@echo "make synth_k8"
	@echo "make sim_pss_corr"
	
