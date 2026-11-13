#!/usr/bin/env python3
"""Verify a Solana OS badge app: compile, package check, and (optionally) a run on the badge.

    uv run -q --with pyserial --with pillow python3 verify.py <app-dir>                 # static only
    uv run -q --with pyserial --with pillow python3 verify.py <app-dir> --badge \\
        --keys "down down select" --shot /tmp/app.png --secs 3

Static (always):
  1. every .lua file compiles with the local Lua 5.5 (`luac -p`), like the store's compiler
  2. `badgeapp.py check`: manifest fields and the store's package limits

On the badge (--badge, needs /dev/ttyUSB0 or $BADGE_PORT), in ONE serial connection,
because every new connection resets the badge and closes the running app:
  3. push changed files (closes whatever app is open), `lua run <id>`
  4. stream the console for --secs, then press each of --keys (one `key` command each,
     --gap seconds apart), streaming the console in between
  5. optional screenshot (--shot out.png), then `lua mem` (heap peak, instruction count)

Exit code 1 if anything failed: a compile error, a check error, or a `[lua:<id>] ...`
error line on the console (runtime error, "Script took too long", out of memory).
"""
import argparse, base64, glob, os, re, shutil, struct, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))


def find_badge_dev():
    """Folder holding badgeapp.py: the copy bundled next to this script, or $BADGE_DEV."""
    for c in (os.environ.get("BADGE_DEV"), HERE):
        if c and os.path.isfile(os.path.join(c, "badgeapp.py")):
            return os.path.abspath(c)
    sys.exit("error: badgeapp.py not found (set BADGE_DEV to the folder that holds it)")


def find_luac():
    for name in ("luac5.5", "luac"):
        p = shutil.which(name)
        if not p:
            continue
        v = subprocess.run([p, "-v"], capture_output=True, text=True)
        if "5.5" in (v.stdout + v.stderr):
            return p
    return None


def compile_check(d):
    luac = find_luac()
    files = sorted(glob.glob(os.path.join(d, "**", "*.lua"), recursive=True))
    if not luac:
        print("warning: no Lua 5.5 luac on PATH; skipping the compile check")
        return True
    ok = True
    for f in files:
        r = subprocess.run([luac, "-p", f], capture_output=True, text=True)
        if r.returncode:
            ok = False
            print("compile error: " + (r.stderr or r.stdout).strip().replace(d.rstrip("/") + "/", ""))
    if ok:
        print(f"compile: ok ({len(files)} Lua file(s), {os.path.basename(luac)})")
    return ok


ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def decode_shot(text, path):
    from PIL import Image
    w = h = None
    rows = {}
    for line in text.splitlines():
        line = ANSI.sub("", line).strip()
        if line.startswith("SHOT-BEGIN"):
            _, w, h = line.split()[:3]
            w, h = int(w), int(h)
        elif line.startswith("SHOT "):
            parts = line.split(" ")
            if len(parts) != 5:
                continue
            try:
                rows[(int(parts[1]), int(parts[2]))] = (int(parts[3]), base64.b64decode(parts[4]))
            except Exception:
                pass
    if not w:
        print("warning: no screenshot in the console output")
        return False
    img = Image.new("RGB", (w, h))
    px = img.load()
    for (x0, y), (n, data) in rows.items():
        for i in range(min(n, len(data) // 2)):
            v = struct.unpack_from("<H", data, i * 2)[0]
            r, g, b = (v >> 11) & 0x1F, (v >> 5) & 0x3F, v & 0x1F
            if x0 + i < w and y < h:
                px[x0 + i, y] = (r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    img.save(path)
    print(f"screenshot: {path} ({w}x{h}, {len(rows)} rows)")
    return True


def on_badge(ba, d, a):
    b, app_id = ba.push(d, a.port)
    log = []

    def pump(secs, until=None):
        """Read the console for `secs` (or until a line contains `until`); echo app lines."""
        end = time.time() + secs
        raw = []
        while time.time() < end:
            ln = b.readline(0.1)
            if ln is None:
                continue
            raw.append(ln)
            c = ba.clean(ln)
            if c.startswith("SHOT ") or c.startswith("SHOT-"):
                if until and until in c:
                    break
                continue
            log.append(c)
            print("  | " + c)
            if until and until in c:
                break
        return raw

    def write(cmd):
        b.s.write((cmd + "\r\n").encode())
        b.s.flush()

    print(f"--- running {app_id} (console below) ---")
    write(f"lua run {app_id}")
    pump(a.secs)
    for k in a.keys.split():
        print(f"--- key {k} ---")
        write(f"key {k}")
        pump(a.gap)
    if a.shot:
        write("shot")
        raw = pump(60, until="SHOT-END")
        decode_shot("\n".join(raw), a.shot)
    print("--- lua mem ---")
    write("lua mem")
    pump(1.5)
    errs = [l for l in log if l.startswith(f"[lua:{app_id}]")]
    return errs


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("dir")
    p.add_argument("--badge", action="store_true", help="push and run it on the badge")
    p.add_argument("--port", default=os.environ.get("BADGE_PORT", "/dev/ttyUSB0"))
    p.add_argument("--secs", type=float, default=3, help="console time after launch")
    p.add_argument("--keys", default="", help='keys to press, e.g. "down down select" (up down left right select back)')
    p.add_argument("--gap", type=float, default=1.0, help="console time after each key")
    p.add_argument("--shot", help="save a screenshot PNG here at the end")
    a = p.parse_args()

    d = os.path.abspath(a.dir)
    sys.path.insert(0, find_badge_dev())
    import badgeapp as ba

    ok = compile_check(d)
    try:
        ba.check(d)
    except SystemExit:
        ok = False
    if not ok:
        print("FAILED (static)")
        sys.exit(1)
    if not a.badge:
        print("OK (static)")
        return
    if not os.path.exists(a.port):
        print(f"no badge at {a.port}: static checks passed, on-badge run skipped")
        return
    errs = on_badge(ba, d, a)
    if errs:
        print("FAILED on the badge:\n  " + "\n  ".join(errs))
        sys.exit(1)
    print("OK (static + badge)")


if __name__ == "__main__":
    main()
