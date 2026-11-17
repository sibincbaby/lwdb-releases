# lwdb

Release builds of lwdb: a CLI, MCP server and desktop app for MySQL and Postgres.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/sibincbaby/lwdb-releases/main/install.sh | sh
```

macOS on Apple Silicon and Linux x86_64. It installs `~/.local/bin/lwdb`, the desktop app
(`~/Applications/lwdb.app` on macOS, an app-menu entry on Linux) and the agent skill
(`~/.claude/skills/lwdb`), then runs `lwdb doctor`. It never touches your data (`~/.lwdb`).

Already have the old Node.js lwdb? The same line replaces it: your connections, saved queries
and history move over (same key), and the old command, app and skill links are removed. The old
lwdb folder (with its `data/`) is kept until you delete it.

Downloads come from Firebase Cloud Storage (Google's network), with this repo's GitHub releases as
the fallback.

Run the same line again to update (or, from 0.3.0, `lwdb update` or Check for Updates… in the app). Pick a version with `LWDB_VERSION=v0.2.0`.
