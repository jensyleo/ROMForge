#!/bin/bash
# ROMForge — full uninstall: deregister, purge state, move app to Trash.
# Copyright (C) 2026 Jensy Leonardo Martínez Cruz — GPLv3, no warranty.
set -euo pipefail

BUNDLE_ID="com.jensyleo.romforge"
APP="/Applications/ROMForge.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "▸ Resetting TCC grants…"
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true

echo "▸ Removing preferences, caches and saved state…"
rm -f  "$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -rf "$HOME/Library/Caches/$BUNDLE_ID"
rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
rm -rf "$HOME/Library/HTTPStorages/$BUNDLE_ID"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

if [[ -d "$APP" ]]; then
    echo "▸ Deregistering from LaunchServices…"
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    echo "▸ Moving app to Trash…"
    osascript -e 'tell application "Finder" to delete POSIX file "'"$APP"'"' >/dev/null || true
fi

echo "✓ ROMForge uninstalled."
