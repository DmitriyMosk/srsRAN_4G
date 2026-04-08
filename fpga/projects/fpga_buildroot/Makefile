ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
IMAGE_NAME ?= fpga_buildroot-dev
CONTAINER_NAME ?= fpga_buildroot-dev
SSH_PORT ?= 2222

DOCKERFILE := $(ROOT_DIR)/docker/Dockerfile
WORKSPACE_DIR := $(ROOT_DIR)
APP_NAME ?= ltemon
APP_SOURCE_DIR := /workspace/project/$(APP_NAME)
APP_BUILD_DIR := /workspace/build/$(APP_NAME)

.PHONY: build run restart stop rm status logs shell ssh prepare-sysroot app-configure app-build app-clean

build:
	docker build -t $(IMAGE_NAME) -f "$(DOCKERFILE)" "$(ROOT_DIR)"

run: rm build
	docker run -d \
		--name $(CONTAINER_NAME) \
		--hostname fpga-buildroot \
		-p $(SSH_PORT):22 \
		-v "$(WORKSPACE_DIR):/workspace" \
		$(IMAGE_NAME)
	@echo "Container started."
	@echo "SSH: ssh dev@127.0.0.1 -p $(SSH_PORT)   (password: dev)"

restart: stop run

stop:
	- docker stop $(CONTAINER_NAME)

rm:
	- docker rm -f $(CONTAINER_NAME)

status:
	- docker ps -a --filter "name=$(CONTAINER_NAME)"

logs:
	docker logs -f $(CONTAINER_NAME)

shell:
	docker exec -it -u dev $(CONTAINER_NAME) bash

ssh:
	ssh dev@127.0.0.1 -p $(SSH_PORT)

prepare-sysroot:
	docker exec $(CONTAINER_NAME) /usr/local/bin/prepare-kuiper-sysroot

app-configure: prepare-sysroot
	docker exec -u dev $(CONTAINER_NAME) cmake -S $(APP_SOURCE_DIR) -B $(APP_BUILD_DIR) -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=/workspace/project/tools/toolchain-arm-linux-gnueabihf-kuiper.cmake

app-build: app-configure
	docker exec -u dev $(CONTAINER_NAME) cmake --build $(APP_BUILD_DIR) --parallel

app-clean:
	docker exec $(CONTAINER_NAME) rm -rf $(APP_BUILD_DIR)
