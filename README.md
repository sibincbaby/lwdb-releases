# lwdb

Release builds of lwdb: a CLI, MCP server and desktop app for MySQL and Postgres.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/sibincbaby/lwdb-releases/main/install.sh | sh
```

macOS on Apple Silicon and Linux x86_64. It installs `~/.local/bin/lwdb`, the desktop app
(`~/Applications/lwdb.app` on macOS, an app-menu entry on Linux) and the agent skill
(`~/.claude/skills/lwdb`), then runs `lwdb doctor`. It never touches your data (`~/.lwdb`).

Run the same line again to update. Pick a version with `LWDB_VERSION=v0.2.0`.
