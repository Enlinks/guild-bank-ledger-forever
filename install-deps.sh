#!/bin/bash
# Refresh embedded libraries. Ace3's SVN host is not required; WoWUIDev/Ace3 tracks the same trunk.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --depth 1 https://github.com/WoWUIDev/Ace3.git "$tmp/ace3"
git clone --depth 1 --branch stable https://github.com/niketa-wow/libaddonutils.git "$tmp/libaddonutils"

rm -rf "$root/Libs"
mkdir -p "$root/Libs"
for lib in LibStub CallbackHandler-1.0 AceLocale-3.0 AceAddon-3.0 AceEvent-3.0 AceHook-3.0 AceConsole-3.0 AceDB-3.0 AceDBOptions-3.0 AceSerializer-3.0 AceGUI-3.0 AceConfig-3.0; do
    cp -a "$tmp/ace3/$lib" "$root/Libs/$lib"
done
cp -a "$tmp/ace3/LICENSE.txt" "$root/Libs/Ace3-LICENSE.txt"
mkdir -p "$root/Libs/LibAddonUtils"
cp -a "$tmp/libaddonutils/LibAddonUtils.lua" "$tmp/libaddonutils/LibAddonUtils.xml" "$tmp/libaddonutils/README.md" "$root/Libs/LibAddonUtils/"
