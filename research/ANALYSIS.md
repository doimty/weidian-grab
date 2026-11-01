# 微店交易流程分析与验证记录

目标：微店买家版 7.9.62，`com.koudai.weidian.buyer`，iOS15.1.1 / RootHide。
本记录针对 0.5.0 本地源码，不把旧版 deb 的安装成功当作新版验证。

## 证据范围

- `weidian-objc.txt` 为 ipsw 静态导出，读取工具报告共 577,582 个实际文本行（旧统计的 508,927 是非空行计数）。
- `research/runtime-metadata.json` 是本轮只读 Frida 探针结果。仅查询固定类/selector、方法类型与镜像；未主动调用下单、支付、验证码或风控方法。
- `get_app_info` 重新确认 App 版本 7.9.62 和当前沙盒路径。
- 静态声明不包含实现、block 内部参数布局、调用关系或 HTTP 结果。下面的阶段划分是定位线索，不冒充反编译调用图。

## 真实交易类

普通确认链的候选分层：

```text
VDTradeConfOrderViewController
  requestConfirmOrder: / requestReConfirmOrder:
  createOrder: / createOrderHelp: / checkOrderRepeat: / createRealOrder:
  createOrderFinish:isSuccess:error:payButtonType:
  createOrderSuccess:payButtonType: / payCallback

VDTradeConfOrderViewModel
  requestDO / confirmOrderDO / preConfirmOrderDO
  requestConfirmOrder: / requestReConfirmOrder:
  checkRepeatOrder:result: / createOrder:result:

VDTradeConfOrderService
  confirmOrderWithRequestDO:result:
  reconfirmOrderRequestDO:confirmOrderDO:result:
  createOrderRequestDO:confirmOrderDO:result:
```

原导出位置：Service 364828、普通 Controller 365258、ViewModel 365380。

快捷下单的容器实际为 `VDTradeQuickOrderView`（373521）与 `VDConfQuickOrderViewModel`（329846）；`VDQuickOrder*` 多数是子视图。容器有 `handleBottomPayClick`、`goToCreateOrder:`、`createRealOrder:isShowLoading:` 等入口，不能把它们和普通页面的同名方法混用。

支付管理器单独存在：`VDTradePayManager`（372270）有 `startPayWithParams:resultBlock:`、`pay:responseCallback:`、`sdkPay:responseCallback:`。没有证据表明原生创建成功后一定停止支付，因此插件仅标记“已派发原生入口”，不报告订单或支付成功。

## 本轮运行时 ABI

| 类 / selector | ObjC 类型编码 | 结论 |
|---|---|---|
| `+[VDTradeConfOrderService confirmOrderWithRequestDO:result:]` | `v32@0:8@16@?24` | 返回 void，模型 + block |
| `+[VDTradeConfOrderService createOrderRequestDO:confirmOrderDO:result:]` | `v40@0:8@16@24@?32` | 返回 void，两个模型 + block |
| `-[VDTradeConfOrderViewModel requestConfirmOrder:]` | `v24@0:8@?16` | 参数是 block，不能当普通对象调用 |
| `-[VDTradeConfOrderViewModel createOrder:result:]` | `v32@0:8Q16@?24` | 首参是 NSUInteger，后面为未知布局 block |
| `-[VDTradeConfOrderViewController createOrder:]` | `v24@0:8Q16` | 首参是 NSUInteger，不是请求模型 |
| `-[VDTradeConfOrderViewController createRealOrder:]` | `v24@0:8Q16` | 同为 NSUInteger，具体语义仍需验证 |
| `-[VDTradeConfOrderViewController viewDidAppear:]` | `v20@0:8B16` | BOOL 参数的生命周期回调 |
| `-[VDTradeConfOrderViewModel setRequestDO:]` | `v24@0:8@16` | 可被动观察自然发生的模型赋值 |
| `-[VDTradeConfOrderViewModel setConfirmOrderDO:]` | `v24@0:8@16` | 可被动观察确认数据落地 |

快捷页面不存在 `createOrder:` / `createRealOrder:` 这两个单参数 selector。本地适配器选择 `goToCreateOrder:`，但在每次准备执行前仍动态验证 void/Q；不存在或 ABI 不符保持未就绪。

## 自动采集白名单

请求侧：`VDTradeConfirmOrderRequestDO.items` → `VDTradeConfOrderRequestItemDO` 的 `item_id`、`item_sku_id`、`quantity`。

确认侧：`VDTradeConfirmOrderDO.shop_list` → `VDTradeConfirmOrderShopDO.item_list` → `VDTradeConfirmOrderShopItemDO`：

- 商品/SKU 标识及数量；以带盐 HMAC 引用代替原始标识落盘。
- `item_name` / `item_sku_title` / `price` 作为可选显示文本。
- `is_select` / `is_valid` 仅在 getter 通过 BOOL ABI 检查时读取。
- 根级 `total_pay_price`、`cannot_submit`。
- `pay_options` 的 selected/available 项中的 buttons(type/name)，不猜按钮枚举。

快捷页另核对 `VDTradeItemInfoDO.selectedSkuInfo`（真实类型 `VDTradeItemSkuInfo`，不同于 `VDTradeSkuInfo`）与当前请求三元组。

不采集整个请求/确认对象、buyer、address、Cookie、Authorization、风险签名、路由参数或埋点字典。

## 旧判断的纠正

1. 只搜 `WD` 前缀漏掉了完整的 `VDTrade*` 交易模块。不能据此断言“下单类必须懒加载后才存在”。
2. libhooker 源码通过 `dlopen` 正常加载插件；已有包含真实初始化节。没有证据支持“RootHide 不执行 constructor”。0.5.0 使用唯一 constructor + main queue + dispatch_once。
3. 当前设备运行时已看到 `WeidianGrab.dylib`，且两个 NSURLSession 方法的实现镜像就是它；旧日志路径不存在不能证明 Hook 未安装。
4. `.roothidepatch` 在设备上为指向 AutoPatches 的符号链接，绝不手工复制插件作为补丁。
5. 仅看到零次 Flutter TLS 事件不能证明整个业务永不经过 Flutter；实现选择交易层模型观察，因此不依赖这种推断。

## 本轮完成与待验

已完成：静态结构、固定 selector 的运行时存在性/ABI、四个 Objective-C 模块编译为本地 ARM64 iOS 对象、生产一次性任务门控 15 条测试、构建产物验证器的历史包正反例。

待验：新 0.5.0 经固定 RootHide Theos 的 arm64+arm64e 正式链接/打包、手机悬浮球、自然采集、定时演练与取消。真实下单/支付不属于本轮调试动作。
