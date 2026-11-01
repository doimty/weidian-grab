"""Recon: what does Weidian actually use for network?

Answers, with evidence rather than assumption:
  1. Are requests going through NSURLSession (ObjC) or dart:io (BoringSSL)?
  2. Which hosts / paths does the app hit while browsing?
  3. Is there a native order-submit call, or is it Flutter-only?

Usage:
  python weidian_recon.py --spawn        # cold start and watch
  python weidian_recon.py                # attach to running app
  python weidian_recon.py --seconds 40
"""
from __future__ import annotations

import argparse
import json
import sys
import time

import frida

BUNDLE = "com.koudai.weidian.buyer"

SCRIPT = r"""
var log = [];
function push(kind, text) {
  if (log.length < 400) log.push(kind + " " + text);
  send({kind: kind, text: text});
}

// --- 通路 1: NSURLSession ---
try {
  var NSURLSession = ObjC.classes.NSURLSession;
  var sel = "- dataTaskWithRequest:completionHandler:";
  var impl = NSURLSession[sel];
  if (impl) {
    Interceptor.attach(impl.implementation, {
      onEnter: function (args) {
        try {
          var req = new ObjC.Object(args[2]);
          var url = req.URL().absoluteString().toString();
          var method = req.HTTPMethod().toString();
          push("NSSESSION", method + " " + url);
        } catch (e) { push("NSSESSION-ERR", e.message); }
      }
    });
    push("HOOK", "NSURLSession dataTaskWithRequest:completionHandler: attached");
  } else {
    push("HOOK", "NSURLSession selector missing");
  }
} catch (e) { push("HOOK-ERR", "NSURLSession: " + e.message); }

// --- 通路 2: BoringSSL (dart:io / Flutter) ---
try {
  var mods = Process.enumerateModules().filter(function (m) {
    return /boringssl|libssl|Flutter/i.test(m.name);
  });
  push("MODULES", mods.map(function (m) { return m.name; }).join(", ") || "(none matched)");

  var sslWrite = Module.findExportByName(null, "SSL_write");
  if (sslWrite) {
    Interceptor.attach(sslWrite, {
      onEnter: function (args) {
        try {
          var n = args[2].toInt32();
          if (n <= 0 || n > 65536) return;
          var s = args[1].readUtf8String(Math.min(n, 1024));
          if (!s) return;
          if (s.indexOf("GET ") === 0 || s.indexOf("POST ") === 0 ||
              s.indexOf("PUT ") === 0 || s.indexOf("HTTP/") === 0) {
            var line = s.split("\r\n")[0];
            push("BORINGSSL", line);
          }
        } catch (e) {}
      }
    });
    push("HOOK", "SSL_write attached");
  } else {
    push("HOOK", "SSL_write export not found");
  }
} catch (e) { push("HOOK-ERR", "SSL_write: " + e.message); }
"""


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1:27043")
    ap.add_argument("--spawn", action="store_true")
    ap.add_argument("--seconds", type=int, default=30)
    args = ap.parse_args(argv[1:])

    device = frida.get_device_manager().add_remote_device(args.host)

    if args.spawn:
        pid = device.spawn([BUNDLE])
        print(f"[*] spawned {BUNDLE} pid={pid}")
        session = device.attach(pid)
    else:
        procs = [p for p in device.enumerate_processes() if "WDBuyer" in p.name]
        if not procs:
            print("[!] Weidian not running - use --spawn")
            return 2
        pid = procs[0].pid
        print(f"[*] attaching to {procs[0].name} pid={pid}")
        session = device.attach(pid)

    script = session.create_script(SCRIPT)

    counts: dict[str, int] = {}
    samples: list[str] = []

    def on_message(message, data):
        if message.get("type") == "send":
            payload = message["payload"]
            kind, text = payload.get("kind", "?"), payload.get("text", "")
            counts[kind] = counts.get(kind, 0) + 1
            if kind.startswith("HOOK") or kind == "MODULES" or kind.endswith("ERR"):
                print(f"  [{kind}] {text}")
            elif len(samples) < 40:
                samples.append(f"{kind} {text}")
                print(f"  {kind}: {text}")

    script.on("message", on_message)
    script.load()

    if args.spawn:
        device.resume(pid)
        print("[*] resumed")

    print(f"[*] watching for {args.seconds}s - 现在去 App 里点几下（首页→商品→下单页）")
    time.sleep(args.seconds)

    print("\n=== 统计 ===")
    for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {k}: {v}")

    session.detach()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
