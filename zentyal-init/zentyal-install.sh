#!/usr/bin/env bash

set -e

##
# Global variables
##

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD=$(tput bold)
NORM=$(tput sgr0)
UBUNTU_VER='UBUNTU-VERSION'
BOOT_SPACE='51200'
SYSTEM_SPACE='358400'
INS_USER=$(id -nu 1000)

##
# Functions
##

function check_ubuntu
{
  echo -e "\n${GREEN} - Checking Ubuntu version...${NC}"

  if ! lsb_release -d | egrep -q "${UBUNTU_VER}.?[0-9]? LTS$"
    then
      echo -e "${RED}  The version that you are using isn't valid. Zentyal requires ${UBUNTU_VER}.x LTS ${NC}"
      exit 1
  fi

  echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo
}


function check_broken_packages
{
  echo -e "${GREEN} - Checking for broken packages...${NC}"

  if [[ $(dpkg -l | egrep -v '^ii|rc' | awk '{if(NR>5)print}' | wc -l) -gt 0 ]]
    then
      echo -e "${RED}  You have broken packages, trying to repair.${NC}"

      for i in {1..10}; do DEBIAN_FRONTEND=noninteractive dpkg --configure -a; done

      if [[ $(dpkg -l | egrep -v '^ii|rc' | awk '{if(NR>5)print}' | wc -l) -gt 0 ]]
        then
          echo -e "${RED}  Couln't fix the broken packages.${NC}"
          exit 1
      fi

      echo -e "${GREEN} Broken packages fixed. ${NORM}";echo
  fi

  echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo
}


function check_disk_space
{
  echo -e "${GREEN} - Checking for available disk space...${NC}"

  if [ $(df /boot | tail -1 | awk '{print $4}') -lt ${BOOT_SPACE} ];
    then
      echo -e "${RED}  Upgrade cannot be performed due to low disk space (less than 50MB available on /boot)${NC}"
      exit 1
  fi

  for partition in / /var
    do
      if [ $(df ${partition} | tail -1 | awk '{print $4}') -lt ${SYSTEM_SPACE} ];
        then
          echo -e "${RED}  Upgrade cannot be performed due to low partition space (less than 350MB available on '${partition}')${NC}"
          exit 1
      fi
    done

  echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo
}


function check_webadmin_port
{
  echo -e "${GREEN} - Checking Webadmin 8443/tcp port...${NC}"

  if ss -tunpl | grep -q '8443'
    then
      echo -e "${RED}  The port 8443/tcp is already in use.${NC}"
      exit 1
  fi

  echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo
}


function check_connection
{
  local CHECK_DOMAIN='google.es'

  echo -e "${GREEN} - Checking the Internet connection...${NC}"

  if ! ping -c4 -W 15 -q -c 5 ${CHECK_DOMAIN} > /dev/null
    then
      echo -e "${RED}  There are issues with the Internet resolution.${NC}"
    else
      apt update
  fi

  echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo
}


function check_requirements
{
  check_ubuntu
  check_broken_packages
  check_disk_space
  check_webadmin_port
  check_connection
}


function zentyal_gui
{
  echo -e "${GREEN} - Installing the graphical environment...${NC}\n"

  echo 'lxdm shared/default-x-display-manager select lxdm' | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${ZEN_GUI}

  if [[ ! -f /etc/X11/default-display-manager ]]
    then
      ## For Ubuntu Server
      echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo
      continue
  fi

  CUR_GUI=$(cat /etc/X11/default-display-manager | xargs basename)

  case ${CUR_GUI} in
    gdm3) ## Ubuntu Desktop (Gnome)
      echo 'gdm3 shared/default-x-display-manager select lxdm' | debconf-set-selections
      DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --force gdm3
      systemctl disable gdm3 lxdm
      which lxdm > /etc/X11/default-display-manager
    ;;
    sddm) ## Lubuntu and Kubuntu
      echo 'sddm shared/default-x-display-manager select lxdm' | debconf-set-selections
      DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --force sddm
      systemctl disable sddm lxdm
      which lxdm > /etc/X11/default-display-manager
    ;;
    lightdm) ## Xubuntu
      echo 'lightdm shared/default-x-display-manager select lxdm' | debconf-set-selections
      DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --force lightdm
      systemctl disable lightdm lxdm
      which lxdm > /etc/X11/default-display-manager
    ;;
  esac

  echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo

  echo -e "${GREEN} - Configuring the graphical environment...${NC}\n"

  /usr/share/zenbuntu-desktop/x11-setup >> /var/tmp/zentyal-installer.log 2>&1
  systemctl enable --now zentyal.lxdm

  echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo
}


function zentyal_installation
{
  echo -e "${GREEN} - Installing Zentyal...${NC}\n"

  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends zentyal zenbuntu-core

  touch /var/lib/zentyal/.commercial-edition
  touch /var/lib/zentyal/.license

  if [[ -n ${ZEN_GUI} ]]
    then
      zentyal_gui
    else
      echo -e "${GREEN}${BOLD}...OK${NC}${NORM}";echo

      echo -e "\n${GREEN}${BOLD}Installation complete, you can access the Zentyal Web Interface at:

        * https://<zentyal-ip-address>:8443/

      ${NC}${NORM}"
  fi

  ## Set keyboard layout temporarily
  sleep 15
  KEYMAP=$(localectl | grep 'Layout' | awk '{print $3}')
  su -c "DISPLAY=:0 setxkbmap $KEYMAP" ${INS_USER}
}


##
# Checks
##


if [[ ${EUID} -ne 0 ]]
  then
    echo -e "${RED}  The script must be run with 'sudo' rights.${NC}"
    exit 1
fi


ZEN_GUI=${1}

if [[ ${ZEN_GUI^} == 'Y' ]]
  then
    ZEN_GUI='zenbuntu-desktop'
  else
    ZEN_GUI=''
fi

##
# Running the functions
##

check_requirements
zentyal_installation


###
# Final commands
###

# Disable cloud-init
touch /etc/cloud/cloud-init.disabled
