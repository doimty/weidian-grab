// 微店抓单脚本（Frida）
//
// 为什么是 Frida 而不是 tweak：roothide 的 libhooker 不加载我们编的 dylib
// （路径/注册契约没摸清），而 Frida 已经验证能钩到真实的 thor.weidian.com 请求。
//
// 两种模式（改下方 CONFIG 后重新 load 即可，不用重启 App）：
//   capture  只打印匹配 host 的请求（URL / 方法 / 头 / body）
//   replay   命中 MATCH 后，用 App 自己的 NSURLSession 原样重发，
//            响应里出现 SUCCESS_CONTAINS 就停
//
// 用法：
//   frida -H 127.0.0.1:27043 -n WDBuyerUniv -l weidian_grab.js
//   （先起 ssh 隧道：python tools\frida-tunnel.py 27043 --proxy 127.0.0.1:7897 --ssh <ip>:22）

var CONFIG = {
    mode: "capture",            // capture | replay
    hostFilter: "weidian.com",  // 只关心业务域名
    match: "",                  // replay 触发条件：URL 或 body 含此子串
    repeat: 0,                  // 重放次数（0 = 不做）
    intervalMs: 80,
    successContains: "",        // 判定成功
    maxBody: 1200
};

var replaying = false;
var done = false;

function log(s) {
    console.log(s);
}

function clip(v, n) {
    if (v === null || v === undefined) return "";
    var s = String(v);
    return s.length > n ? s.substring(0, n) + "…" : s;
}

function isApi(url) {
    if (!CONFIG.hostFilter) return true;
    return url.indexOf(CONFIG.hostFilter) >= 0;
}

function bodyOf(req) {
    try {
        var d = req.HTTPBody();
        if (!d) return "";
        return new ObjC.Object(d).toString();
    } catch (e) { return ""; }
}


// 用新建的 session 重发（会再次经过我们的 hook，用 replaying 挡住递归）
function replayOnce(req) {
    if (done) return;

    var cfg = ObjC.classes.NSURLSessionConfiguration.defaultSessionConfiguration();
    cfg.setTimeoutIntervalForRequest_(8.0);
    var session = ObjC.classes.NSURLSession.sessionWithConfiguration_(cfg);

    var handler = new ObjC.Block({
        retType: "void",
        argTypes: ["object", "object", "object"],
        implementation: function (data, resp, err) {
            if (done) return;
            var code = 0;
            try { code = resp.statusCode(); } catch (e) {}
            var text = "";
            try {
                if (data) text = ObjC.Object(data).toString();
            } catch (e) {}
            var hit = CONFIG.successContains && text.indexOf(CONFIG.successContains) >= 0;

            log("[try] code=" + code + " len=" + (text ? text.length : 0) +
                " hit=" + hit + (hit ? "  " + clip(text, 200) : ""));

            if (hit) {
                done = true;
                log("*** SUCCESS ***");
            }
        }
    });

    var task = session.dataTaskWithRequest_completionHandler_(req, handler);
    task.resume();
}

function startReplay(req) {
    log("=== REPLAY " + req.URL().absoluteString() + " x" + CONFIG.repeat + " ===");
    for (var i = 0; i < CONFIG.repeat; i++) {
        (function (n) {
            setTimeout(function () { replayOnce(req); }, n * CONFIG.intervalMs);
        })(i);
    }
}

// --- 主钩子：四个变体都要挂 ---
// 微店大量请求走 delegate 模式（- dataTaskWithRequest:），只钩 completionHandler
// 版本会一条都看不到 —— 这是实测踩出来的。
function onRequest(req) {
    if (replaying) return;
    try {
        var url = req.URL().absoluteString().toString();
        if (!isApi(url)) return;

        var method = req.HTTPMethod().toString();
        var body = bodyOf(req);
        var hdrs = "";
        try { hdrs = req.allHTTPHeaderFields().toString(); } catch (e) {}

        log("REQ " + method + " " + clip(url, 300));
        log("    hdr=" + clip(hdrs, 500));
        if (body) log("    body=" + clip(body, CONFIG.maxBody));

        if (CONFIG.mode === "replay" && !done && CONFIG.match &&
            (url.indexOf(CONFIG.match) >= 0 || body.indexOf(CONFIG.match) >= 0)) {
            replaying = true;
            startReplay(req);
        }
    } catch (e) {
        log("[err] " + e.message);
    }
}

[
    "- dataTaskWithRequest:completionHandler:",
    "- dataTaskWithRequest:",
    "- dataTaskWithURL:completionHandler:",
    "- dataTaskWithURL:"
].forEach(function (sel) {
    try {
        var m = ObjC.classes.NSURLSession[sel];
        if (!m) { log("[!] missing " + sel); return; }
        Interceptor.attach(m.implementation, {
            onEnter: function (args) {
                var arg = new ObjC.Object(args[2]);
                // URL 变体传的是 NSURL，包成 request 便于统一处理
                var req = null;
                try { req = arg.URL() ? arg : ObjC.classes.NSURLRequest.requestWithURL_(arg); }
                catch (e) { req = arg; }
                if (req) onRequest(req);
            }
        });
        log("[+] hooked " + sel);
    } catch (e) {
        log("[-] " + sel + ": " + e.message);
    }
});

log("[*] mode=" + CONFIG.mode + " filter=" + CONFIG.hostFilter +
    (CONFIG.match ? " match=" + CONFIG.match : "") +
    (CONFIG.repeat ? " repeat=" + CONFIG.repeat : ""));
