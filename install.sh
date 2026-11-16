#!/bin/sh
# lwdb installer: downloads the release for this machine, checks its SHA-256 and installs it
# (~/.local/bin/lwdb, the desktop app, the agent skill). Run it again to update.
#   curl -fsSL https://raw.githubusercontent.com/sibincbaby/lwdb-releases/main/install.sh | sh
# LWDB_VERSION=v0.2.0 picks a release (default: the latest); LWDB_BIN_DIR overrides ~/.local/bin.
# Published as install.sh in github.com/sibincbaby/lwdb-releases; the source is scripts/get.sh.
set -eu
repo=https://github.com/sibincbaby/lwdb-releases/releases
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) plat=macos-arm64 ;;
    Linux-x86_64 | Linux-amd64) plat=linux-x86_64 ;;
    *) echo "lwdb: no build for $(uname -s) $(uname -m) (macOS Apple Silicon and Linux x86_64 only)" >&2; exit 1 ;;
esac
case "${LWDB_VERSION:-latest}" in
    latest) url=$repo/latest/download ;;
    *) url=$repo/download/$LWDB_VERSION ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "lwdb: downloading lwdb-$plat.tar.gz"
curl -fsSL "$url/lwdb-$plat.tar.gz" -o "$tmp/lwdb-$plat.tar.gz"
curl -fsSL "$url/SHA256SUMS" -o "$tmp/SHA256SUMS"
want=$(grep " lwdb-$plat.tar.gz\$" "$tmp/SHA256SUMS" | cut -d' ' -f1)
if command -v sha256sum >/dev/null; then
    have=$(sha256sum "$tmp/lwdb-$plat.tar.gz" | cut -d' ' -f1)
else
    have=$(shasum -a 256 "$tmp/lwdb-$plat.tar.gz" | cut -d' ' -f1)
fi
[ -n "$want" ] && [ "$have" = "$want" ] || { echo "lwdb: checksum mismatch, nothing installed" >&2; exit 1; }
mkdir "$tmp/pkg"
tar xzf "$tmp/lwdb-$plat.tar.gz" -C "$tmp/pkg"
bash "$tmp/pkg/scripts/install.sh" --no-build </dev/null
case ":$PATH:" in
    *":${LWDB_BIN_DIR:-$HOME/.local/bin}:"*) ;;
    *) echo "lwdb: add ${LWDB_BIN_DIR:-$HOME/.local/bin} to PATH, e.g. echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc" ;;
esac
