#!/bin/bash
set -e

# Setup script for Tsundoku
INSTALL_DIR="${1:-$HOME/Documents/Tsundoku}"
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Placeholder: Download latest release
echo "Downloading release..."
# curl -L https://github.com/mai-kun/tsundoku/releases/latest/download/tsundoku-linux-x64.zip -o "$INSTALL_DIR/tsundoku.zip"
# unzip "$INSTALL_DIR/tsundoku.zip" -d "$INSTALL_DIR"
# chmod +x "$INSTALL_DIR/Tsundoku"

# Storage mode
read -p "Select storage mode (default/portable/custom): " STORAGE_MODE
STORAGE_MODE=${STORAGE_MODE:-default}

cat > "$INSTALL_DIR/storage.json" <<CONF
{
  "mode": "$STORAGE_MODE"
}
CONF

# Desktop Entry
DESKTOP_FILE="$HOME/.local/share/applications/tsundoku.desktop"
cat > "$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Name=Tsundoku
Exec=$INSTALL_DIR/Tsundoku
Type=Application
Categories=Utility;
DESKTOP

echo "Installation complete."
