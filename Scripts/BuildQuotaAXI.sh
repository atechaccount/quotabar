#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
VERSION="$(< "$ROOT/Scripts/quota-axi.version")"
BUN_VERSION=1.4.2
STAGE="$ROOT/.build/quota-axi-bundle"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid quota-axi version: $VERSION" >&2
    exit 1
fi

case "$(uname -m)" in
    arm64) TARGET=bun-darwin-arm64; BUN_PACKAGE=@oven/bun-darwin-aarch64 ;;
    x86_64) TARGET=bun-darwin-x64; BUN_PACKAGE=@oven/bun-darwin-x64 ;;
    *) echo "error: unsupported build architecture" >&2; exit 1 ;;
esac

mkdir -p "$STAGE"
export npm_config_cache="$ROOT/.build/npm-cache"
npm install --prefix "$STAGE/package" --no-save --package-lock=false --ignore-scripts --no-audit --no-fund "quota-axi@$VERSION"
npm install --prefix "$STAGE/bun" --no-save --package-lock=false --ignore-scripts --no-audit --no-fund "$BUN_PACKAGE@$BUN_VERSION"
# quota-axi reads package.json for --version; that file is not beside a compiled binary.
printf 'export const VERSION = "%s";\n' "$VERSION" > "$STAGE/package/node_modules/quota-axi/dist/src/version.js"
"$STAGE/bun/node_modules/$BUN_PACKAGE/bin/bun" build \
    "$STAGE/package/node_modules/quota-axi/dist/bin/quota-axi.js" \
    --compile --target="$TARGET" --outfile "$STAGE/quota-axi"
