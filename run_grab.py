"""Load weidian_grab.js into the running Weidian app and stream its output.

Usage:
  python run_grab.py            # 60s，抓取模式
  python run_grab.py --seconds 120
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import frida

BUNDLE = "com.koudai.weidian.buyer"
HERE = Path(__file__).resolve().parent


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1:27043")
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--script", default=str(HERE / "weidian_grab.js"))
    args = ap.parse_args(argv[1:])

    device = frida.get_device_manager().add_remote_device(args.host)
    procs = [p for p in device.enumerate_processes() if "WDBuyer" in p.name]
    if not procs:
        print("[!] 微店没在运行，先启动它")
        return 2

    print(f"[*] attach {procs[0].name} (pid {procs[0].pid})")
    session = device.attach(procs[0].pid)
    script = session.create_script(Path(args.script).read_text(encoding="utf-8"))
    script.on("message", lambda m, d: print(
        m.get("payload") if m.get("type") == "send" else f"[{m.get('type')}] {m.get('description', m)}",
        flush=True))
    script.load()
    print(f"[*] 脚本已注入，采集 {args.seconds}s —— 现在去 App 里点进商品/下单页", flush=True)

    try:
        time.sleep(args.seconds)
    except KeyboardInterrupt:
        pass

    session.detach()
    print("[*] done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
