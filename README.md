# badge-app: a Claude Code skill for Solana OS badge apps

Teaches [Claude Code](https://claude.com/claude-code) to build, fix, verify and ship Lua apps
for the **Solana Breakpoint 2026 badge** (Solana OS, ESP32-C5, 320×218 screen, six keys,
8 RGB LEDs).

Ask Claude to *"make a reaction-time game for the badge"*, *"add a sleep timer to my LED app"*,
or *"why does my app crash with 'Script took too long'?"*. The skill gives it:

- the badge's rules (Lua 5.5 sandbox, 32-bit numbers, the 200k instruction budget, UI object
  limits, tick timing, permissions in `app.json`) and an everyday API cheat sheet
- a workflow: read the right section of the official `LUA_API.md`, scaffold, write, verify,
  then package for the App Store
- **`badgeapp.py`**, a dev CLI: `new`, `check`, `push`, `dev --watch`, `run`, `logs`, `sh`, `zip`
- **`verify.py`**, which compiles every `.lua` with Lua 5.5, runs the store's package checks
  and, with a badge plugged in, pushes the app, presses keys, streams the console, takes a
  screenshot and fails on any Lua error, all over a single serial connection

## Install

### Option 1: install script (recommended)

```sh
curl -fsSL https://raw.githubusercontent.com/cesp99/badge-app-skill/main/install.sh | bash
```

This installs to `~/.claude/skills/badge-app`, so the skill is available in every project.
Options:

```sh
# only for the current project (./.claude/skills/badge-app), e.g. to commit it with your apps
curl -fsSL https://raw.githubusercontent.com/cesp99/badge-app-skill/main/install.sh | bash -s -- --project

# also clone the official Solana OS repo (Lua API docs + examples) into ./solana-os
curl -fsSL https://raw.githubusercontent.com/cesp99/badge-app-skill/main/install.sh | bash -s -- --docs

# a specific version, or a different skills folder
... | bash -s -- --ref v1.0.0
... | bash -s -- --dir /path/to/skills

# remove it
... | bash -s -- --uninstall            # add --project if you installed it per project
```

Run it again to update. Read the script before you pipe it to bash if you prefer:
[`install.sh`](install.sh).

### Option 2: Claude Code plugin marketplace

Inside Claude Code:

```
/plugin marketplace add cesp99/badge-app-skill
/plugin install badge-app@badge-app-skill
```

Update later with `/plugin marketplace update badge-app-skill`.

### Option 3: manually

```sh
git clone https://github.com/cesp99/badge-app-skill
cp -R badge-app-skill/skills/badge-app ~/.claude/skills/        # or .claude/skills/ in a project
# or symlink it to keep it updated with `git pull`:
ln -s "$PWD/badge-app-skill/skills/badge-app" ~/.claude/skills/badge-app
```

### Claude.ai / Claude Desktop

Download `badge-app.zip` from the [latest release](https://github.com/cesp99/badge-app-skill/releases/latest)
and upload it under *Settings → Capabilities → Skills*. Claude can then write and review
badge apps there. Pushing to a badge over USB needs Claude Code on your machine.

## Requirements

| Needed for | What |
|---|---|
| Running the tools | Python 3.9+ and [`uv`](https://docs.astral.sh/uv/) (or `pip install pyserial pillow`) |
| The compile check | Lua 5.5 `luac` on PATH (`luac5.5` or `luac`). Without it the step is skipped with a warning |
| Testing on hardware | The badge on USB (`/dev/ttyUSB0` by default, or set `BADGE_PORT`) and read access to the port: on Linux, join `dialout` (Debian, Ubuntu, Fedora) or `uucp` (Arch) |
| API docs | A checkout of [solana-foundation/solana-os](https://github.com/solana-foundation/solana-os) in your workspace. `--docs` clones it, and Claude clones it itself when it's missing |

## Typical layout

Work from a folder like this (Claude creates what's missing):

```
my-badge-stuff/
├── solana-os/        # git clone --depth 1 https://github.com/solana-foundation/solana-os
├── apps/<id>/        # your apps: main.lua + app.json (+ bundled files)
└── dist/             # store zips from `badgeapp.py zip`
```

## Using the tools without Claude

```sh
SKILL=~/.claude/skills/badge-app
alias badgeapp="uv run -q --with pyserial --with pillow python3 $SKILL/scripts/badgeapp.py"
alias badgeverify="uv run -q --with pyserial --with pillow python3 $SKILL/scripts/verify.py"

badgeapp new my-app --name "My App" --author @you   # scaffold apps/my-app/
badgeapp dev apps/my-app --watch                    # push, run, stream print(), re-push on save
badgeverify apps/my-app --badge --keys "down select" --shot /tmp/my-app.png
badgeapp zip apps/my-app                            # dist/my-app-<version>.zip
```

Publish the zip in a browser at <https://solana.com/breakpoint/badge/apps/submit> (signed in,
X account linked). The store blocks scripted access, so publishing can't be automated.

Opening the serial port resets the badge on Linux (CH340 DTR/RTS), and that closes the running
app. That's why `verify.py` does everything in one connection.

## Repo layout

```
skills/badge-app/          # the skill (what gets installed)
├── SKILL.md
└── scripts/
    ├── badgeapp.py        # dev CLI
    └── verify.py          # compile + check + on-badge test
evals/                     # test prompts and graders for the skill (not installed)
.claude-plugin/            # plugin + marketplace manifests
install.sh
```

## Notes

- `led.keep` (LED scenes that keep running after an app exits) only exists on the
  [`persistent-leds`](https://github.com/cesp99/solana-os/tree/persistent-leds) firmware branch
  so far. The skill always feature-gates it.
- Not affiliated with the Solana Foundation. The Lua API reference belongs to
  [solana-foundation/solana-os](https://github.com/solana-foundation/solana-os) (MIT).

## License

MIT
