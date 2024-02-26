# ISO generation

This repository explains how to build a custom ISO file for Zentyal 8.0. If you want to build a Zentyal 7.1 ISO, use the branch [7.1](https://github.com/zentyal/iso-generator/tree/7.1) instead.

## Requirements

The computer requirements to build an ISO are:

1. Around 5GB of available disk space.
2. The system packages installed:
    * wget
    * p7zip-full
    * debootstrap
    * gnupg
    * dpkg-dev
    * genisoimage

    You can install those packages by running the following command:

    ```sh
    sudo apt update
    sudo apt install \
        wget \
        p7zip-full \
        debootstrap \
        gnupg \
        dpkg-dev \
        genisoimage
    ```

## Generate the ISO

To generate a new ISO based on an [Ubuntu Server 22.04](https://releases.ubuntu.com/jammy/ubuntu-22.04.3-live-server-amd64.iso) live you must do the following:

1. Clone this repository:

    ```sh
    git clone https://github.com/zentyal/iso-generator.git
    ```

2. Change this directory:

    ```sh
    cd iso-generator
    ```

3. Create the variable file `autoinstall-vars.conf` from the template `autoinstall-vars.conf.template`

    ```sh
    cp autoinstall-vars.conf.template autoinstall-vars.conf
    ```

4. Do the necessary modifications to the variable file like the value of `BASE_DIR` variable.

5. Run the script that generates the ISO:

    ```sh
    ./autoinstall.sh
    ```

6. Test the ISO.
