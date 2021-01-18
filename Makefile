SHELL = /bin/sh

DOCKER ?= docker
GIT ?= git
MKDIR ?= mkdir -p
RM ?= rm -f

# The following args have been provided default values but can be overriden
# from the CLI by specifying those variables with the override values or by
# declaring those variables in the project.mk file which is conditionally
# included after variable declaration in this Makefile.

# Path to the shippable part of your application
# The shippable part of your application should contain manifest files
# (package.json and package-lock.json in case of NPM, package.json and
# yarn.lock in case of Yarn) and the actual source that you will want to run
# inside of your container.
srcdir ?= .

# Path to the working directory on the host
# The working directory will contain the home directory that is mounted into
# the Docker container, package caches and other artifacts that may be be used
# to aid in development.
workdir = .

# Absolute path to Dockerfile
Dockerfile = ./Dockerfile

# Docker stage to build in case of a multi-stage build
# Defaults to the build stage when undefined as it is fair to assume that
# manually invoking GNU Make rules is likelier to happen from a software
# developer's workstation as opposed to a production build environment and
# therefore the ability to spawn a working build/development environment with
# minimal manual effort renders this design choice sensible.
stage ?= build

# Prefix for Docker images
PROJECT_NAME ?=
# Override an empty PROJECT_NAME to equal the source directory name
ifeq ($(strip $(PROJECT_NAME)),)
PROJECT_NAME = $(notdir $(realpath $(srcdir)))
endif

# Version of the application to build
PROJECT_VERSION ?=
ifeq ($(strip $(PROJECT_VERSION)),)
PROJECT_VERSION = $(shell $(GIT) describe --always --dirty)
endif

# Ports of the application to expose
APP_PORTS ?= 8000/tcp

SYSTEM_PACKAGES ?= ca-certificates git calibre

# Version for the base Node.js Docker image
# The notation of the version should match the semver notation for which there
# are official Docker images available, otherwise the IMAGE variable will have
# to be modified to pull the appropriate Docker base image.
RUNTIME_VERSION ?= 12.18.2

# Docker image registry
DOCKER_REGISTRY ?= index.docker.io/

# Base image (as FROM) for all project images
# Try to use official images as much as possible.
# https://docs.docker.com/docker-hub/official_images/
DOCKER_BASE_IMAGE ?= $(DOCKER_REGISTRY)node:$(RUNTIME_VERSION)-stretch-slim

# Node.js dependency installation command
# The following example installation commands should work:
# -	for projects that use NPM: `npm install`
# - for projects that use Yarn: `yarn install`
PACKAGE_INSTALLER ?= npm install

# Host address for port mapping
# Don't use 0.0.0.0 as this opens up your machine,
HOST_ADDRESS ?= 127.0.0.1

# Version to use for tagging images
# By default the PROJECT_VERSION and RUNTIME_VERSION are factored into the
# VERSION variable such that RUNTIME_VERSION is part of the pre-release clause.
# The reason the build metadata was not utilized in this case is because Docker
# does not allow for tags containing build metadata clauses since plus-signs
# (+) are technically not allowed in Docker tags.
# https://semver.org/
VERSION ?= $(PROJECT_VERSION)-nodejs-$(RUNTIME_VERSION)


# Docker container parameters

# Home path of the container in order to adequately mount .homedir
DOCKER_CONTAINER_HOME_PATH = /home/developer

# Ports of the container to expose
DOCKER_CONTAINER_PORTS = $(APP_PORTS)


# Docker host parameters

# IP address or hostname of the host, defaults to the host loopback address
DOCKER_HOST_ADDRESS = $(HOST_ADDRESS)

# Docker image name
DOCKER_IMAGE_NAME = $(PROJECT_NAME)

# Docker image tag
DOCKER_IMAGE_TAG = $(VERSION)

# Caching flag for Docker build process
# Disable caching to force the docker builder to always rebuild all layers and
# thus minimize the chances of cached layers providing a false sense of build
# validity. If a build is broken because some resource is no longer available
# from the registries, you would need to know this as soon as possible i.e.:
# before hitting production environments.
DOCKER_CACHE_FLAG ?= "--no-cache"

# Arguments for Docker image builds
# - DOCKER_BASE_IMAGE defines the Docker image to use in the FROM instruction
# - DOCKER_PORTS defines the ports to expose on the production image
# - PROJECT defines the name of the project and name of the subdirectory of
#   /opt where to install the project
# - PACKAGE_INSTALLER defines the command to install Node.js packages
DOCKER_BUILD_ARGS = \
	--build-arg=IMAGE="$(DOCKER_BASE_IMAGE)" \
	--build-arg=PACKAGE_INSTALLER="$(PACKAGE_INSTALLER)" \
	--build-arg=PORTS="$(DOCKER_CONTAINER_PORTS)" \
	--build-arg=PROJECT="$(PROJECT_NAME)" \
	--build-arg=SYSTEM_PACKAGES="$(SYSTEM_PACKAGES)"

# Define the command line arguments to use in spawning Docker runs.
# - Defines environment variables (-e)
# - Defines port mappings (-p)
# - Sets the UID and GID to those of the host user (-u)
#   Ensures sensible ownership defaults on Linux hosts
# - Mounts volumes (-v)
# - Sets working directory (-w)
DOCKER_ARGS = \
	-e "PROJECT=$(PROJECT_NAME)" \
	-e "HOME=$(DOCKER_CONTAINER_HOME_PATH)" \
	-u $(shell id -u):$(shell id -g) \
	-v $(realpath $(workdir)/.homedir):$(DOCKER_CONTAINER_HOME_PATH) \
	-v $(realpath $(srcdir)):/tmp/$(PROJECT_NAME) \
	-w /tmp/$(PROJECT_NAME)


# Include the project.mk file if it exists to override defined parameters
-include project.mk

# Spawn a Bash shell
bash: $(srcdir) $(workdir)
	$(MKDIR) \
		$(workdir)/.homedir
ifeq ($(strip $(stage)),production)
	$(DOCKER) run \
		$(DOCKER_ARGS) \
		--rm -it \
		--entrypoint=bash \
		$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)
else
	$(DOCKER) run \
		$(DOCKER_ARGS) \
		--rm -it \
		--entrypoint=bash \
		$(DOCKER_IMAGE_NAME):$(stage)
endif

# Remove temporary files
clean: $(workdir)
	$(RM) \
		$(workdir)/.homedir/.config \
		$(workdir)/.homedir/.npm \
		$(workdir)/.homedir/.serverless \
		$(workdir)/.homedir/.serverlessrc

# Build the Docker image
image: $(srcdir)
ifeq ($(strip $(stage)),production) # production stage
	$(DOCKER) build \
		$(DOCKER_BUILD_ARGS) \
		$(DOCKER_CACHE_FLAG) \
		--file=$(Dockerfile) \
		--rm \
		--tag=$(DOCKER_IMAGE_NAME) \
		--tag=$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG) \
		--target=production \
		$(srcdir)
else # build stage
	$(DOCKER) build \
		$(DOCKER_BUILD_ARGS) \
		$(DOCKER_CACHE_FLAG) \
		--file=$(Dockerfile) \
		--rm \
		--tag=$(DOCKER_IMAGE_NAME):$(stage) \
		--tag=$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)-$(stage) \
		--target=$(stage) \
		$(srcdir)
endif

.PHONY: bash clean image
