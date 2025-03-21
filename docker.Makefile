#
# github.com/docker/cli
#
# Makefile for developing using Docker
#

# Overridable env vars
DOCKER_CLI_MOUNTS ?= -v "$(CURDIR)":/go/src/github.com/docker/cli
DOCKER_CLI_CONTAINER_NAME ?=
DOCKER_CLI_GO_BUILD_CACHE ?= y

DEV_DOCKER_IMAGE_NAME = docker-cli-dev$(IMAGE_TAG)
BINARY_NATIVE_IMAGE_NAME = docker-cli-native$(IMAGE_TAG)
CROSS_IMAGE_NAME = docker-cli-cross$(IMAGE_TAG)
E2E_IMAGE_NAME = docker-cli-e2e$(IMAGE_TAG)
E2E_ENGINE_VERSION ?=
CACHE_VOLUME_NAME := docker-cli-dev-cache
ifeq ($(DOCKER_CLI_GO_BUILD_CACHE),y)
DOCKER_CLI_MOUNTS += -v "$(CACHE_VOLUME_NAME):/root/.cache/go-build"
endif
VERSION = $(shell cat VERSION)
ENVVARS = -e VERSION=$(VERSION) -e GITCOMMIT -e PLATFORM -e TESTFLAGS -e TESTDIRS -e GOOS -e GOARCH -e GOARM -e TEST_ENGINE_VERSION=$(E2E_ENGINE_VERSION)

# Some Dockerfiles use features that are only supported with BuildKit enabled
export DOCKER_BUILDKIT=1

# build docker image (dockerfiles/Dockerfile.build)
.PHONY: build_docker_image
build_docker_image:
	# build dockerfile from stdin so that we don't send the build-context; source is bind-mounted in the development environment
	cat ./dockerfiles/Dockerfile.dev | docker build ${DOCKER_BUILD_ARGS} --build-arg=GO_VERSION -t $(DEV_DOCKER_IMAGE_NAME) -

.PHONY: build_binary_native_image
build_binary_native_image:
	# build dockerfile from stdin so that we don't send the build-context; source is bind-mounted in the development environment
	cat ./dockerfiles/Dockerfile.binary-native | docker build --build-arg=GO_VERSION -t $(BINARY_NATIVE_IMAGE_NAME) -

.PHONY: build_e2e_image
build_e2e_image:
	docker build -t $(E2E_IMAGE_NAME) --build-arg=GO_VERSION --build-arg VERSION=$(VERSION) --build-arg GITCOMMIT=$(GITCOMMIT) -f ./dockerfiles/Dockerfile.e2e .

DOCKER_RUN_NAME_OPTION := $(if $(DOCKER_CLI_CONTAINER_NAME),--name $(DOCKER_CLI_CONTAINER_NAME),)
DOCKER_RUN := docker run --rm $(ENVVARS) $(DOCKER_CLI_MOUNTS) $(DOCKER_RUN_NAME_OPTION)

.PHONY: binary
binary:
	docker buildx bake binary

build: binary ## alias for binary

plugins: build_binary_native_image ## build the CLI plugin examples
	$(DOCKER_RUN) $(BINARY_NATIVE_IMAGE_NAME) ./scripts/build/plugins

.PHONY: clean
clean: build_docker_image ## clean build artifacts
	$(DOCKER_RUN) $(DEV_DOCKER_IMAGE_NAME) make clean
	docker volume rm -f $(CACHE_VOLUME_NAME)

.PHONY: test-unit
test-unit: build_docker_image ## run unit tests (using go test)
	$(DOCKER_RUN) $(DEV_DOCKER_IMAGE_NAME) make test-unit

.PHONY: test ## run unit and e2e tests
test: test-unit test-e2e

.PHONY: cross
cross:
	docker buildx bake cross

.PHONY: plugins-windows
plugins-windows: build_cross_image ## build the example CLI plugins for Windows
	$(DOCKER_RUN) $(CROSS_IMAGE_NAME) make $@

.PHONY: plugins-osx
plugins-osx: build_cross_image ## build the example CLI plugins for macOS
	$(DOCKER_RUN) $(CROSS_IMAGE_NAME) make $@

.PHONY: dynbinary
dynbinary: ## build dynamically linked binary
	USE_GLIBC=1 docker buildx bake dynbinary

.PHONY: dev
dev: build_docker_image ## start a build container in interactive mode for in-container development
	$(DOCKER_RUN) -it \
		--mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
		$(DEV_DOCKER_IMAGE_NAME)

shell: dev ## alias for dev

.PHONY: lint
lint: ## run linters
	docker buildx bake lint

.PHONY: shellcheck
shellcheck: ## run shellcheck validation
	docker buildx bake shellcheck

.PHONY: fmt
fmt: ## run gofmt
	$(DOCKER_RUN) $(DEV_DOCKER_IMAGE_NAME) make fmt

.PHONY: vendor
vendor: build_docker_image vendor.conf ## download dependencies (vendor/) listed in vendor.conf
	$(DOCKER_RUN) -it $(DEV_DOCKER_IMAGE_NAME) make vendor

.PHONY: authors
authors: ## generate AUTHORS file from git history
	$(DOCKER_RUN) -it $(DEV_DOCKER_IMAGE_NAME) make authors

.PHONY: manpages
manpages: build_docker_image ## generate man pages from go source and markdown
	$(DOCKER_RUN) -it $(DEV_DOCKER_IMAGE_NAME) make manpages

.PHONY: yamldocs
yamldocs: build_docker_image ## generate documentation YAML files consumed by docs repo
	$(DOCKER_RUN) -it $(DEV_DOCKER_IMAGE_NAME) make yamldocs

.PHONY: test-e2e
test-e2e: test-e2e-non-experimental test-e2e-experimental test-e2e-connhelper-ssh ## run all e2e tests

.PHONY: test-e2e-experimental
test-e2e-experimental: build_e2e_image # run experimental e2e tests
	docker run --rm --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock $(ENVVARS) -e DOCKERD_EXPERIMENTAL=1 $(E2E_IMAGE_NAME)

.PHONY: test-e2e-non-experimental
test-e2e-non-experimental: build_e2e_image # run non-experimental e2e tests
	docker run --rm --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock $(ENVVARS) -e TEST_ENGINE_VERSION=$(E2E_ENGINE_VERSION) $(E2E_IMAGE_NAME)

.PHONY: test-e2e-connhelper-ssh
test-e2e-connhelper-ssh: build_e2e_image # run experimental SSH-connection helper e2e tests
	docker run --rm --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock $(ENVVARS) -e DOCKERD_EXPERIMENTAL=1 -e TEST_CONNHELPER=ssh $(E2E_IMAGE_NAME)

.PHONY: help
help: ## print this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {gsub("\\\\n",sprintf("\n%22c",""), $$2);printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
