#!/bin/bash
set -euo pipefail

STOCK_REPO="OpenRepeater/openrepeater"
STOCK_TAG="2.1.3"
WEBROOT="/var/www/openrepeater"

echo "Restoring official OpenRepeater 2.1.3..."

if [ "$EUID" -ne 0 ]; then
    echo "Run this script as root."
    exit 1
fi

for cmd in curl tar php; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing required command: $cmd"
        exit 1
    }
done

if [ ! -d "$WEBROOT" ]; then
    echo "OpenRepeater installation not found."
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading official OpenRepeater source..."

curl -fL \
    "https://codeload.github.com/$STOCK_REPO/tar.gz/refs/tags/$STOCK_TAG" \
    -o "$TMPDIR/stock.tar.gz"

tar -xzf "$TMPDIR/stock.tar.gz" -C "$TMPDIR"

SRC=$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -type d -print -quit)

if [ ! -f "$SRC/ports.php" ] ||
   [ ! -f "$SRC/functions/svxlink_update.php" ]; then
    echo "Official source verification failed."
    exit 1
fi

echo "Checking PHP syntax..."

find "$SRC" -type f -name '*.php' -print0 |
while IFS= read -r -d '' file; do
    php -l "$file" >/dev/null
done

echo "Backing up current web application..."

BACKUP="/root/openrepeater-before-stock-$(date +%Y%m%d-%H%M%S).tar.gz"

(
    cd "$WEBROOT"
    tar -czf "$BACKUP" \
        functions includes modules theme wizard ./*.php
)

echo "Installing official application files..."

for dir in functions includes modules theme wizard; do
    mkdir -p "$WEBROOT/$dir"
    cp -a "$SRC/$dir/." "$WEBROOT/$dir/"
done

cp -a "$SRC"/*.php "$WEBROOT/"

echo "Setting permissions..."

chown -R www-data:www-data \
    "$WEBROOT/functions" \
    "$WEBROOT/includes" \
    "$WEBROOT/modules" \
    "$WEBROOT/theme" \
    "$WEBROOT/wizard"

chown www-data:www-data "$WEBROOT"/*.php

echo "Restarting PHP-FPM..."

PHP_UNIT=$(systemctl list-units \
    --type=service --state=running --no-legend 'php*-fpm.service' |
    awk 'NR==1 {print $1}')

if [ -n "$PHP_UNIT" ]; then
    systemctl restart "$PHP_UNIT"
else
    echo "Warning: PHP-FPM service not found."
fi

echo "===================================="
echo "Official OpenRepeater 2.1.3 restored!"
echo "Backup saved at: $BACKUP"
echo "===================================="
