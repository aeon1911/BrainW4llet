#!/usr/bin/env bash
# Empacota a extensão do Firefox (firefox/) em build/firefox/*.xpi, sem os
# testes. O .xpi sai sem assinatura: para instalar de vez no Firefox comum,
# assine pelo addons.mozilla.org (ver firefox/README.md).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' firefox/manifest.json | head -1)"
OUT="build/firefox"
NAME="BrainW4llet-$VERSION-firefox.xpi"
rm -rf "$OUT"
mkdir -p "$OUT"

# Lista ordenada e datas fixas: o mesmo código gera o mesmo arquivo.
FILES="$(cd firefox && find . -type f ! -path './test/*' ! -name package.json ! -name '.*' | sed 's#^\./##' | LC_ALL=C sort)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
(cd firefox && cp --parents $FILES "$STAGE/")
find "$STAGE" -exec touch -h -d '2026-01-01T00:00:00Z' {} +
(cd "$STAGE" && TZ=UTC zip -q -X -D "$OLDPWD/$OUT/$NAME" $FILES)

(cd "$OUT" && sha256sum ./* > firefox.sha256 && cat firefox.sha256)
