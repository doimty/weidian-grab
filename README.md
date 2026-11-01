# WeidianGrab 0.5.0

面向微店买家版 **7.9.62**（`com.koudai.weidian.buyer`）的 RootHide 插件。当前工作分支新增悬浮面板、白名单交易摘要以及前台单次定时任务；源码已完成本地 iOS ARM64 对象编译检查，实际双架构 deb 和手机 UI 测试仍需运行当前版本 CI 后验证。旧 0.4.x 的安装成功与新功能已验证是两回事。

## 依据与接入层

已用 ipsw 导出主程序 ObjC 声明，并在真实运行进程核对了部分 ABI。分析见 [交易结构记录](research/ANALYSIS.md)，原始导出和 App 二进制仅保留本机，不参与构建或提交。

- 普通确认页：`VDTradeConfOrderViewController` / `VDTradeConfOrderViewModel`。
- 快捷下单：`VDTradeQuickOrderView` / `VDConfQuickOrderViewModel`。
- 被动观察两个 VM 的 `setRequestDO:` / `setConfirmOrderDO:`，以及页面自然显示。只从指定商品模型读取字段，不主动请求、加购物车或发订单。
- `createOrder:` 与 `goToCreateOrder:` 仅作为用户在面板确认并设置 `nativeOnce` 任务后的入口；调用前重新校验返回 `void`、唯一业务参数为 `NSUInteger(Q)`。
- 头文件揭示的是类、selector 和属性。它既不是反编译结果，也不证明调用顺序、支付结果或 block 参数布局。

## 面板

App 活动、scene 就绪后显示“微助”悬浮球，可拖动、靠边吸附，点开包含：

1. 自动采集开关、商品/规格/数量和确认金额摘要。
2. 到点提醒、本地演练、提交一次三种动作。
3. 日期时间选择、当前页提交按钮选择、倒计时和取消。
4. **5 秒本地演练**按钮：只消耗一次本地任务，不发网络请求。
5. 清空采集和分享诊断报告。

“提交一次”会先展示商品、规格、金额、时间供用户确认。任务仅调用 App 当前页的原生流程一次，不重放 HTTP、不猜支付枚举、不自动重试；后续验证和支付由微店决定，因此返回 `dispatched` **仅代表已调用入口，绝非订单/付款成功**。

## 自动采集与隐私

只保存指定字段：会话盐 HMAC 处理的商品/SKU 引用、商品标题、规格、数量字符串、价格字符串、已选/有效状态、实际服务端按钮 type/name。不会序列化 requestDO/confirmOrderDO 整个对象，不读取 Cookie、Authorization、请求体、收件地址、买家资料、验证码或风控签名。

请求商品与确认商品三元组必须匹配（包含重复行计数），快捷页还要匹配当前选中 SKU。字段缺失、getter ABI 未验证、按钮未知时仍可展示摘要，但单次提交保持未就绪。

状态保存在 **App 沙盒 `Library/Application Support/WeidianGrab/`**：

- `state.json`：开关、摘要、任务。
- `events.jsonl`：脱敏状态事件，约 1 MiB 轮转。
- `report.json`：面板“导出诊断”的分享文件。

旧的全局 JSON 配置与原始 Cookie 重放代码不再用于 0.5.0。旧 Frida 侦察脚本仅作历史调试资料。

## 定时约束

- 使用设备绝对时间；不宣称与服务器时间同步或硬实时执行。
- 设置范围为未来 2 秒至 24 小时。
- 微店切后台、锁屏或采集到新样本时取消。
- 到点后重新核验页面可见、同一 VM/模型、样本指纹、商品与价格、选定按钮和 ABI；样本超过十分钟或到时延迟超过两秒不执行。
- 主进程重启后旧任务转为取消，不自动恢复交易动作。
- 每次设置独立 task UUID，执行前先消费；同一任务至多调用一次。

## RootHide 构建

遵循 workspace 已工作 OKOK 工程：`roothide/theos` 固定提交 `88506b2c22e9e07dd4ed055f23c9e398a117a2c7`、`THEOS_PACKAGE_SCHEME=roothide`、`ARCHS=arm64 arm64e`、最低 iOS15。不靠改 control 架构伪装适配。

CI 下载固定 SDK 归档并校验 SHA256。归档目录标签为 16.5，内部 SDKSettings 实际版本为 16.4，manifest 如实记录。

```sh
make clean
make package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
python3 scripts/validate_deb.py \
  packages/com.koudai.weidian.grab_0.5.0_iphoneos-arm64e.deb \
  --version 0.5.0 --expected-sdk 16.4 --output manifest.json
```

维护脚本只为本插件创建指向 `/usr/lib/DynamicPatches/AutoPatches.dylib` 的正确软链，绝不把插件复制为 `.roothidepatch`。不向 SpringBoard 注入，不改其他插件 filter。

CI 包含完整 build.log、toolchain.json、manifest.json 和精确版本的 deb；验证器检查架构、真实 load commands、filter、脚本权限、符号链接和 SHA256。

## 调试验收

先安装新包并重开微店，在面板检查版本与 build ID。优先验证悬浮球、自然采集、5 秒演练、取消以及后台取消。调试不执行 `nativeOnce`，也不提交真实订单/付款。

已完成：本地四模块 ARM64 对象编译、生产任务门控 15 条可执行断言、运行时存在性与部分 ABI、历史包验证器正反例。
待完成：新 0.5.0 云端双架构链接/出包与手机 UI/自然采集/定时演练。
