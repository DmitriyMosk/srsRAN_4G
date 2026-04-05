SHELL := /bin/bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
IMAGE_NAME ?= fpga_buildroot-dev
CONTAINER_NAME ?= fpga_buildroot-dev
SSH_PORT ?= 2222

PROJECT_DIR := $(ROOT_DIR)/project
TOOLS_DIR := $(ROOT_DIR)/project/tools
BUILDROOT_DIR := $(ROOT_DIR)/buildroot
DOCKERFILE := $(ROOT_DIR)/docker/Dockerfile

.PHONY: build run restart stop rm status logs shell ssh

build:
	docker build -t $(IMAGE_NAME) -f "$(DOCKERFILE)" "$(ROOT_DIR)"

run: rm build
	docker run -d \
		--name $(CONTAINER_NAME) \
		--hostname fpga-buildroot \
		-p $(SSH_PORT):22 \
		-v "$(PROJECT_DIR):/workspace/project" \
		-v "$(TOOLS_DIR):/workspace/tools" \
		-v "$(BUILDROOT_DIR):/workspace/buildroot" \
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
