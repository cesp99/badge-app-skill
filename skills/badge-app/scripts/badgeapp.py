#!/usr/bin/env python3
"""badgeapp: create, sideload and package Solana OS (Breakpoint badge) Lua apps.

    badgeapp.py new <id> [--name "My App"]   scaffold ./apps/<id>/ (main.lua + app.json)
    badgeapp.py check <dir>                  validate the package against the store's limits
    badgeapp.py push <dir> [--run]           copy changed files onto the badge over USB
    badgeapp.py dev <dir> [--watch]          push, run and stream the console (re-push on save)
    badgeapp.py run <id>                     start an installed app and stream its output
    badgeapp.py logs                         stream the badge console
    badgeapp.py sh "<cmd>" ...               run console commands (info, lua list, lua mem, ...)
    badgeapp.py zip <dir>                    build ./dist/<id>-<version>.zip for /apps/submit

Sideloading uses the same console protocol as the web's "Run on badge"
(`lua sums` + `lua recv`, see solana-os/docs/LUA_API.md "Console (development)").
Publishing is done on the web: https://solana.com/breakpoint/badge/apps/submit
"""
import argparse, base64, hashlib, json, os, re, sys, time, zipfile

PORT = os.environ.get("BADGE_PORT", "/dev/ttyUSB0")
HERE = os.path.dirname(os.path.abspath(__file__))

ID_RE = re.compile(r"^[a-z0-9-]{3,24}$")
PART_RE = re.compile(r"^[a-z0-9_.-]+$")
ICONS = "play star heart bell gift home image list wifi shuffle eye edit charge gps settings audio bulb".split()
CATEGORIES = "games tools social quests demos".split()
PERMS = "led wifi mesh ble lamps items profile quest http rpc".split()
MAIN_MAX, FILE_MAX, FILES_MAX, TOTAL_MAX = 64 * 1024, 256 * 1024, 64, 1024 * 1024


# ---------------------------------------------------------------- package

def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def load_manifest(d):
    p = os.path.join(d, "app.json")
    if not os.path.isfile(p):
        die(f"{p} not found")
    with open(p) as f:
        return json.load(f)


def package_files(d):
    """[(relpath, abspath)] for everything that ships: main.lua, app.json, bundled files.
    Hidden files/folders and README*.md are skipped."""
    out = []
    for root, dirs, files in os.walk(d):
        dirs[:] = sorted(x for x in dirs if not x.startswith("."))
        for f in sorted(files):
            if f.startswith(".") or (root == d and f.lower().startswith("readme")):
                continue
            ap = os.path.join(root, f)
            out.append((os.path.relpath(ap, d).replace(os.sep, "/"), ap))
    return out


def check(d, quiet=False):
    m = load_manifest(d)
    errs, warns = [], []
    mid = m.get("id", "")
    if not ID_RE.match(mid):
        errs.append(f"id {mid!r}: 3-24 chars of a-z 0-9 -")
    if len(m.get("name", "")) > 20:
        errs.append("name: at most 20 chars")
    if m.get("icon") not in ICONS:
        warns.append(f"icon {m.get('icon')!r} is not one of: {' '.join(ICONS)}")
    if m.get("category") not in CATEGORIES:
        warns.append(f"category {m.get('category')!r} is not one of: {' '.join(CATEGORIES)}")
    for p in m.get("permissions", []):
        if p not in PERMS:
            errs.append(f"unknown permission {p!r} (known: {' '.join(PERMS)})")
    if m.get("hosts") and "http" not in m.get("permissions", []):
        warns.append("hosts are only used with the http permission")
    if not re.match(r"^[0-9A-Fa-f]{6}$", str(m.get("accent", "B6B0FF"))):
        errs.append("accent: 6 hex digits, no '#'")

    files = package_files(d)
    names = [r for r, _ in files]
    if "main.lua" not in names:
        errs.append("main.lua is missing")
    bundled, total = 0, 0
    for rel, ap in files:
        size = os.path.getsize(ap)
        if rel == "main.lua":
            if size > MAIN_MAX:
                errs.append(f"main.lua is {size} bytes (max {MAIN_MAX})")
            continue
        if rel == "app.json":
            continue
        bundled += 1
        total += size
        parts = rel.split("/")
        if (len(rel) > 64 or len(parts) > 4
                or any(not PART_RE.match(x) or x[0] == "." or x[-1] == "." for x in parts)):
            errs.append(f"{rel}: paths are lowercase a-z 0-9 _ - . , <=64 chars, <=4 levels")
        if size > FILE_MAX:
            errs.append(f"{rel} is {size} bytes (max {FILE_MAX})")
    if bundled > FILES_MAX:
        errs.append(f"{bundled} bundled files (max {FILES_MAX})")
    if total > TOTAL_MAX:
        errs.append(f"bundled files total {total} bytes (max {TOTAL_MAX})")
    if not quiet or errs:
        for w in warns:
            print(f"warning: {w}")
        for e in errs:
            print(f"error: {e}")
    if errs:
        sys.exit(1)
    if not quiet:
        print(f"ok: {mid} {m.get('version', '?')}, main.lua + {bundled} bundled files ({total} bytes)")
    return m, files


# ---------------------------------------------------------------- serial

class Badge:
    def __init__(self, port=PORT):
        try:
            import serial
        except ImportError:
            die("pyserial missing: run with `uv run --with pyserial badgeapp.py ...`")
        self.s = serial.Serial()
        self.s.port, self.s.baudrate, self.s.timeout = port, 115200, 0.05
        self.s.dtr = self.s.rts = False         # don't hold the chip in reset/boot
        try:
            self.s.open()
        except Exception as e:
            die(f"can't open {port}: {e}")
        self.buf = b""
        # Opening a CH340 port can reset the board: if it rebooted, wait for the console.
        head = self._read_for(1.0, b"ESP-ROM")
        if b"ESP-ROM" in head or b"rst:" in head:
            self._read_for(20, b"console ready")
            time.sleep(1.5)
        self.buf = b""

    def _read_for(self, secs, marker=None):
        out, end = b"", time.time() + secs
        while time.time() < end:
            d = self.s.read(4096)
            out += d
            if marker and marker in out:
                break
        return out

    def readline(self, timeout):
        end = time.time() + timeout
        while b"\n" not in self.buf:
            if time.time() > end:
                return None
            self.buf += self.s.read(4096)
        line, self.buf = self.buf.split(b"\n", 1)
        return line.decode("utf-8", "replace").rstrip("\r")

    def send(self, cmd):
        self.buf = b""
        self.s.reset_input_buffer()
        self.s.write((cmd + "\r\n").encode())

    def cmd(self, cmd, until=None, timeout=10, idle=0.6):
        """Send a console command; return its output lines (stop at a line matching
        `until`, or after `idle` seconds of silence)."""
        self.send(cmd)
        lines, last = [], time.time()
        end = time.time() + timeout
        while time.time() < end:
            ln = self.readline(0.1)
            if ln is None:
                if not until and lines and time.time() - last > idle:
                    break
                continue
            last = time.time()
            ln = clean(ln)
            if ln.endswith(cmd):             # the console's echo
                continue
            lines.append(ln)
            if until and re.search(until, ln):
                break
        return lines

    def stream(self):
        try:
            while True:
                d = self.s.read(4096)
                if d:
                    sys.stdout.write(d.decode("utf-8", "replace"))
                    sys.stdout.flush()
        except KeyboardInterrupt:
            print()


ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def clean(s):
    return ANSI.sub("", s).replace("sol> ", "").strip()


def sums(b, app_id):
    have = {}
    for ln in b.cmd(f"lua sums {app_id}", until=r"^sums: ", timeout=15):
        m = re.match(r"^([0-9a-f]{64}) (\d+) (.+)$", ln)
        if m:
            have[m.group(3)] = (m.group(1), int(m.group(2)))
        elif ln.startswith("sums: no"):
            die(ln)
    return have


def recv(b, app_id, rel, data):
    sha = hashlib.sha256(data).hexdigest()
    b64 = base64.b64encode(data)
    b.send(f"lua recv {app_id} {rel} {len(data)} {sha}")
    pos = 0
    while True:
        ln = b.readline(10)
        if ln is None:
            die(f"{rel}: no answer from the badge")
        ln = clean(ln)
        m = re.match(r"^recv: (ready|more) (\d+)", ln)
        if m:
            n = int(m.group(2))
            b.s.write(b64[pos:pos + n])
            b.s.flush()
            pos += n
        elif ln.startswith("recv: ok"):
            return
        elif ln.startswith("recv: error") or "close it first" in ln or ln.startswith("usage:"):
            die(f"{rel}: {ln}")


def push(d, port, close=True):
    m, files = check(d, quiet=True)
    app_id = m["id"]
    b = Badge(port)
    if close:
        b.cmd("open home", timeout=3)
        time.sleep(0.3)
    have = sums(b, app_id)
    # main.lua and bundled files first, app.json last (the badge lists the app once both exist)
    files.sort(key=lambda f: f[0] == "app.json")
    sent = 0
    for rel, ap in files:
        with open(ap, "rb") as f:
            data = f.read()
        if have.get(rel) == (hashlib.sha256(data).hexdigest(), len(data)):
            continue
        t = time.time()
        recv(b, app_id, rel, data)
        print(f"  sent {rel} ({len(data)} B, {time.time() - t:.1f}s)")
        sent += 1
    local = {r for r, _ in files}
    for rel in have:
        if rel not in local:
            b.cmd(f"lua rm {app_id} {rel}", timeout=5)
            print(f"  removed {rel}")
    print(f"pushed {app_id}: {sent} file(s) sent, {len(files) - sent} unchanged")
    return b, app_id


def snapshot(d):
    return {r: os.path.getmtime(a) for r, a in package_files(d)}


# ---------------------------------------------------------------- commands

MAIN_TEMPLATE = '''-- {name}: a Solana OS app. API: solana-os/docs/LUA_API.md
-- Screen below the status bar: ui.W x ui.H (320 x 218). Keys: up down left right select back.

local count = storage.get("count") or 0

ui.label(0, 40, "{name}", {{size=20, w=ui.W, align="center"}})
local label = ui.label(0, 90, tostring(count), {{size=32, w=ui.W, align="center", color="green"}})
ui.hint("SELECT +1   UP/DOWN +-10   CANCEL exit")

local function show()
  label:text(tostring(count))
end

function on_key(k, rep)
  if k == "select" then count = count + 1
  elseif k == "up" then count = count + 10
  elseif k == "down" then count = count - 10
  else return false end            -- "back" falls through: exits the app
  show()
  print("count", count)            -- shows on the serial console (badgeapp.py dev/logs)
  return true
end

function on_exit()
  storage.set("count", count)
end
'''


def cmd_new(a):
    if not ID_RE.match(a.id):
        die("id: 3-24 chars of a-z 0-9 -")
    d = os.path.join(a.dir, a.id)
    if os.path.exists(d):
        die(f"{d} already exists")
    os.makedirs(d)
    name = a.name or a.id.replace("-", " ").title()[:20]
    manifest = {
        "id": a.id, "name": name, "version": "0.1.0", "author": a.author,
        "summary": "A Solana OS app.", "icon": "star", "accent": "14F195",
        "category": "demos", "permissions": [],
    }
    with open(os.path.join(d, "app.json"), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    with open(os.path.join(d, "main.lua"), "w") as f:
        f.write(MAIN_TEMPLATE.format(name=name))
    print(f"created {d}/  (main.lua, app.json)\nnext: badgeapp.py dev {d} --watch")


def cmd_check(a):
    check(a.dir)


def cmd_push(a):
    b, app_id = push(a.dir, a.port)
    if a.run:
        b.cmd(f"lua run {app_id}", timeout=2)
        print(f"started {app_id}")


def cmd_dev(a):
    b, app_id = push(a.dir, a.port)
    print(f"running {app_id}; console below (Ctrl-C to stop)\n" + "-" * 60)
    b.send(f"lua run {app_id}")
    if not a.watch:
        b.stream()
        return
    seen = snapshot(a.dir)
    try:
        while True:
            d = b.s.read(4096)
            if d:
                sys.stdout.write(d.decode("utf-8", "replace"))
                sys.stdout.flush()
            now = snapshot(a.dir)
            if now != seen:
                seen = now
                time.sleep(0.2)              # let the editor finish writing
                print("\n" + "-" * 20 + " change detected, re-pushing " + "-" * 20)
                b.s.close()
                try:
                    b, _ = push(a.dir, a.port)
                except SystemExit:
                    b = Badge(a.port)        # keep watching after a failed check/push
                    continue
                b.send(f"lua run {app_id}")
    except KeyboardInterrupt:
        print()


def cmd_run(a):
    b = Badge(a.port)
    b.cmd("open home", timeout=2)
    b.send(f"lua run {a.id}")
    b.stream()


def cmd_logs(a):
    Badge(a.port).stream()


def cmd_sh(a):
    b = Badge(a.port)
    for c in a.cmds:
        for ln in b.cmd(c, timeout=a.timeout):
            print(ln)


def cmd_zip(a):
    m, files = check(a.dir, quiet=True)
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, f"{m['id']}-{m.get('version', '0')}.zip")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for rel, ap in files:
            z.write(ap, rel)
    print(f"wrote {path} ({len(files)} files)\nupload it at https://solana.com/breakpoint/badge/apps/submit")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", default=PORT, help=f"serial port (default {PORT}, or $BADGE_PORT)")
    sp = p.add_subparsers(dest="cmd", required=True)

    s = sp.add_parser("new"); s.add_argument("id"); s.add_argument("--name")
    s.add_argument("--author", default="@you"); s.add_argument("--dir", default="apps")
    s.set_defaults(f=cmd_new)
    s = sp.add_parser("check"); s.add_argument("dir"); s.set_defaults(f=cmd_check)
    s = sp.add_parser("push"); s.add_argument("dir"); s.add_argument("--run", action="store_true")
    s.set_defaults(f=cmd_push)
    s = sp.add_parser("dev"); s.add_argument("dir"); s.add_argument("--watch", action="store_true")
    s.set_defaults(f=cmd_dev)
    s = sp.add_parser("run"); s.add_argument("id"); s.set_defaults(f=cmd_run)
    s = sp.add_parser("logs"); s.set_defaults(f=cmd_logs)
    s = sp.add_parser("sh"); s.add_argument("cmds", nargs="+"); s.add_argument("--timeout", type=float, default=10)
    s.set_defaults(f=cmd_sh)
    s = sp.add_parser("zip"); s.add_argument("dir"); s.add_argument("--out", default="dist")
    s.set_defaults(f=cmd_zip)

    a = p.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
