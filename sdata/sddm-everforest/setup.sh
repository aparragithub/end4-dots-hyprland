#!/bin/bash
# Setup everforest SDDM theme based on Sugar Candy
# Usage: sudo ./setup.sh [optional-background-image.jpg]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUGAR="/usr/share/sddm/themes/Sugar-Candy"
EVER="/usr/share/sddm/themes/everforest"
BG_IMAGE="${1:-$SCRIPT_DIR/Backgrounds/custom-bg.jpg}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Ejecuta con sudo"
    exit 1
fi

if [ ! -d "$SUGAR" ]; then
    echo "ERROR: Sugar Candy no esta instalado. Instala sddm-theme-sugar-candy-git primero."
    exit 1
fi

echo "=== Creando tema everforest desde Sugar Candy ==="

# 1. Remove old version if exists
if [ -d "$EVER" ]; then
    echo "Borrando everforest anterior..."
    rm -rf "$EVER"
fi

# 2. Copy fresh from Sugar Candy
echo "Copiando desde Sugar Candy..."
cp -r "$SUGAR" "$EVER"

# 3. Copy background image
if [ -f "$BG_IMAGE" ]; then
    echo "Copiando fondo: $BG_IMAGE"
    cp "$BG_IMAGE" "$EVER/Backgrounds/custom-bg.jpg"
else
    echo "AVISO: Fondo no encontrado en $BG_IMAGE"
fi

# 4. Apply custom configs
echo "Aplicando theme.conf y metadata..."
cp "$SCRIPT_DIR/theme.conf" "$EVER/theme.conf"
cp "$SCRIPT_DIR/metadata.desktop" "$EVER/metadata.desktop"

if [ -f "$SCRIPT_DIR/Assets/User.svgz" ]; then
    echo "Aplicando icono de usuario personalizado..."
    cp "$SCRIPT_DIR/Assets/User.svgz" "$EVER/Assets/User.svgz"
fi

# 5. Set as active theme
echo "Activando tema everforest..."
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-theme.conf << 'SDDMCONF'
[Theme]
Current=everforest
SDDMCONF

echo "=== Tema everforest instalado ==="
echo "Proba con: sddm-greeter --test-mode --theme /usr/share/sddm/themes/everforest"
