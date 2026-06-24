#!/bin/bash

DOTFILES="/home/user1/dotfiles"

# Neovim
rm -rf "$HOME/.config/nvim"
ln -s "$DOTFILES/nvim" "$HOME/.config/nvim"
