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


##
# Functions
##

function disable_whoopsie()
{
    # This functions removes an error

    local conf_file='/usr/share/dbus-1/system.d/org.freedesktop.NetworkManager.conf'
    local patron_start='<policy user="whoopsie">'
    local patron_end='</policy>'

    # Check if the file exists
    if [ ! -f "$conf_file" ]; then return; fi

    # Check if the user exists
    if grep -q 'whoopsie' /etc/passwd; then return; fi

    # Check if the patron matches
    if ! grep -q "$patron_start" "$conf_file"; then return; fi

    # Remove the policy and notify to the service
    sudo sed -i "\#$patron_start#,\#$patron_end#d" "$conf_file"
    systemctl restart dbus
}


function disable_power()
{
    # Esta función elimina un error

    local conf_file='/etc/dbus-1/system.d/org.freedesktop.thermald.conf'
    local patron_start='<policy group="power">'
    local patron_end='</policy>'

    # Check if the file exists
    if [ ! -f "$conf_file" ]; then return; fi

    # Check if the user exists
    if grep -q 'power' /etc/group; then return; fi

    # Check if the patron matches
    if ! grep -q "$patron_start" "$conf_file"; then return; fi

    # Remove the policy and notify to the service
    sudo sed -i "\#$patron_start#,\#$patron_end#d" "$conf_file"
    systemctl restart dbus
}


function disable_cloud-init()
{
    # This function disables Cloud-init
    touch /etc/cloud/cloud-init.disabled
}


function run_functions()
{
    # This function runs the functions
    disable_whoopsie
    disable_power
    disable_cloud-init
}


##
# Running the functions
##

run_functions
