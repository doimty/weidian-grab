# WeidianGrab

微店买家版（`com.koudai.weidian.buyer`）的抓包 / 抢单 tweak。

微店是 ObjC + Flutter 混合体，下单链路可能走任一条，所以抓取做了双通路：

| 通路 | 覆盖 | 重放 |
|---|---|---|
| `NSURLSession` | 原生页面 | ✅ 支持 |
| `SSL_write`（BoringSSL） | Flutter / `dart:io` | ❌ 仅记录（见下） |

## 安装

```sh
dpkg -i com.koudai.weidian.grab_0.1.0_iphoneos-arm64e.deb
killall -9 WDBuyerUniv
```

注入确认：

```sh
tail -f /var/mobile/Library/Logs/WeidianGrab.log
```

第一行应该是 `loaded; SSL_write hook = ok`。

## 两阶段用法

### 阶段一：抓

```sh
cp /var/mobile/Library/Preferences/com.koudai.weidian.grab.json /tmp/
# 或直接写：
cat > /var/mobile/Library/Preferences/com.koudai.weidian.grab.json <<'EOF'
{"enabled":true,"mode":"capture","match":"","repeat":200,"intervalMs":80,
 "successContains":"","stopOnSuccess":true,"maxBodyLog":8192}
EOF
killall -9 WDBuyerUniv && open com.koudai.weidian.buyer
```

然后在 App 里**手动下一单**（到提交订单那一步即可，不用真付款），日志里会出现：

```
REQ POST https://xxx/order/create
  headers={"Cookie":"...","Authorization":"...",...}
  body={"skuId":123,"num":1,...}
```

或者 Flutter 通路的：

```
TLS POST /api/v2/order/submit HTTP/1.1
Host: ...
Cookie: ...
{"sku_id":...}
```

### 阶段二：重放

把上面抓到的 URL 特征和成功判据填进配置：

```json
{
  "enabled": true,
  "mode": "replay",
  "match": "order/create",
  "repeat": 200,
  "intervalMs": 80,
  "successContains": "\"success\":true",
  "stopOnSuccess": true
}
```

重载配置不用重启 App：

```sh
# 用 MCP 工具或 SSH 执行
python3 -c "import ctypes;ctypes.CDLL(None).CFNotificationCenterPostNotification(ctypes.CDLL(None).CFNotificationCenterGetDarwinNotifyCenter(), 'com.koudai.weidian.grab/reload', None, None, True)"
```

或直接 `killall -9 WDBuyerUniv` 重开。

命中 `match` 后 tweak 会用自己的 `NSURLSession` 把**同一个请求**（方法/头/body 原样，含 Cookie 与 Authorization）按 `intervalMs` 间隔连发 `repeat` 次，响应里出现 `successContains` 就停并写 `*** SUCCESS at attempt N ***`。

## Flutter 通路的说明

`SSL_write` 能抓到 Flutter 的明文请求（TLS 加密前），但**不能自动重放** —— 重放需要 dart 侧的状态（签名、nonce、加密参数），tweak 里重建不了。

处理办法：把日志里那段完整请求（请求行 + 头 + body）拷出来，用 PC 侧脚本重发：

```python
import requests
headers = { ...从日志里抄... }
body = "...从日志里抄..."
for i in range(200):
    r = requests.post("https://host/path", headers=headers, data=body, timeout=10)
    if '"success":true' in r.text:
        print("hit", i); break
```

如果那边有签名/时间戳，就需要在脚本里复现签名算法 —— 这一步通常得反 Flutter 的 `libapp.so`（`class-dump` 看不到，得上 IDA + Flutter 符号还原）。

## 注意

- 这个 tweak 只做「抓 + 重发」，不含任何风控绕过。微店对下单有频控（同账号、同设备、同 IP），`intervalMs` 调得太狠会直接被拒，建议从 200ms 起试。
- 重放用的是抓到的 Cookie/Token，**过期就失效**，需要重新抓一次。
- 日志里有完整 Cookie，别外传。
