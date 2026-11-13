#!/usr/bin/env bash
# Install the badge-app skill for Claude Code.
#
#   curl -fsSL https://raw.githubusercontent.com/cesp99/badge-app-skill/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --project        # this project only (./.claude/skills)
#   curl -fsSL .../install.sh | bash -s -- --docs           # also clone the Solana OS docs here
#   curl -fsSL .../install.sh | bash -s -- --uninstall
#
# Options:
#   --user         install for every project: ~/.claude/skills/badge-app (default)
#   --project      install into ./.claude/skills/badge-app
#   --dir <path>   install into <path>/badge-app (any skills folder)
#   --ref <ref>    branch or tag to install (default: main)
#   --docs         clone github.com/solana-foundation/solana-os into ./solana-os (API docs)
#   --uninstall    remove the skill from the chosen location
set -euo pipefail

REPO="cesp99/badge-app-skill"
NAME="badge-app"
REF="main"
DEST_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
DOCS=0
UNINSTALL=0

say()  { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --user) DEST_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" ;;
    --project) DEST_ROOT="$PWD/.claude/skills" ;;
    --dir) [ $# -ge 2 ] || die "--dir needs a path"; DEST_ROOT="$2"; shift ;;
    --ref) [ $# -ge 2 ] || die "--ref needs a branch or tag"; REF="$2"; shift ;;
    --docs) DOCS=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help)
      cat <<'USAGE'
install.sh [--user | --project | --dir <path>] [--ref <ref>] [--docs] [--uninstall]
  --user         install for every project: ~/.claude/skills/badge-app (default)
  --project      install into ./.claude/skills/badge-app
  --dir <path>   install into <path>/badge-app
  --ref <ref>    branch or tag to install (default: main)
  --docs         clone solana-foundation/solana-os into ./solana-os (Lua API docs)
  --uninstall    remove the skill from the chosen location
USAGE
      exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

DEST="$DEST_ROOT/$NAME"

if [ "$UNINSTALL" = 1 ]; then
  if [ -f "$DEST/SKILL.md" ]; then
    rm -rf "$DEST"
    say "removed $DEST"
  else
    say "nothing to remove at $DEST"
  fi
  exit 0
fi

# Source: a local checkout if this script is run from one, else the GitHub tarball.
SRC=""
# (When piped through `curl | bash` there is no script file, so always download.)
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/skills/$NAME/SKILL.md" ] && [ -f "$SCRIPT_DIR/install.sh" ]; then
  SRC="$SCRIPT_DIR/skills/$NAME"
  say "installing from local checkout $SCRIPT_DIR"
else
  command -v curl >/dev/null || die "curl is required"
  command -v tar  >/dev/null || die "tar is required"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  say "downloading $REPO@$REF"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xz -C "$TMP"
  SRC="$(find "$TMP" -mindepth 3 -maxdepth 3 -type d -path "*/skills/$NAME" | head -n1)"
  [ -n "$SRC" ] && [ -f "$SRC/SKILL.md" ] || die "skills/$NAME not found in the download"
fi

mkdir -p "$DEST_ROOT"
if [ -e "$DEST" ]; then
  say "replacing existing $DEST"
  rm -rf "$DEST"
fi
cp -R "$SRC" "$DEST"
chmod +x "$DEST"/scripts/*.py 2>/dev/null || true
say "installed to $DEST"

if [ "$DOCS" = 1 ]; then
  if [ -f "$PWD/solana-os/docs/LUA_API.md" ]; then
    say "solana-os docs already present in $PWD/solana-os"
  else
    command -v git >/dev/null || die "git is required for --docs"
    say "cloning solana-foundation/solana-os into $PWD/solana-os"
    git clone --depth 1 https://github.com/solana-foundation/solana-os "$PWD/solana-os"
  fi
fi

# Dependency check (warnings only; the skill tells Claude how to cope).
echo
if command -v uv >/dev/null; then
  say "uv found: the scripts run with 'uv run --with pyserial --with pillow'"
elif command -v python3 >/dev/null; then
  warn "uv not found. Install it (https://docs.astral.sh/uv/) or run: python3 -m pip install pyserial pillow"
else
  warn "python3 not found: the dev tools (badgeapp.py, verify.py) need Python 3.9+"
fi
LUAC=""
for c in luac5.5 luac; do
  if command -v "$c" >/dev/null && "$c" -v 2>&1 | grep -q '5\.5'; then LUAC="$c"; break; fi
done
if [ -n "$LUAC" ]; then
  say "Lua 5.5 compiler found ($LUAC)"
else
  warn "no Lua 5.5 'luac' on PATH: verify.py will skip the compile check (install Lua 5.5 to enable it)"
fi
if [ "$(uname -s)" = Linux ] && ! id -nG | grep -qwE 'dialout|uucp'; then
  warn "you're not in the dialout/uucp group, so /dev/ttyUSB0 may be unreadable: sudo usermod -aG dialout \$USER (or uucp), then log in again"
fi

echo
say "done. Start Claude Code and ask, e.g.: \"make a badge app that ...\""
[ "$DOCS" = 1 ] || say "tip: re-run with --docs in your badge project to fetch the Lua API docs (Claude can also do it for you)"
