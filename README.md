# WeidianGrab 0.6.0

面向微店买家版 **7.9.62**（`com.koudai.weidian.buyer`）的 RootHide 插件。**接口直提版**：悬浮面板只做配置与参数采集，到点直接调用 App 自身的创建订单网络接口，不执行页面点击、不调用 Controller 的提交方法、不打开支付链接。

## 提交路径（机器码证据）

静态反汇编确认（样本 SHA256 `55FA08DB…99472`，证据见 `research/service-static/`）：

```text
+[VDTradeConfOrderService createOrderRequestDO:confirmOrderDO:result:]
  IMP 0x104ccbbb8   types v40@0:8@16@24@?32
   → WDNHttpVapInfo vbuy / CreateOrder / 1.0
   → WDNHttpThorHandler → WDTNNetworkManager POST
   → WDTNThorParameterProcessor 每次读取 currentServerTime 重新 md5 签名
   → POST https://<thorHost>/vbuy/CreateOrder/1.0
```

因此插件**不需要手工拼 Thor HTTP 或自算签名**：复用该 Service，由 App 原生网络栈在发送瞬间取服务器时间签名。

回调 ABI 由调用方 block descriptor 证实为：

```objc
void (^result)(BOOL isSuccess, id response, WDNErrorDO *error);  // v28@?0B8@12@"WDNErrorDO"20
```

插件使用**自己的**回调接收结果，**不**转发给 `createOrderSuccess:payButtonType:`——后者会进入支付 URL 路由。

## 已知边界

- 响应为原始字典透传，`order_id` 的字段位置/类型**未证实**。插件只按 `order_id` / `order_ids` 做可选识别，识别不到时报告“接口成功、订单号未知”，不推断支付成功。
- 接口成功 ≠ 支付成功。插件不调用 `VDTradePayManager`，不打开返回的支付 URL。
- `risk_sign` 非空时原样复用；为空时 App 内部会自行生成。插件不生成、不刷新、不绕验证码与频控。
- SDK 存在条件性 HTTPS 重发；插件在自身层保证单任务只调用一次、无重试，网络层内部行为不作保证。
- 商品/SKU/数量三项不足以证明成功，故提交时传入采集到的完整 `requestDO` / `confirmOrderDO`（仅内存）。

## 面板

悬浮球可拖动、靠边吸附。面板提供：

1. 自动采集开关与完整商品/规格/数量、确认金额、支付参数摘要。
2. 到点提醒 / 本地演练 / **接口直提** 三种动作。
3. 时间选择（含时区）、倒计时、取消。
4. **5 秒本地演练**：只消耗本地任务，不发网络请求。
5. 清空采集、导出诊断。

接口直提在设置时即冻结参数并在面板中列出商品、金额与时间供确认；到点前重新校验参数指纹，变化即不发送。任务限定在样本十分钟有效期内。

## 状态机

```text
armed → firing → sending → apiSucceeded / failed / unknown
```

- 发出前取消：直接停止，不发请求。
- **发出后取消：只记录意图，不撤单**，继续等待真实结果。
- 回调最多接受一次；迟到回调在 `unknown` 后仍可补记为最终结果。
- 30 秒未返回标记 `unknown` 并释放参数，提示人工核对，不重试。
- App 重启后 `sending`/`unknown` 任务转为 `unknown`，不自动恢复提交。

## 隐私

参数模型与接口响应**只在内存**，不落盘、不写日志。落盘的只有脱敏摘要（会话盐 HMAC 商品引用、标题、数量、价格）、版本、任务状态事件与诊断计数。导出诊断会剔除订单号。

## RootHide 构建

固定 `roothide/theos` 提交 `88506b2c…`、`THEOS_PACKAGE_SCHEME=roothide`、`ARCHS=arm64 arm64e`、最低 iOS 15；CI 校验固定 SDK 归档 SHA256（归档名 16.5，实际 16.4）。

```sh
make clean && make package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
python3 scripts/validate_deb.py packages/com.koudai.weidian.grab_0.6.0_iphoneos-arm64e.deb \
  --version 0.6.0 --expected-sdk 16.4 --output manifest.json
```

CI 在构建前运行两组状态机断言（39 条）：`Tests/task_gate_test.c`、`Tests/service_state_test.c`。

## 验收状态

已完成：静态链路与 ABI 证据、四模块 ARM64 编译、39 条状态机断言、构建产物验证。
待验：0.6.0 云端双架构出包、真机面板与采集、真机接口提交（未在调试中发送真实订单）。
