#!/bin/sh

curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage
chmod u+x nvim-linux-x86_64.appimage

# To expose nvim globally:

sudo mkdir -p /opt/nvim
sudo mv nvim-linux-x86_64.appimage /opt/nvim/nvim
