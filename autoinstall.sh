#!/bin/bash

set -e

# Import variable file
test -r autoinstall-vars.conf || exit 1
. ./autoinstall-vars.conf

if [ ${GEN_DEBUG} == 'true' ]; then
   set -x    # Debug
fi


##
## Functions
##

function initial_tasks() {
   # This function ensures that the build is done from scratch

   # Remove an existing ISO
   if [ -f "${ISO_NAME}" ]; then
      rm ${ISO_NAME}*
   fi

   # Remove the ISO build directory
   if [ -d "${ISO_BUILD_DIR}" ]; then
      sudo rm -rf "${ISO_BUILD_DIR}"
   fi
}


function get_iso() {
   # This function gets the ISO that we are going to customize

   # Download the ISO if it is not present
   if [ ! -f ${UBUNTU_ISO_PATH} ]; then
      wget https://releases.ubuntu.com/focal/${UBUNTU_ISO_NAME} -P ${UBUNTU_ISO_PATH}
   fi

   # Create the directory where the ISO will be generated
   mkdir -p ${ISO_BUILD_DIR}

   # Unpack the Ubuntu ISO so we can proceed with the customization
   7z -y x ${UBUNTU_ISO_PATH} -o${ISO_BUILD_DIR}
}


function setup_boot() {
   # This function configures the GRUB

   cd ${BASE_DIR}/templates-boot/

   # Configure Grub and Isolinux
   cp template-boot.grub.cfg ${ISO_BUILD_DIR}/boot/grub/grub.cfg
   cp template-boot.loopback.cfg ${ISO_BUILD_DIR}/boot/grub/loopback.cfg
   cp template-boot.isolinux-zentyal.cfg ${ISO_BUILD_DIR}/isolinux/txt.cfg

   ## Initial endless boot
   sed -i -r 's/timeout\s+[0-9]+/timeout 0/g' ${ISO_BUILD_DIR}/isolinux/isolinux.cfg

   # Set the Zentyal version
   for file in /boot/grub/grub.cfg /boot/grub/loopback.cfg isolinux/txt.cfg; do
      sed -i "s/VERSION/$ZEN_VERSION-$ZEN_EDITION/g" ${ISO_BUILD_DIR}/${file}
   done

   # Remove unnecessary file
   rm -rf ${ISO_BUILD_DIR}/[BOOT]
}


function setup_image() {
   # This function changes the initial boot ISO image

   cd ${BASE_DIR}

   # Copy the Zentyal image for the initial grub menu
   cp images/splash.* ${ISO_BUILD_DIR}/isolinux/
   cd ${ISO_BUILD_DIR}/isolinux

   mkdir -v tmp
   cd tmp

   cat ../bootlogo | cpio --extract --make-directories --no-absolute-filenames

   # Copy the first initial boot image
   cp ${BASE_DIR}/images/splash.pcx .
   cp ${BASE_DIR}/images/initial-boot.pcx access.pcx

   # Avoid choosing initial language
   echo 'en' > lang

   find . | cpio -o > ../bootlogo
   cd ../

   if [ ${GEN_DEBUG} != 'true' ]; then
      rm -rf tmp
   fi
}


function setup_autoinstall() {
   # This function sets up Cloud-Init

   cd ${BASE_DIR}/templates-cloud_init/

   # Add the three required files
   for file in zentyal-delete-all zentyal-expert zentyal-expert-gui; do
      # Create the directory in the ISO
      mkdir ${ISO_BUILD_DIR}/${file}

      # Add the template
      cp template.user-data_${file} ${ISO_BUILD_DIR}/${file}/user-data

      # Create the required empty file
      touch ${ISO_BUILD_DIR}/${file}/meta-data
   done

   # Use a debugging template that installs Zentyal without interactive questions
   # cp ${BASE_DIR}/templates-cloud_init/template.user-data_developer ${ISO_BUILD_DIR}/zentyal-delete-all/user-data

   # Add the Zentyal directory that manages the post-installation
   mkdir ${ISO_BUILD_DIR}/zentyal-init
   cp ${BASE_DIR}/zentyal-init/* ${ISO_BUILD_DIR}/zentyal-init/
}


function setup_keys() {
   # This function downloads the repository keys

   # Zentyal
   for i in ${ZEN_KEYS_URL}; do
      wget -q ${i} -P ${ISO_BUILD_DIR}/zentyal-init/
   done

   # Suricata (IPS module)
   gpg --keyserver keyserver.ubuntu.com --recv-keys ${IPS_KEY_ID}
   gpg --export ${IPS_KEY_ID} > ${ISO_BUILD_DIR}/zentyal-init/suricata.gpg
   gpg --batch --yes --delete-keys ${IPS_KEY_ID}
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
deb http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe
EOF

   # Update the repositories index and installing a required package for HTTPS repositories
   sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} apt update
   sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} apt install -y ca-certificates

   # Add Zentyal and Suricata repositories
   echo "deb [signed-by=/etc/apt/trusted.gpg.d/${IPS_KEY_NAME}] ${IPS_REPO_URL} ${IPS_REPO_DIST} ${IPS_REPO_COMPONENTS}" | sudo tee -a ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/sources.list
   echo "deb [signed-by=/etc/apt/trusted.gpg.d/${ZEN_KEY_NAME}] ${ZEN_REPO_URL} ${ZEN_VERSION} ${ZEN_REPO_COMPONENTS}" | sudo tee -a ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/sources.list

   # Add repositories keys
   sudo cp ${ISO_BUILD_DIR}/zentyal-init/${ZEN_KEY_NAME} ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/trusted.gpg.d/
   sudo cp ${ISO_BUILD_DIR}/zentyal-init/${IPS_KEY_NAME} ${CHROOT_PKG_OFFLINE_BUILD_DIR}/etc/apt/trusted.gpg.d/

   # Set extra configuration for Zentyal commercial
   if [ ${ZEN_EDITION} == 'commercial' ]; then
      bash zentyal-commercial.sh
      PKG_TO_DOWNLOAD="${PKG_TO_DOWNLOAD} ${PKG_TO_DOWNLOAD_COMMERCIAL}"
   fi

   # Update the repositories index and revmove Netplan
   sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} apt update
   sudo chroot ${CHROOT_PKG_OFFLINE_BUILD_DIR} apt purge -y netplan.io

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
      $ISO_BUILD_DIR/zentyal-init/zentyal-repositories.sh

   # Suricata (IPS)
   sed -i \
      -e "s#IPS_KEY_NAME#$IPS_KEY_NAME#g" \
      -e "s#IPS_REPO_URL#$IPS_REPO_URL#" \
      -e "s#IPS_REPO_DIST#$IPS_REPO_DIST#" \
      -e "s#IPS_REPO_COMPONENTS#$IPS_REPO_COMPONENTS#" \
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
   find '!' -name "md5sum.txt" '!' -path "./isolinux/*" -follow -type f -exec "$(which md5sum)" {} \; > md5sum.txt

   cd ${BASE_DIR}

   genisoimage \
   -D \
   -r \
   -V "${VOL_NAME}" \
   -cache-inodes \
   -J \
   -l \
   -input-charset utf-8 \
   -joliet-long \
      -b isolinux/isolinux.bin \
      -c isolinux/boot.cat \
   -no-emul-boot \
   -boot-load-size 4 \
   -boot-info-table \
   -eltorito-alt-boot \
   -e boot/grub/efi.img \
   -no-emul-boot \
   -o ${ISO_NAME} \
   ${ISO_BUILD_DIR}

   # Generate the MD5 file from the ISO
   md5sum ${ISO_NAME} > ${ISO_NAME}.md5

   if [ ${GEN_DEBUG} != 'true' ]; then
      sudo rm -rf ${ISO_BUILD_DIR}
   fi
}


##
## Running the functions
##

# 1 - From scratch
initial_tasks

# 2 - Get and unpack the ISO
get_iso

# 3 - Configure the grub
setup_boot
setup_image

# 4 - Set up Cloud-init
setup_autoinstall

# 5 - Fetch the repository keys
setup_keys

# 6 - Set up the offline installation
if [ "${FETCH_OFFLINE_PACKAGES}" == 'true' ]; then
   get_offline_packages
fi

# 7. Set the values of the scripts
set_scrips_vars

# 8 - Generate
iso_generation

echo "The ISO was successfully generated in ${BASE_DIR}/${ISO_NAME}"
