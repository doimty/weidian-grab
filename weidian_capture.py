"""Capture Weidian traffic from both stacks, with the UI driven separately.

Hooks:
  * NSURLSession (ObjC pages / third-party SDKs)
  * SSL_write inside the Flutter module (dart:io plaintext, pre-encryption)

Writes one line per request to a log file so a separate agent can drive the UI
and then read the result.

Usage:
  python weidian_capture.py --seconds 40 --out capture.log [--spawn]
"""
from __future__ import annotations

import argparse
import sys
import threading
import time

import frida

BUNDLE = "com.koudai.weidian.buyer"

SCRIPT = r"""
var interest = /weidian|koudai|wd\.|api\.|gw\.|m\./i;

function emit(kind, text) { send({k: kind, t: text}); }

// NSURLSession
try {
  var impl = ObjC.classes.NSURLSession["- dataTaskWithRequest:completionHandler:"];
  if (impl) {
    Interceptor.attach(impl.implementation, {
      onEnter: function (a) {
        try {
          var r = new ObjC.Object(a[2]);
          var url = r.URL().absoluteString().toString();
          var m = r.HTTPMethod().toString();
          var body = "";
          try {
            var d = r.HTTPBody();
            if (d) body = ObjC.Object(d).toString();
          } catch (e) {}
          emit("NSURLSession", m + " " + url + (body ? "\n    body=" + body.substring(0, 800) : ""));
        } catch (e) {}
      }
    });
  }
} catch (e) { emit("ERR", "nsurlsession " + e.message); }

// Flutter 静态链接的 BoringSSL
try {
  var flutter = Process.findModuleByName("Flutter");
  if (flutter) {
    var addr = null;
    flutter.enumerateSymbols().forEach(function (s) {
      if (s.name === "SSL_write" && addr === null) addr = s.address;
    });
    if (addr) {
      Interceptor.attach(addr, {
        onEnter: function (a) {
          try {
            var n = a[2].toInt32();
            if (n <= 0 || n > 65536) return;
            var txt = a[1].readUtf8String(Math.min(n, 2048));
            if (!txt) return;
            if (txt.indexOf("GET ") !== 0 && txt.indexOf("POST ") !== 0 &&
                txt.indexOf("PUT ") !== 0 && txt.indexOf("HTTP/") !== 0) return;
            var first = txt.split("\r\n")[0];
            var host = "";
            var mh = /Host: ([^\r\n]+)/i.exec(txt);
            if (mh) host = mh[1];
            emit("Flutter", first + "  host=" + host);
          } catch (e) {}
        }
      });
      emit("HOOK", "Flutter SSL_write attached @" + addr);
    } else {
      emit("ERR", "SSL_write symbol not found in Flutter");
    }
  } else {
    emit("ERR", "Flutter module missing");
  }
} catch (e) { emit("ERR", "flutter " + e.message); }
"""


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1:27043")
    ap.add_argument("--seconds", type=int, default=40)
    ap.add_argument("--out", default="capture.log")
    ap.add_argument("--spawn", action="store_true")
    args = ap.parse_args(argv[1:])

    device = frida.get_device_manager().add_remote_device(args.host)

    if args.spawn:
        pid = device.spawn([BUNDLE])
        session = device.attach(pid)
        print(f"[*] spawned pid={pid}")
    else:
        procs = [p for p in device.enumerate_processes() if "WDBuyer" in p.name]
        if not procs:
            print("[!] not running")
            return 2
        pid = procs[0].pid
        session = device.attach(pid)
        print(f"[*] attached pid={pid}")

    script = session.create_script(SCRIPT)
    fh = open(args.out, "w", encoding="utf-8")
    lock = threading.Lock()
    n = {"count": 0}

    def on_message(message, data):
        if message.get("type") != "send":
            return
        p = message["payload"]
        line = f"{p['k']}\t{p['t']}"
        with lock:
            n["count"] += 1
            fh.write(line + "\n")
            fh.flush()
        print("  " + line.replace("\n", " | ")[:200])

    script.on("message", on_message)
    script.load()

    if args.spawn:
        device.resume(pid)
        print("[*] resumed")

    print(f"[*] capturing {args.seconds}s -> {args.out}")
    time.sleep(args.seconds)
    session.detach()
    fh.close()
    print(f"[*] done, {n['count']} events")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
