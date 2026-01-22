#!/bin/bash

set -e

##
# Global variables
##

ZENTYAL_INIT_DIR='/var/zentyal-init'
ZENTYAL_LOCAL_REPO='/var/tmp/zentyal-packages'
ZENTYAL_TAR_PKG_NAME='zentyal-packages-offline.tar.gz'
REPO_CACHE_DIR='/var/cache/apt/archives'
ZENTYAL_REPOSITORY_NAME='zentyal.sources'
ZENTYAL_REPOSITORY_TMP_NAME='zentyal-temporal.sources'
BASE_REPO_KEY_DIR='/etc/apt/trusted.gpg.d'

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
    echo "deb [trusted=yes] file://${ZENTYAL_LOCAL_REPO}/ ./" > /etc/apt/sources.list.d/${ZENTYAL_REPOSITORY_TMP_NAME}

cat > /etc/apt/sources.list.d/${ZENTYAL_REPOSITORY_TMP_NAME} <<EOF
# Temporal Zentyal repository
Types: deb
URIs: file:${ZENTYAL_LOCAL_REPO}
Suites: ./
Trusted: yes
EOF

    # Link .deb files to Apt cache to avoid downloading them
    cd ${REPO_CACHE_DIR}
    for pkg in $ZENTYAL_LOCAL_REPO/*.deb; do
        ln -s ${pkg} .
    done

    # Temporarily move the original source.list
    mv /etc/apt/sources.list.d/ubuntu.sources /tmp

    # Update the package database with only the local repository
    apt update

    # Restore the original sources.list
    mv /tmp/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources

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


function set_repository_zentyal() {
    # This function adds the Zentyal repository

    echo -e "\n${YELLOW} Running function set_repository_zentyal...${NC}"

    if [ -f ${ZENTYAL_INIT_DIR}/commercial-edition ]; then
        mkdir -vp 0755 /var/lib/zentyal/
        echo 'ACTIVATION-REQUIRED' > /var/lib/zentyal/.license
    fi

cat > /etc/apt/sources.list.d/${ZENTYAL_REPOSITORY_NAME} <<EOF
# Zentyal repository
Types: deb
URIs: ZEN_REPO_URL
Suites: ZEN_VERSION
Components: ZEN_REPO_COMPONENTS
Signed-By: ${BASE_REPO_KEY_DIR}/ZEN_REPO_KEY_NAME

EOF

    echo -e "${GREEN}...OK${NC}";echo
}


function set_repository_firefox() {
    # This function adds the Firefox repository for the zenbuntu-desktop module

    echo -e "\n${YELLOW} Running function set_repository_firefox...${NC}"

cat >> /etc/apt/sources.list.d/${ZENTYAL_REPOSITORY_NAME} <<EOF
# Firefox repository
Types: deb
URIs: FIREFOX_REPO_URL
Suites: FIREFOX_REPO_DIST
Components: FIREFOX_REPO_COMPONENTS
Signed-By: ${BASE_REPO_KEY_DIR}/FIREFOX_REPO_KEY_NAME

EOF

    cp ${ZENTYAL_INIT_DIR}/FIREFOX_REPO_PREFERENCE_NAME /etc/apt/preferences.d/FIREFOX_REPO_PREFERENCE_NAME

    echo -e "${GREEN}...OK${NC}";echo
}


function set_repository_docker() {
    # This function adds the Docker repository for the Docker module

    echo -e "\n${YELLOW} Running function set_repository_docker...${NC}"

cat >> /etc/apt/sources.list.d/${ZENTYAL_REPOSITORY_NAME} <<EOF
# Docker repository
Types: deb
URIs: DOCKER_REPO_URL
Suites: DOCKER_REPO_DIST
Components: DOCKER_REPO_COMPONENTS
Signed-By: ${BASE_REPO_KEY_DIR}/DOCKER_REPO_KEY_NAME

EOF

    echo -e "${GREEN}...OK${NC}";echo
}


##
# Running the functions
##

echo -e "${GREEN}Running script ${0} ...${NC}"

set_local_repository
add_keys
set_repository_zentyal
set_repository_firefox
set_repository_docker

echo -e "${GREEN} Running script ${0} completed.${NC}"
