#!/bin/bash
# Builds Cellar.app and packs it into build/Cellar.dmg with a drag-to-Applications link.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh

STAGE=build/dmg
rm -rf "$STAGE" build/Cellar.dmg
mkdir -p "$STAGE"
cp -R build/Cellar.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Cellar -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/Cellar.dmg
rm -rf "$STAGE"
echo "Built build/Cellar.dmg"
