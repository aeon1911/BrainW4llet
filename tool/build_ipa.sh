#!/usr/bin/env bash
# Gera build/ipa/BrainW4llet-unsigned.ipa (macOS + Xcode). O AltStore/SideStore
# assina o app com o seu Apple ID na instalação.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build ios --release --no-codesign

rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R build/ios/iphoneos/Runner.app build/ipa/Payload/
(cd build/ipa && zip -qry BrainW4llet-unsigned.ipa Payload && rm -rf Payload)
(cd build/ipa && shasum -a 256 BrainW4llet-unsigned.ipa | tee BrainW4llet-unsigned.ipa.sha256)
