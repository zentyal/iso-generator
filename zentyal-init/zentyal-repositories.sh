#!/bin/bash

set -e

##
# Global variables
##

ZENTYAL_INIT_DIR='/var/zentyal-init'
ZENTYAL_LOCAL_REPO='/var/tmp/zentyal-packages'
ZENTYAL_TAR_PKG_NAME='zentyal-packages-offline.tar.gz'
REPO_CACHE_DIR='/var/cache/apt/archives'

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'


##
# Functions
##

function set_local_repository() {
    # This function configures a local repository so Zentyal can be installed
    # without Internet in the FIRST BOOT

    echo -e "\n${YELLOW} Running function set_local_repository...${NC}"

    # Add the local repository
    echo "deb [trusted=yes] file://${ZENTYAL_LOCAL_REPO}/ ./" > /etc/apt/sources.list.d/zentyal-temporal.list

    # Link .deb files to Apt cache to avoid downloading them
    cd ${REPO_CACHE_DIR}
    for pkg in $ZENTYAL_LOCAL_REPO/*.deb; do
        ln -s ${pkg} .
    done

    # Temporarily move the original source.list
    mv /etc/apt/sources.list /etc/apt/sources.list.disabled

    # Update the package database with only the local repository
    apt update

    # Restore the original sources.list
    mv /etc/apt/sources.list.disabled /etc/apt/sources.list

    # Remove the package compress file to reduce disk space
    if [ -f ${ZENTYAL_INIT_DIR}/${ZENTYAL_TAR_PKG_NAME} ]
    then
        rm -f ${ZENTYAL_INIT_DIR}/${ZENTYAL_TAR_PKG_NAME}
    fi

    echo -e "${GREEN}...OK${NC}";echo
}


function add_keys() {
    # This function adds the required repository keys

    echo -e "\n${YELLOW} Running function add_keyss...${NC}"

    cp ${ZENTYAL_INIT_DIR}/*.{asc,gpg} /etc/apt/trusted.gpg.d/

    echo -e "${GREEN}...OK${NC}";echo
}


function set_repositories() {
    # This function adds the additional repositories, what are: Zentyal, Docker and Firefox

    echo -e "\n${YELLOW} Running function set_repositories...${NC}"

    if [ -f ${ZENTYAL_INIT_DIR}/commercial-edition ]; then
        mkdir -vp 0755 /var/lib/zentyal/
        echo 'ACTIVATION-REQUIRED' > /var/lib/zentyal/.license
    else
        echo 'deb [signed-by=/etc/apt/trusted.gpg.d/ZEN_REPO_KEY_NAME] ZEN_REPO_URL ZEN_VERSION ZEN_REPO_COMPONENTS' >> /etc/apt/sources.list.d/zentyal.list
    fi

    echo "deb [arch=DOCKER_REPO_ARCH signed-by=/etc/apt/trusted.gpg.d/DOCKER_REPO_KEY_NAME] DOCKER_REPO_URL DOCKER_REPO_DIST DOCKER_REPO_COMPONENTS" | tee -a ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/sources.list.d/docker.list
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/FIREFOX_REPO_KEY_NAME] FIREFOX_REPO_URL FIREFOX_REPO_DIST FIREFOX_REPO_COMPONENTS" | tee -a ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/sources.list.d/mozilla.list
    cp ${ZENTYAL_INIT_DIR}/FIREFOX_REPO_PREFERENCE_NAME /etc/apt/preferences.d/FIREFOX_REPO_PREFERENCE_NAME

    echo -e "${GREEN}...OK${NC}";echo
}


##
# Running the functions
##

echo -e "${GREEN}Running script ${0} ...${NC}"

set_local_repository
add_keys
set_repositories

echo -e "${GREEN} Running script ${0} completed.${NC}"
