#!/bin/bash
DOTFILES="$(cd "$(dirname "$0")" && pwd)"
ln -sf "$DOTFILES/hypr" "$HOME/.config/hypr"
ln -sf "$DOTFILES/waybar" "$HOME/.config/waybar"
ln -sf "$DOTFILES/rofi" "$HOME/.config/rofi"
