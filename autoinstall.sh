#!/bin/bash

set -e

# Import variable file
test -r autoinstall-vars.conf || exit 1
. ./autoinstall-vars.conf

if [ ${GEN_DEBUG} == 'true' ]; then
   set -ex
else
   set -e
fi


##
## Functions
##

function initial_tasks() {
   # This function ensures that the build is done from scratch

   # Remove an existing ISO
   if [ -f "${ISO_NAME}" ]; then
      rm -f ${ISO_NAME}*
   fi

   # Remove the ISO build directory
   if [ -d "${ISO_BUILD_DIR}" ]; then
      sudo rm -rf "${ISO_BUILD_DIR}"
   fi

   # Remove the temporal directory
   if [ -d "${TMP_DIR}" ]; then
      sudo rm -rf "${TMP_DIR}"
   fi
}


function get_iso() {
   # This function gets the ISO that we are going to customize

   # Download the ISO if it is not present
   if [ ! -f ${UBUNTU_ISO_PATH} ]; then
      wget https://releases.ubuntu.com/${UBUNTU_DIST}/${UBUNTU_ISO_NAME} -P ${UBUNTU_ISO_PATH}
   fi

   # Create the directory where the ISO will be generated
   mkdir -p ${ISO_BUILD_DIR}

   # Unpack the Ubuntu ISO so we can proceed with the customization
   7z -y x ${UBUNTU_ISO_PATH} -o${ISO_BUILD_DIR}
}


function setup_boot() {
   # This function configures the GRUB

   # Create the temporal directory
   mkdir ${TMP_DIR}

   cd ${ISO_BUILD_DIR}

   ## Move MBR and GPT img files to a temporal location
   mv ${ISO_BUILD_DIR}/\[BOOT\]/*.img ${TMP_DIR}/
   rm -rf ${ISO_BUILD_DIR}/\[BOOT\]

   # Copy Grub2 configuration file
   cp ${BASE_DIR}/templates-boot/template-boot.grub.cfg boot/grub/grub.cfg
}


function setup_theme() {
   # This function adds a theme to the grub menu

   cd ${BASE_DIR}

   # Create the theme directory
   mkdir -v ${ISO_BUILD_DIR}/boot/grub/themes/

   # Copy the grub theme
   cp -vr ${THEME}/* ${ISO_BUILD_DIR}/boot/grub/themes/
}


function setup_autoinstall() {
   # This function sets up Cloud-Init

   cd ${BASE_DIR}/templates-cloud_init/

   # Add the three required files for each grub menu
   for file in zentyal-delete-all zentyal-expert zentyal-expert-gui; do
      # Create the directory in the ISO
      mkdir ${ISO_BUILD_DIR}/${file}

      # Add the template
      cp template.user-data_${file} ${ISO_BUILD_DIR}/${file}/user-data

      # Create the required empty file
      touch ${ISO_BUILD_DIR}/${file}/meta-data
   done

   # Add the Zentyal directory that manages the post-installation
   mkdir ${ISO_BUILD_DIR}/zentyal-init
   cp ${BASE_DIR}/zentyal-init/* ${ISO_BUILD_DIR}/zentyal-init/
}


function setup_key() {
   # This function downloads the repository keys

   # Zentyal
   for i in ${ZEN_KEYS_URL}; do
      wget -q ${i} -P ${ISO_BUILD_DIR}/zentyal-init/
   done
}


function get_offline_packages() {
   # This function fetches all the necessary packages for the offline installation

   cd ${BASE_DIR}

   # Start from scratch
   if [ -d ${CHROOT_PKG_OFFLINE_BASE} ]; then
      sudo rm -rf ${CHROOT_PKG_OFFLINE_BASE}
   fi

   # Create the needed directories
   mkdir -p ${CHROOT_PKG_OFFLINE_BUILD_DIR} ${CHROOT_PKG_OFFLINE_RESULT_DIR}

   # Create a virtual system based on Ubuntu
   sudo debootstrap --arch=${ZEN_ARCH} --include=gnupg ${UBUNTU_DIST} ${CHROOT_PKG_OFFLINE_BUILD_DIR}

   # Add Ubuntu repository
   cat <<EOF | sudo tee ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu ${UBUNTU_DIST} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${UBUNTU_DIST}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${UBUNTU_DIST}-security main restricted universe
EOF

   # Update the repositories index and installing a required package for HTTPS repositories
   sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} apt update
   sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} apt install -y ca-certificates software-properties-common

   # Add Zentyal and Suricata repositories
   # echo "deb [signed-by=/etc/apt/trusted.gpg.d/${ZEN_KEY_NAME}] ${ZEN_REPO_URL} ${ZEN_VERSION} ${ZEN_REPO_COMPONENTS}" | sudo tee -a ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/sources.list
   echo "deb [trusted=yes] ${ZEN_REPO_URL} ${ZEN_VERSION} ${ZEN_REPO_COMPONENTS}" | sudo tee -a ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/sources.list
   sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} add-apt-repository -y ${IPS_PPA}

   # Add Zentyal repository key
   sudo cp ${ISO_BUILD_DIR}/zentyal-init/${ZEN_KEY_NAME} ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/trusted.gpg.d/

   # Set extra configuration for Zentyal commercial
   if [ ${ZEN_EDITION} == 'commercial' ]; then
      bash zentyal-commercial.sh
      PKG_TO_DOWNLOAD="${PKG_TO_DOWNLOAD} ${PKG_TO_DOWNLOAD_COMMERCIAL}"
   fi

   # Update the repositories index
   sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} apt update

   # Download the packages and
   echo ${PKG_TO_DOWNLOAD} | \
      xargs sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} \
                  apt install \
                     --download-only \
                     --no-install-recommends \
                     --allow-unauthenticated \
                     --yes

   # Change to the final directory where the packages will be moved and compressed
   cd ${CHROOT_PKG_OFFLINE_RESULT_DIR}

   # Moving the downloaded packages
   sudo find ${CHROOT_PKG_OFFLINE_BUILD_DIR}/var/cache/apt/archives/ \
         -type f \
         -name '*.deb' \
         -exec mv {} . \;

   # Create the repository index
   dpkg-scanpackages -m . | gzip -c > Packages.gz

   # Compress the packages
   tar cfz ${ISO_BUILD_DIR}/zentyal-init/${PKG_FILE_NAME} ./

   # Clean the local environment
   if [ ${GEN_DEBUG} != 'true' ]; then
      sudo rm -rf ${CHROOT_PKG_OFFLINE_BASE}
   fi
}


function set_scrips_vars() {
   # This function sets the value of the scripts added to the ISO

   # Set repositories
   # Zentyal
   sed -i \
      -e "s#ZEN_KEY_NAME#$ZEN_KEY_NAME#g" \
      -e "s#ZEN_REPO_URL#$ZEN_REPO_URL#" \
      -e "s#ZEN_REPO_VERSION#$ZEN_VERSION#" \
      -e "s#ZEN_REPO_COMPONENTS#$ZEN_REPO_COMPONENTS#" \
      -e "s#IPS_PPA#$IPS_PPA#" \
      $ISO_BUILD_DIR/zentyal-init/zentyal-repositories.sh

   # Set Ubuntu version
   sed -i "s/UBUNTU-VERSION/$UBUNTU_VERSION/" $ISO_BUILD_DIR/zentyal-init/zentyal-install.sh

   # Set a commercial edition file
   if [ ${ZEN_EDITION} == 'commercial' ]; then
      touch ${ISO_BUILD_DIR}/zentyal-init/commercial-edition
   fi
}


function iso_generation() {
   # This function generates the ISO

   cd ${ISO_BUILD_DIR}

   sudo xorriso -as mkisofs -r \
   -V "Zentyal ${ZEN_VERSION}" \
   -o ../${ISO_NAME} \
   --grub2-mbr ${TMP_DIR}/1-Boot-NoEmul.img \
   -partition_offset 16 \
   --mbr-force-bootable \
   -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b ${TMP_DIR}/2-Boot-NoEmul.img \
   -appended_part_as_gpt \
   -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
   -c '/boot.catalog' \
   -b '/boot/grub/i386-pc/eltorito.img' \
      -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
   -eltorito-alt-boot \
   -e '--interval:appended_partition_2:::' \
   -no-emul-boot \
   .

   # Generate the MD5 file from the ISO
   md5sum ../${ISO_NAME} > ../${ISO_NAME}.md5
}

function clean() {
   # This functions removes the temporal files that were created

      sudo rm -rf ${ISO_BUILD_DIR}
      sudo rm -rf ${CHROOT_PKG_OFFLINE_BASE}
}


##
## Running the functions
##

# 1 - Prepare the environment
initial_tasks

# 2 - Download and unpack the ISO
get_iso

# 3 - Configure Grub2
setup_boot
setup_theme

# 4 - Set up Cloud-init
setup_autoinstall

# 5 - Fetch the repository keys
setup_key

# 6 - Set up the offline installation
if [ "${FETCH_OFFLINE_PACKAGES}" == 'true' ]; then
   get_offline_packages
fi

# 7. Set the values of the scripts
set_scrips_vars

# 8 - Generate the ISO file
iso_generation

# 9 - Clean the environment
if [ ${GEN_DEBUG} != 'true' ]; then clean; fi

echo "The ISO was successfully generated in ${BASE_DIR}/${ISO_NAME}"
