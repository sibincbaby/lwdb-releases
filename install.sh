#!/bin/sh
# lwdb installer: downloads the release for this machine, checks its SHA-256 and installs it
# (~/.local/bin/lwdb, the desktop app, the agent skill). Run it again to update.
#   curl -fsSL https://raw.githubusercontent.com/sibincbaby/lwdb-releases/main/install.sh | sh
# LWDB_VERSION=v0.2.0 picks a release (default: the latest); LWDB_BIN_DIR overrides ~/.local/bin.
# Published as install.sh in github.com/sibincbaby/lwdb-releases; the source is scripts/get.sh.
# Releases come from Firebase Cloud Storage (Google's CDN; `latest` names the newest), else from
# the GitHub release (scripts/publish.sh puts them in both).
set -eu
cdn=https://storage.googleapis.com/lwdb-releases.firebasestorage.app/lwdb
gh=https://github.com/sibincbaby/lwdb-releases/releases
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) plat=macos-arm64 ;;
    Linux-x86_64 | Linux-amd64) plat=linux-x86_64 ;;
    *) echo "lwdb: no build for $(uname -s) $(uname -m) (macOS Apple Silicon and Linux x86_64 only)" >&2; exit 1 ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# a connection that hangs, or a download that stalls under 1 KB/s for 30 s: drop it and retry
net="--retry 3 --retry-delay 2 --connect-timeout 20 --speed-limit 1024 --speed-time 30"
# and any failure at all (a name lookup that fails is not one curl retries): the whole download
# again, three times in all
again() {
    n=1
    until "$@"; do
        [ $n -lt 3 ] || return 1
        echo "lwdb: the download failed; trying again" >&2
        n=$((n + 1))
        sleep 3
    done
}
# Download $1 to $2: in a terminal curl draws its progress bar; for the app (LWDB_PROGRESS=1,
# no terminal) a line each second, "lwdb: downloading 37%", that it shows as a progress bar.
fetch() {
    if [ "${LWDB_PROGRESS:-}" = 1 ]; then
        curl $net -fL# "$1" -o "$2" 2>"$2.progress" &
        pid=$! last=""
        while kill -0 "$pid" 2>/dev/null; do
            p=$(tr '\r' '\n' <"$2.progress" | grep -o '[0-9][0-9.]*%' | tail -n 1)
            p=${p%\%}
            p=${p%%.*}
            if [ -n "$p" ] && [ "$p" != "$last" ]; then echo "lwdb: downloading $p%"; last=$p; fi
            sleep 1
        done
        if ! wait "$pid"; then
            tr '\r' '\n' <"$2.progress" | grep -v '%' | grep . | tail -n 1 >&2
            return 1
        fi
        [ "$last" = 100 ] || echo "lwdb: downloading 100%"
    elif [ -t 2 ]; then
        curl $net -fL# "$1" -o "$2"
    else
        curl $net -fsSL "$1" -o "$2"
    fi
}
version=${LWDB_VERSION:-}
if [ -z "$version" ]; then
    version=$(curl $net -fsSL "$cdn/latest" 2>/dev/null | tr -d ' \r\n') || version=""
fi
case $version in
    "" | v[0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "lwdb: not a release: $version (e.g. LWDB_VERSION=v0.3.1)" >&2; exit 1 ;;
esac
# the package and its checksums from one place
get() {
    again fetch "$1/lwdb-$plat.tar.gz" "$tmp/lwdb-$plat.tar.gz" &&
        again curl $net -fsSL "$1/SHA256SUMS" -o "$tmp/SHA256SUMS"
}
echo "lwdb: downloading lwdb-$plat.tar.gz${version:+ ($version)}"
if [ -z "$version" ]; then
    get "$gh/latest/download"
elif ! get "$cdn/$version"; then
    echo "lwdb: trying GitHub instead" >&2
    get "$gh/download/$version"
fi
want=$(grep " lwdb-$plat.tar.gz\$" "$tmp/SHA256SUMS" | cut -d' ' -f1)
if command -v sha256sum >/dev/null; then
    have=$(sha256sum "$tmp/lwdb-$plat.tar.gz" | cut -d' ' -f1)
else
    have=$(shasum -a 256 "$tmp/lwdb-$plat.tar.gz" | cut -d' ' -f1)
fi
[ -n "$want" ] && [ "$have" = "$want" ] || { echo "lwdb: checksum mismatch, nothing installed" >&2; exit 1; }
mkdir "$tmp/pkg"
tar xzf "$tmp/lwdb-$plat.tar.gz" -C "$tmp/pkg"

# --- The old Node.js lwdb (npm link, the Tauri desktop app, the ~/.lwdb/skill snapshot): its
# store moves over before anything is removed, then its pieces go. Its checkout (with its
# data/ folder) and ~/.lwdb (the key, setdb config, backups) are kept.
lw=$HOME/.lwdb
store=${LW_DB_SQLITE:-${LW_DB_DATA_DIR:-$lw/data}/lwdb.sqlite}
# follow a symlink chain to its file (no readlink -f on older macOS)
resolve() {
    f=$1 n=0
    while [ -L "$f" ] && [ $n -lt 20 ]; do
        t=$(readlink "$f")
        case $t in /*) f=$t ;; *) f=$(dirname "$f")/$t ;; esac
        n=$((n + 1))
    done
    echo "$f"
}
old_repo="" old_links="" old=0
# the old `lwdb` links npm (or its ~/.local/bin fallback) put on PATH: they lead to bin/lwdb.mjs
for d in $(printf '%s' "$PATH" | tr ':' ' ') "$HOME"/.nvm/versions/node/*/bin \
    "$HOME"/.local/share/mise/installs/node/*/bin "$HOME/.volta/bin" /usr/local/bin /opt/homebrew/bin "$HOME/.local/bin"; do
    [ -L "$d/lwdb" ] || continue
    case $(resolve "$d/lwdb") in
        */bin/lwdb.mjs)
            case " $old_links " in *" $d/lwdb "*) continue ;; esac
            old_links="$old_links $d/lwdb"
            r=$(resolve "$d/lwdb")
            old_repo=${old_repo:-${r%/bin/lwdb.mjs}}
            ;;
    esac
done
if [ -f "$lw/launcher.json" ]; then
    r=$(sed -n 's/^ *"cwd": *"\(.*\)",*$/\1/p' "$lw/launcher.json" | head -n 1)
    [ -n "$r" ] && [ -d "$r" ] && old_repo=$r
fi
[ -n "$old_repo$old_links" ] || [ -e "$lw/launcher.json" ] || [ -e "$lw/skill" ] && old=1
old_apps=""
if [ "$(uname -s)" = Darwin ]; then
    for app in /Applications/lwdb.app "$HOME/Applications/lwdb.app"; do
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)" = com.linways.lwdb ] &&
            old_apps="$old_apps $app" && old=1
    done
fi
old_deb=0
if command -v dpkg-query >/dev/null && dpkg-query -L lwdb 2>/dev/null | grep -qx /usr/bin/lwdb-desktop; then
    old_deb=1 old=1
fi

if [ $old = 1 ]; then
    echo "lwdb: found the old Node.js lwdb; replacing it"
    # its desktop app first: it runs the old server, which writes the store
    for app in $old_apps; do
        if pgrep -f "$app/Contents/MacOS/" >/dev/null 2>&1; then
            osascript -e 'tell application id "com.linways.lwdb" to quit' >/dev/null 2>&1 || true
            sleep 2
        fi
        if mv "$app" "$HOME/.Trash/lwdb-nodejs-$(date +%Y%m%d-%H%M%S).app" 2>/dev/null; then
            echo "  moved the old app $app to the Trash"
        else
            echo "  couldn't move the old app $app: drag it to the Trash yourself"
        fi
    done
    if [ $old_deb = 1 ]; then
        echo "  removing the old desktop app's package (sudo dpkg -r lwdb; your password may be asked)"
        if (exec </dev/tty) 2>/dev/null && sudo dpkg -r lwdb </dev/tty >/dev/null; then
            echo "  removed the lwdb package"
        else
            echo "  not removed: run  sudo dpkg -r lwdb"
        fi
    fi
    # the store: connections, saved queries, history (the key in ~/.lwdb/key is the same)
    if [ -n "$old_repo" ] && [ -f "$old_repo/data/lwdb.sqlite" ]; then
        if [ -e "$store" ]; then
            echo "  kept your current store $store; the old one stays at $old_repo/data/lwdb.sqlite"
            echo "    (to use the old one instead: lwdb restore $old_repo/data/lwdb.sqlite)"
        else
            mkdir -p "$(dirname "$store")"
            cp -p "$old_repo/data/lwdb.sqlite" "$store"
            if [ -f "$old_repo/data/lwdb.sqlite-wal" ]; then cp -p "$old_repo/data/lwdb.sqlite-wal" "$store-wal"; fi
            echo "  copied your connections, saved queries and history from $old_repo/data/lwdb.sqlite"
        fi
    fi
    for l in $old_links; do
        d=$(dirname "$l")
        # npm link's global package link sits beside its bin dir
        m=$(dirname "$d")/lib/node_modules/lwdb
        if rm -f "$l" 2>/dev/null; then
            echo "  removed the old command $l"
            if [ -L "$m" ]; then rm -f "$m" 2>/dev/null || true; fi
        else
            echo "  couldn't remove $l: run  sudo rm $l"
        fi
    done
    rm -f "$lw/launcher.json"
fi

bash "$tmp/pkg/scripts/install.sh" --no-build </dev/null

if [ $old = 1 ]; then
    # Copilot's and Codex's skill links led to the old ~/.lwdb/skill: now copies of the new skill
    for t in .copilot .codex; do
        l=$HOME/$t/skills/lwdb
        if [ -L "$l" ]; then
            rm -f "$l"
            mkdir -p "$l"
            cp "$HOME/.claude/skills/lwdb/SKILL.md" "$l/SKILL.md"
            echo "lwdb: updated the agent skill in $l"
        fi
    done
    rm -rf "$lw/skill"
    echo "lwdb: the old Node.js lwdb is removed.${old_repo:+ Its folder $old_repo (with its data/) is kept: delete it when you no longer need it.}"
fi
case ":$PATH:" in
    *":${LWDB_BIN_DIR:-$HOME/.local/bin}:"*) ;;
    *) echo "lwdb: add ${LWDB_BIN_DIR:-$HOME/.local/bin} to PATH, e.g. echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc" ;;
esac
