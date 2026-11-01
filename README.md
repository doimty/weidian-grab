# WeidianGrab 0.8.1

微店买家版 7.9.62 / iOS15+ / RootHide。悬浮面板用于选择购物车目标、设定时间和最高实付金额；执行路径直接调用 App 原生网络 Service，不模拟点击，不调用订单页的提交按钮方法。

## 使用

1. 打开购物车刷新数据。任务卡自动带入已勾选的商品；点商品卡也可指定目标，不自动全选。
2. 主界面只有商品、开抢时间、最高实付金额（含运费）和一个“准备抢购”按钮。
3. 核对确认框后才设置任务。右上角“···”收纳本地参数校验、五秒演练和诊断导出。
4. 到点前保持微店在前台。悬浮卡可收起，执行不依赖订单确认页。

最多提前十二小时设置，原始商品 ID、地址等参数只在当前进程内存。App 重启不自动恢复交易任务。数据/时间改变后需重新确认。

## 自动流程

```text
已设置
  → 设定时刻前五秒 ConfirmOrder（晚设置则立即预热）
  → 校验响应模型和服务端提交状态
  → 若未开放，等待设定时刻再 ConfirmOrder 一次
  → 商品/SKU/数量匹配、金额不超上限、唯一可用已选支付按钮
  → 设定时刻直接 CreateOrder 最多一次
  → 接收接口结果，停止
```

未知响应、缺地址、待验证/协议、仍未开放、金额超限或参数变化时停止。不是无限轮询，不处理验证码，不改服务端开售限制。预热失败会直接停止，只有确认响应明确 `cannot_submit` 为 true 才在到点追加一次确认。时间按设备时钟，不宣称服务器同步或硬实时。

**前台限制：** 当前版本切后台、锁屏或系统时间显著变化会取消未发出的创建动作。未实现后台保活/跨进程调度；不要把“驻留购物车模板”理解成锁屏也能准点发单。

**创建已发出后：** 取消本地任务不代表撤单。等待结果期间不覆盖任务；超时为 unknown，不自动重试，迟到结果可补记。接口成功不等于支付成功。插件不打开返回的支付链接，但所选服务端支付方式本身可能有效果（例如极速支付），以微店实际订单为准。

## 原生参数与 ABI 依据

- 购物车观察 `fetchDataSucceed:(BOOL)ok cartListDO:(id)model`，保留 BOOL/object ABI 校验，修复旧版 `objc_retain(0x1)`。
- 每条购物车记录以 cartId/shop/item/SKU 共同索引，避免同商品不同规格覆盖。
- 原生 `itemIdCountSku` 的 token 为 `itemId_count_sku_payType`；VM 初始化把第四段解析为字符串 `price_type`。保留原 `priceType` 和 `payType` 分别采集，映射以反汇编证据为准，不按字段名称猜。
- 使用 `VDTradeConfOrderViewModel initWithRequest:` 的纯本地 token 解析生成 typed requestDO；不调用跳转/领券方法。
- Confirm 回调为 `void (^)(BOOL,id,WDNErrorDO*)`，返回原始字典，转换为 `VDTradeConfirmOrderDO` 后再校验。
- 创建入口 `+[VDTradeConfOrderService createOrderRequestDO:confirmOrderDO:result:]`，原生链路为 Thor POST，默认生产路由 `vbuy/CreateOrder/1.0`，由 App 取当前时间签名。
- 不调用 Controller 的成功回调或支付管理器，不手工重放 Cookie 请求。

确认接口是否接受当前默认收件信息、实际未开售商品返回的业务错误/状态、抢购成功率和最终订单号结构仍需真实业务验证。本轮调试不生成真实订单或付款。

## 测试与构建

`Tests/cart_preheat_mock.m` 连接真正的生产 `WDGCart.m` / `WDGOrderService.m`，仅把 App 类和网络接口换成本地 Foundation fixtures。覆盖 BOOL Hook、不同 SKU、空选择、token 构造、开售时序、二次确认、金额/模型拒绝、取消、超时与重复/迟到响应。

```sh
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
  -framework Foundation Tests/cart_preheat_mock.m WDGCart.m WDGOrderService.m \
  -o /tmp/cart-preheat-mock
/tmp/cart-preheat-mock
make clean && make package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
python3 scripts/validate_deb.py packages/com.koudai.weidian.grab_0.8.1_iphoneos-arm64e.deb \
  --version 0.8.1 --expected-sdk 16.4 --output manifest.json
```

固定 roothide/theos `88506b2c22e9e07dd4ed055f23c9e398a117a2c7`、arm64+arm64e、最低 iOS15。SDK归档名16.5，元数据实际16.4。CI先执行模拟/门控测试，再出精确包并核验依赖、filter、脚本与哈希；完整日志随产物保存。

配置/脱敏摘要和任务事件在 App 沙盒 `Library/Application Support/WeidianGrab/`。完整模型、原始接口响应不落盘。诊断导出不含原始 Cookie、地址或支付URL。
