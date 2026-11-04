#!/bin/bash

# --------------------------------------------------------------
# Init

packages=("man-db" "grep" "rsync" "wget" "curl" "fuse" "build-essential" "python3" "python3-pip" "python3-venv" "shellcheck")

# --------------------------------------------------------------
# Check if root

if [ "$(id -u)" -ne 0 ]; then
	echo Please run this script as root or using sudo.
	exit 1
fi

# --------------------------------------------------------------
# Update apt package lists

apt-get update # To get the latest package lists

# --------------------------------------------------------------
# Install packages

for package in "${packages[@]}"; do

	if dpkg -s "$package" &>/dev/null; then
		echo ''
		echo "$package is already installed"
		echo '-----------------'
	else
		echo ''
		echo "$package is trying to get installed"
		echo '-----------------'

		apt-get install "$package" -y
	fi

	echo ""

done

# --------------------------------------------------------------
