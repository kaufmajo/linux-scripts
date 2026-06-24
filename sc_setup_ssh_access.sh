#!/bin/bash

# ---------------------------------------------------------------
#
# https://code.visualstudio.com/docs/remote/troubleshooting#_configuring-key-based-authentication
#
# cd /home/user1/.ssh
#
# ssh-keygen -t ed25519 -b 4096
#
# chmod 400 ~/.ssh/id_ed25519
# --------------------------------------------------------------

# --------------------------------------------------------------
# Init

___hosts=("user1@10.99.99.20" "user1@10.99.99.30" "user1@10.99.99.40" "sysadmin@172.23.3.45" "joachim@172.23.3.45")
___names=("debian-01___hyperv" "debian-02___hyperv" "debian-04___hyperv" "dockerHubDev___proxmox" "dockerHubDev___proxmox")

# --------------------------------------------------------------
# Process

for i in ${!___hosts[@]}; do

    read -p "Are you sure you want to proceed [y/n] -> Setup ssh access for '"${___hosts[$i]}"/"${___names[$i]}"': " -r

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        
        export USER_AT_HOST="${___hosts[$i]}"
        export PUBKEYPATH="$HOME/.ssh/id_ed25519.pub"
        ssh-copy-id -i "$PUBKEYPATH" "$USER_AT_HOST"
        
        echo ""
    fi

done
