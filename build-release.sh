#!/bin/bash

# This script will build all of the artifacts involved in a new Rocket Pool smartnode release
# (except for the macOS daemons, which need to be built manually on a macOS system) and put
# them into a convenient folder for ease of uploading.

# NOTE: You MUST put this in a directory that has the `smartnode` and `smartnode-install`
# repositories cloned as subdirectories.


# =========================
# === Config Parameters ===
# =========================

# The hostname / address of the arm64 machine
ARM_ADDRESS=""

# The port that the arm64 machine's SSH server is listening on
ARM_PORT=""

# The username to SSH with on the arm64 machine
ARM_USER=""

# The path on the arm64 machine that holds this script (e.g. if this script was run locally on that machine
# and lived in `/srv/gogopool` so the build artifacts went to `/srv/gogopool/v1.0.0`, then you would set
# this to `/srv/gogopool`).
ARM_PATH=""


# =================
# === Functions ===
# =================

# Print a failure message to stderr and exit
fail() {
    MESSAGE=$1
    RED='\033[0;31m'
    RESET='\033[;0m'
    >&2 echo -e "\n${RED}**ERROR**\n$MESSAGE${RESET}\n"
    exit 1
}


# Builds all of the CLI binaries
build_cli() {
    cd smartnode/gogopool-cli || fail "Directory ${PWD}/smartnode/gogopool-cli does not exist or you don't have permissions to access it."
    rm -f gogopool-cli-*

    echo -n "Building CLI binaries... "
    ./build.sh || fail "Error building CLI binaries."
    mv gogopool-cli-linux-amd64 ../../$VERSION
    mv gogopool-cli-darwin-amd64 ../../$VERSION
    mv gogopool-cli-linux-arm64 ../../$VERSION
    mv gogopool-cli-darwin-arm64 ../../$VERSION
    echo "done!"

    cd ../..
}


# Builds the .tar.xz file packages with the RP configuration files
build_install_packages() {
    cd smartnode-install || fail "Directory ${PWD}/smartnode-install does not exist or you don't have permissions to access it."
    rm -f amd64/rp-smartnode-install-amd64.tar.xz
    rm -f arm64/rp-smartnode-install-arm64.tar.xz

    echo -n "Building Smartnode installer packages... "
    tar cfJ amd64/rp-smartnode-install-amd64.tar.xz amd64/rp-smartnode-install || fail "Error building amd64 package."
    tar cfJ arm64/rp-smartnode-install-arm64.tar.xz arm64/rp-smartnode-install || fail "Error building arm64 package."
    mv amd64/rp-smartnode-install-amd64.tar.xz ../$VERSION
    mv arm64/rp-smartnode-install-arm64.tar.xz ../$VERSION
    cp install.sh ../$VERSION
    cp install-update-tracker.sh ../$VERSION
    echo "done!"

    echo -n "Building update tracker package... "
    tar cfJ rp-update-tracker.tar.xz rp-update-tracker || fail "Error building update tracker package."
    mv rp-update-tracker.tar.xz ../$VERSION
    echo "done!"

    cd ..
}


# Builds the daemon binary
build_daemon() {
    cd smartnode || fail "Directory ${PWD}/smartnode does not exist or you don't have permissions to access it."
    rm -f gogopool/gogopool-daemon-*

    if [ -z "$ARM_ADDRESS" ]; then
        echo "ARM machine address not provided, skipping retrieval of the arm64 binary."
    else
        echo -n "Retrieving arm64 binary... "
        scp -P $ARM_PORT $ARM_USER@$ARM_ADDRESS:$ARM_PATH/$VERSION/gogopool-daemon-linux-arm64 ../$VERSION || fail "Copying the arm64 daemon failed."
        echo "done!"
    fi

    echo -n "Building Daemon binary... "
    ./daemon-build.sh || fail "Error building daemon binary."
    mv gogopool/gogopool-daemon-* ../$VERSION
    echo "done!"

    cd ..
}


# Builds the Docker Smartnode image and pushes it to Docker Hub
build_docker_smartnode() {
    cd smartnode || fail "Directory ${PWD}/smartnode does not exist or you don't have permissions to access it."

    echo "Building Docker Smartnode image..."
    docker build -t gogopool/smartnode:$VERSION-$ARCH -f docker/gogopool-dockerfile . || fail "Error building Docker Smartnode image."
    echo "done!"
    echo -n "Pushing to Docker Hub... "
    docker push gogopool/smartnode:$VERSION-$ARCH || fail "Error pushing Docker Smartnode image to Docker Hub."
    echo "done!"
    
    cd ..
}


# Builds the Docker POW Proxy image and pushes it to Docker Hub
build_docker_pow_proxy() {
    cd smartnode || fail "Directory ${PWD}/smartnode does not exist or you don't have permissions to access it."

    echo "Building Docker POW Proxy image..."
    docker build -t gogopool/smartnode-pow-proxy:$VERSION-$ARCH -f docker/gogopool-pow-proxy-dockerfile . || fail "Error building Docker POW Proxy image."
    echo "done!"
    echo -n "Pushing to Docker Hub... "
    docker push gogopool/smartnode-pow-proxy:$VERSION-$ARCH || fail "Error pushing Docker POW Proxy image to Docker Hub."
    echo "done!"
    
    cd ..
}


# Builds the Docker prune provisioner image and pushes it to Docker Hub
build_docker_prune_provision() {
    cd smartnode || fail "Directory ${PWD}/smartnode does not exist or you don't have permissions to access it."

    echo "Building Docker Prune Provisioner image..."
    docker build -t gogopool/eth1-prune-provision:$VERSION-$ARCH -f docker/gogopool-prune-provision . || fail "Error building Docker Prune Provision image."
    echo "done!"
    echo -n "Pushing to Docker Hub... "
    docker push gogopool/eth1-prune-provision:$VERSION-$ARCH || fail "Error pushing Docker Prune Provision image to Docker Hub."
    echo "done!"
    
    cd ..
}


# Builds the Docker Manifests and pushes them to Docker Hub
build_docker_manifest() {
    echo -n "Building Docker manifests... "
    rm -f ~/.docker/manifests/docker.io_gogopool_smartnode-$VERSION
    rm -f ~/.docker/manifests/docker.io_gogopool_smartnode-pow-proxy-$VERSION
    docker manifest create gogopool/smartnode:$VERSION --amend gogopool/smartnode:$VERSION-amd64 --amend gogopool/smartnode:$VERSION-arm64
    docker manifest create gogopool/smartnode-pow-proxy:$VERSION --amend gogopool/smartnode-pow-proxy:$VERSION-amd64 --amend gogopool/smartnode-pow-proxy:$VERSION-arm64
    echo "done!"
    echo -n "Pushing to Docker Hub... "
    docker manifest push --purge gogopool/smartnode:$VERSION
    docker manifest push --purge gogopool/smartnode-pow-proxy:$VERSION
    echo "done!"
}


# Builds the Docker Manifest for the prune provisioner and pushes it to Docker Hub
build_docker_prune_provision_manifest() {
    echo -n "Building Docker Prune Provision manifests... "
    rm -f ~/.docker/manifests/docker.io_gogopool_eth1-prune-provision-$VERSION
    docker manifest create gogopool/eth1-prune-provision:$VERSION --amend gogopool/eth1-prune-provision:$VERSION-amd64 --amend gogopool/eth1-prune-provision:$VERSION-arm64
    echo "done!"
    echo -n "Pushing to Docker Hub... "
    docker manifest push --purge gogopool/eth1-prune-provision:$VERSION
    echo "done!"
}


# Print usage
usage() {
    echo "Usage: build-release.sh [options] -v <version number>"
    echo "This script assumes it is in a directory that contains subdirectories for all of the Rocket Pool repositories."
    echo "To copy the arm64 daemon binary from a remote system, set the appropriate variables at the top of this file."
    echo "Options:"
    echo $'\t-a\tBuild all of the artifacts, except for the prune provisioner'
    echo $'\t-c\tBuild the CLI binaries for all platforms'
    echo $'\t-m\tBuild the Daemon binary for this local platform'
    echo $'\t-p\tBuild the Smartnode installer packages'
    echo $'\t-d\tBuild the Docker Smartnode image and push it to Docker Hub'
    echo $'\t-x\tBuild the Docker POW Proxy image and push it to Docker Hub'
    echo $'\t-n\tBuild the Docker manifests (Smartnode and POW Proxy), and push them to Docker Hub'
    echo $'\t-r\tBuild the Docker Prune Provisioner image and push it to Docker Hub'
    echo $'\t-f\tBuild the Docker manifest for the Prune Provisioner and push it to Docker Hub'
    exit 0
}


# =================
# === Main Body ===
# =================

# Get CPU architecture
UNAME_VAL=$(uname -m)
ARCH=""
case $UNAME_VAL in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)       fail "CPU architecture not supported: $UNAME_VAL" ;;
esac

# Parse arguments
while getopts "acpmndxrfv:" FLAG; do
    case "$FLAG" in
        a) CLI=true PACKAGES=true DAEMON=true DOCKER=true MANIFEST=true PROXY=true ;;
        c) CLI=true ;;
        p) PACKAGES=true ;;
        m) DAEMON=true ;;
        d) DOCKER=true ;;
        x) PROXY=true ;;
        n) MANIFEST=true ;;
        r) PRUNE=true ;;
        f) PRUNE_MANIFEST=true ;;
        v) VERSION="$OPTARG" ;;
        *) usage ;;
    esac
done
if [ -z "$VERSION" ]; then
    usage
fi

# Cleanup old artifacts
rm -f ./$VERSION/*
mkdir -p ./$VERSION

# Build the artifacts
if [ "$CLI" = true ]; then
    build_cli
fi
if [ "$PACKAGES" = true ]; then
    build_install_packages
fi
if [ "$DAEMON" = true ]; then
    build_daemon
fi
if [ "$DOCKER" = true ]; then
    build_docker_smartnode
fi
if [ "$PROXY" = true ]; then
    build_docker_pow_proxy
fi
if [ "$MANIFEST" = true ]; then
    build_docker_manifest
fi
if [ "$PRUNE" = true ]; then
    build_docker_prune_provision
fi
if [ "$PRUNE_MANIFEST" = true ]; then
    build_docker_prune_provision_manifest
fi