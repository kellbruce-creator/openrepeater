#!/bin/bash
set -euo pipefail

REPO="kellbruce-creator/openrepeater"
BRANCH="2.1.3"
WEBROOT="/var/www/openrepeater"

echo "Installing Kell Bruce's OpenRepeater updates..."

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

for cmd in curl tar php; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing required command: $cmd"
        exit 1
    }
done

if [ ! -d "$WEBROOT" ]; then
    echo "OpenRepeater installation not found at $WEBROOT."
    echo "Install the standard OpenRepeater image first."
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fL \
    "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" \
    -o "$TMPDIR/source.tar.gz"

tar -xzf "$TMPDIR/source.tar.gz" -C "$TMPDIR"

SRC="$TMPDIR/openrepeater-$BRANCH"

if [ ! -d "$SRC" ]; then
    echo "Could not find downloaded source directory."
    exit 1
fi

echo "Checking PHP files..."

find "$SRC" -type f -name '*.php' -print0 |
while IFS= read -r -d '' file; do
    php -l "$file" >/dev/null
done

echo "Copying updated application..."

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
    echo "Warning: No running PHP-FPM service found."
fi

echo "=================================="
echo "OpenRepeater update completed!"
echo "=================================="
