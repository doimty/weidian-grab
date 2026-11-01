"""Deeper recon: which hosts does Weidian resolve, and does Flutter do TLS at all?

Hooks:
  getaddrinfo        - every DNS lookup, stack-agnostic
  SSL_do_handshake   - TLS connection attempts inside Flutter
  SSL_write/_ex      - plaintext writes inside Flutter
  NSURLSession       - all dataTask variants, to prove what is native

Usage: python weidian_probe.py --seconds 25
"""
from __future__ import annotations

import argparse
import sys
import time

import frida

SCRIPT = r"""
function emit(k, t) { send({k: k, t: t}); }

// --- DNS：与协议栈无关，谁上网都能看见 ---
try {
  var gai = Module.findExportByName(null, "getaddrinfo");
  if (gai) {
    Interceptor.attach(gai, {
      onEnter: function (a) {
        try {
          var node = a[0].readCString();
          if (node && !/^\d+\.\d+\.\d+\.\d+$/.test(node)) emit("DNS", node);
        } catch (e) {}
      }
    });
    emit("HOOK", "getaddrinfo ok");
  } else { emit("ERR", "getaddrinfo missing"); }
} catch (e) { emit("ERR", "gai " + e.message); }

// --- Flutter 里的 BoringSSL ---
try {
  var m = Process.findModuleByName("Flutter");
  if (m) {
    var counts = {};
    var wanted = { "SSL_do_handshake": 0, "SSL_write": 0, "SSL_write_ex": 0, "SSL_read": 0 };
    m.enumerateSymbols().forEach(function (s) {
      if (wanted.hasOwnProperty(s.name)) {
        try {
          Interceptor.attach(s.address, { onEnter: function () { counts[s.name] = (counts[s.name] || 0) + 1; } });
        } catch (e) {}
      }
    });
    emit("HOOK", "flutter ssl symbols watched");
    setInterval(function () {
      var parts = [];
      for (var k in counts) parts.push(k + "=" + counts[k]);
      emit("COUNT", parts.join(" "));
    }, 3000);
  }
} catch (e) { emit("ERR", "flutter " + e.message); }

// --- 原生侧所有 dataTask 变体 ---
try {
  ["- dataTaskWithRequest:completionHandler:",
   "- dataTaskWithRequest:",
   "- dataTaskWithURL:completionHandler:",
   "- dataTaskWithURL:"].forEach(function (sel) {
    var impl = ObjC.classes.NSURLSession[sel];
    if (!impl) return;
    Interceptor.attach(impl.implementation, {
      onEnter: function (a) {
        try {
          var arg = new ObjC.Object(a[2]);
          var url = null;
          try { url = arg.URL().absoluteString().toString(); } catch (e) {}
          if (!url) { try { url = arg.absoluteString().toString(); } catch (e) {} }
          if (!url) { try { url = arg.description().toString(); } catch (e) {} }
          if (!url) return;
          emit("NATIVE", sel.substring(2, 16) + " " + url);
        } catch (e) { emit("ERR", "extract " + e.message); }
      }
    });
  });
  emit("HOOK", "nsurlsession variants ok");
} catch (e) { emit("ERR", "nsurlsession " + e.message); }
"""


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1:27043")
    ap.add_argument("--seconds", type=int, default=25)
    args = ap.parse_args(argv[1:])

    device = frida.get_device_manager().add_remote_device(args.host)
    procs = [p for p in device.enumerate_processes() if "WDBuyer" in p.name]
    if not procs:
        print("[!] Weidian not running")
        return 2
    session = device.attach(procs[0].pid)
    script = session.create_script(SCRIPT)

    hosts: dict[str, int] = {}

    def on_message(msg, data):
        if msg.get("type") != "send":
            return
        k, t = msg["payload"]["k"], msg["payload"]["t"]
        if k == "DNS":
            hosts[t] = hosts.get(t, 0) + 1
            print(f"  DNS    {t}")
        elif k in ("HOOK", "ERR", "COUNT"):
            print(f"  {k:<6} {t}")
        else:
            print(f"  {k:<6} {t[:120]}")

    script.on("message", on_message)
    script.load()
    time.sleep(args.seconds)

    print("\n=== 域名汇总 ===")
    for h, c in sorted(hosts.items(), key=lambda kv: -kv[1]):
        print(f"  {c:>3}x  {h}")
    session.detach()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
