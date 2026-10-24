#!/usr/bin/env bash
# Gera build/appimage/BrainW4llet-<versão>-x86_64.AppImage a partir do build
# Linux release. Requer: clang, cmake, ninja, gtk3 e o appimagetool
# (APPIMAGETOOL, padrão ~/development/appimagetool/appimagetool-x86_64.AppImage).
set -euo pipefail
cd "$(dirname "$0")/.."

APPIMAGETOOL="${APPIMAGETOOL:-$HOME/development/appimagetool/appimagetool-x86_64.AppImage}"
VERSION="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
BUNDLE=build/linux/x64/release/bundle
OUT=build/appimage
APPDIR="$OUT/BrainW4llet.AppDir"

flutter build linux --release

rm -rf "$OUT"
mkdir -p "$APPDIR"
cp -R "$BUNDLE"/. "$APPDIR/"
cp linux/packaging/brainw4llet.desktop "$APPDIR/"
rsvg-convert -w 256 -h 256 linux/packaging/brainw4llet.svg -o "$APPDIR/brainw4llet.png"
ln -s brainw4llet.png "$APPDIR/.DirIcon"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/brainw4llet" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# Extrai em vez de montar via FUSE, para funcionar mesmo sem fuse2.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" --no-appstream \
  "$APPDIR" "$OUT/BrainW4llet-$VERSION-x86_64.AppImage"
rm -rf "$APPDIR"
(cd "$OUT" && sha256sum ./*.AppImage | tee "BrainW4llet-$VERSION-x86_64.AppImage.sha256")
