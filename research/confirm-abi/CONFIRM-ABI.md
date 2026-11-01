# VDTradeConfOrderService confirm 系列 result block ABI 静态确证

样本：`tools/weidian-grab/WDBuyerUniv.bin`（微店 7.9.62 arm64，未加密）
方法：`ipsw macho disass` / `ipsw macho dump` 静态只读分析。未连设备、未执行目标方法、未发网络。
证据目录：`tools/weidian-grab/research/confirm-abi/`

---

## 0. 结论速览

| selector | IMP | type encoding | block signature 字符串 | ObjC block 类型 |
|---|---|---|---|---|
| `+confirmOrderWithRequestDO:result:` | `0x104ccb140` | `v32@0:8@16@?24` | `v28@?0B8@12@"WDNErrorDO"20` | `void(^)(BOOL, id, WDNErrorDO *)` |
| `+reconfirmOrderRequestDO:confirmOrderDO:result:` | `0x104ccb49c` | `v40@0:8@16@24@?32` | `v28@?0B8@"VDTradeConfirmOrderDO"12@"WDNErrorDO"20` | `void(^)(BOOL, VDTradeConfirmOrderDO *, WDNErrorDO *)` |
| `+confirmOrderCheckRepeatWithRequestDO:confirmOrderDO:result:` | `0x104ccab70` | `v40@0:8@16@24@?32` | `v28@?0B8@12@"WDNErrorDO"20` | `void(^)(BOOL, id, WDNErrorDO *)`（**第二参数实际为原始 response 字典**） |

**核心答案**：`confirmOrderWithRequestDO:result:` 的 result block 是
`void(^)(BOOL success, id response, WDNErrorDO *error)`，签名 `v28@?0B8@12@"WDNErrorDO"20`，
与 `createOrderRequestDO:confirmOrderDO:result:` 的 block **完全同签名**（同一 signature 指针 `0x106e1cf5f`）。

**第二参数是什么（决定预热可用性）**：`confirm` 的 block 第二参数是 **原始 response 字典（NSDictionary / yy_model 输入）**，
不是 `confirmOrderDO` 模型。证据：`confirm` 内**不调用** `setResultClass:`，
`WDNetworkContext` 的 `resultClass` 为 nil ⇒ `thorSuccess:context:` 走 `loc_105832b70` 原样透传 payload。
真实调用方 `requestConfirmOrder:` 的 block 体自己 `yy_modelWithDictionary:` 才得到 `VDTradeConfirmOrderDO`。

---

## 1. 逐项确证

### 1.1 `+[VDTradeConfOrderService confirmOrderWithRequestDO:result:]`

- IMP：`0x104ccb140`
- type encoding：`v32@0:8@16@?24`
  - 证据：`research/service-static/method-addresses.txt:91`
    `0x104ccb140  +[VDTradeConfOrderService confirmOrderWithRequestDO:result:]  types=v32@0:8@16@?24  entry=0x1062d2e04 list=0x1062d2df0`
- 声明：`research/service-static/objc-addresses.txt:540902-540903`
  `+ (void)confirmOrderWithRequestDO:(id)_do result:(id /* block */)result;`
- 反汇编：`confirm-abi/confirm-disass.txt`
  - 入口 `0x104ccb140`：`x2` = requestDO（`0x104ccb160 mov x19, x2`），
    `x3` = result block → `0x104ccb180 mov x0, x3` / `0x104ccb184 retain` / `0x104ccb188 str x0, [sp,#0x40]`，
    `x0`（self/class）→ `0x104ccb164 str x0, [sp,#0x48]`
  - 尾部调用：`0x104ccb43c  bl j__objc_msgSend(x0, "request:context:")`
    调用前 `0x104ccb430 ldp x19, x0, [sp, #0x40]`（`x19` = 已 retain 的 result block，`x0` = 该 block 自身，用于 `objc_release` 后置）
    / `0x104ccb434 mov x2, x19` / `0x104ccb438 mov x3, x20`
    ⇒ **`x2` = 调用方原始 result block，`x3` = 新建 WDNetworkContext**
  - **关键**：`confirm` 全程**没有构造任何 block literal**（无 `__NSConcreteStackBlock`），
    也**没有** `setResultClass:`（`confirm-disass.txt` 中 `setResultClass` 出现 0 次）
    ⇒ block 原样转发，第二参数类型由 `WDNetworkContext` 默认行为决定，而非 `confirm` 指定。

- **block signature 取得（双向交叉验证，两处 descriptor 指向同一字符串）**

  | 来源 | descriptor vaddr | signature 指针 | 字符串 |
  |---|---|---|---|
  | 真实调用方 `-[VDTradeConfOrderViewModel requestConfirmOrder:]` | `0x107818630` | `0x106e1cf5f` | `v28@?0B8@12@"WDNErrorDO"20` |
  | 对照组 `createOrderRequestDO:confirmOrderDO:result:` | `0x107819be0` | `0x106e1cf5f` | `v28@?0B8@12@"WDNErrorDO"20` |

  - 调用方 descriptor 证据：`confirm-abi/caller-block-descriptor.txt`
    ```
    0x0
    0x100000030     ; flags = BLOCK_HAS_SIGNATURE | BLOCK_HAS_COPY_DISPOSE
    0x100443014     ; copy helper
    0x100422070     ; dispose helper
    0x106e1cf5f     ; signature
    0x100000200     ; layout: 0x20 bytes captured, 1 weak ref
    ```
  - signature 字符串证据：`confirm-abi/signature-strings.txt`
    `=== 0x106e1cf5f ===  v28@?0B8@12@"WDNErrorDO"20`
  - 调用点证据：`confirm-abi/caller-requestConfirmOrder-disass.txt:24-34`
    ```
    0x104ce4be0  adrp x9, 0x107818000
    0x104ce4be4  add  x9, x9, #0x630      ; data_107818630 (__DATA_CONST.__const)
    0x104ce4be8  stp  x8, x9, [sp, #0x10] ; invoke=0x104ce4c2c, descriptor=0x107818630
    0x104ce4c04  bl   j__objc_msgSend(x0, "confirmOrderWithRequestDO:result:")
    ```

### 1.2 `+[VDTradeConfOrderService reconfirmOrderRequestDO:confirmOrderDO:result:]`

- IMP：`0x104ccb49c`
- type encoding：`v40@0:8@16@24@?32`（`research/service-static/method-addresses.txt:92`）
- 反汇编：`confirm-abi/reconfirm-disass.txt`
  - `0x104ccb4bc mov x21, x4` → result block
  - `0x104ccbb30 bl j__objc_msgSend(x0, "request:context:")`，`x2` = block（`0x104ccbb24 ldr x22,[sp,#0x38]`）
  - **`setResultClass:` 存在 1 次**：`0x104ccbb1c`，`setResultClass:` ← `objc_opt_class(VDTradeConfirmOrderDO)`
    ⇒ `WDNetworkContext.resultClass = VDTradeConfirmOrderDO.class`
    ⇒ `thorSuccess:` 走 `yy_modelWithDictionary:`，block 第二参数是 **模型对象**
- block signature：descriptor `0x107818690`（`confirm-abi/caller-reconfirm-descriptor.txt`）→ sig `0x106e1cfa9`
  → `v28@?0B8@"VDTradeConfirmOrderDO"12@"WDNErrorDO"20`（`confirm-abi/signature-strings.txt`）
- 调用方：`-[VDTradeConfOrderViewModel requestReConfirmOrder:]` `0x104ce52a8`
  证据 `confirm-abi/caller-requestReConfirmOrder-disass.txt:25-34`（descriptor `data_107818690`，`x4` = block）
- 调用方 block 体 `sub_104ce5348`（`confirm-abi/caller-reconfirm-block-body.txt:20`）
  `0x104ce5388 cbz w20, ...` ⇒ **确认第 0 参数是 BOOL**（`w20`），且 `x19` 直接当模型用（`buyer_address` 等），
  `x21` 当 error 用 ⇒ 三方与签名一致。

### 1.3 `+[VDTradeConfOrderService confirmOrderCheckRepeatWithRequestDO:confirmOrderDO:result:]`

- IMP：`0x104ccab70`
- type encoding：`v40@0:8@16@24@?32`（`research/service-static/method-addresses.txt:90`）
- 反汇编：`confirm-abi/checkrepeat-disass.txt`
  - `0x104ccab90 mov x21, x4` → result block；`0x104ccabcc str x0,[sp,#0x8]`
  - `0x104ccb0b8 bl j__objc_msgSend(x0, "request:context:")`，`0x104ccb0ac ldr x22,[sp,#0x8]` → `x2` = block
  - **`setResultClass` 出现 0 次，`yy_modelWithDictionary` 出现 0 次**
    ⇒ 与 `confirm` 同构：无模型转换，block 第二参数是 **原始 payload**
- block signature：**静态未能取得独立 descriptor**。
  - 该 selector 在可读静态文本中**无调用方**（`cstring-addresses.txt:177942` 仅有 selector 字符串本身）。
  - 真实调用方链：`-[VDTradeConfOrderViewController createOrderHelp:]` `0x104cddc4c`
    → `0x104cde0f8 bl "checkRepeatOrder:result:"`（`confirm-abi/controller-checkRepeat-callsite.txt:82`）
    → `-[VDTradeConfOrderViewModel checkRepeatOrder:result:]` `0x104ce5508`
    → `0x104ce5b04 bl "confirmOrderCheckRepeatWithRequestDO:confirmOrderDO:result:"`（`confirm-abi/caller-checkRepeatOrder-disass.txt:417`）
  - `checkRepeatOrder:result:` 把**它自己的入参 block `x3` 原样透传**（`0x104ce5540 mov x0,x3` retain → `x19` → `0x104ce5b00 mov x4,x19`），
    中间**不构造** block literal。
  - 该入参 block 由控制器 `createOrderHelp:` 提供，descriptor `0x107819be0` → sig `0x106e1cf5f`
    → `v28@?0B8@12@"WDNErrorDO"20`（`confirm-abi/controller-checkRepeat-callsite.txt:67-68`）
  - 控制器 block 体 `sub_104cde158`（`confirm-abi/controller-checkrepeat-block-invoke.txt`）：
    `0x104cde170 mov x20, x3`（error）、`0x104cde1a0 cbz x20`、`0x104cde1a4 "desc"`、`x19`(第1参数) 当 id 用
  - **第二参数类型直证（关键）**：控制器 block 对 `x19`（即第二参数）发送的全是 **NSDictionary API**
    （`confirm-abi/controller-checkrepeat-block-arg2.txt`）：
    ```
    0x104cde1f4  mov x0, x19
    0x104cde1f8  bl  j__objc_msgSend(x0, "allKeys")            ; ← 字典
    0x104cde210  bl  "containsObject:"
    0x104cde224  bl  "objectForKeyedSubscript:"                  ; ← 字典取值
    0x104cde234  bl  "boolValue"                                 ; 取某 key 的 BOOL
    0x104cde22c  retain / 0x104cde248 release
    ```
    ⇒ `checkRepeat` 的第二参数在真实调用方侧被当 **NSDictionary** 消费，
    与「无 resultClass、原样透传 payload」的静态判定完全一致，**不是** `VDTradeConfirmOrderDO` 模型。
  - **判定**：签名 = `v28@?0B8@12@"WDNErrorDO"20`，即 `void(^)(BOOL, id, WDNErrorDO *)`。
    这是**间接确证**（经由两个转发层），非本 selector 直连 descriptor；
    但第二参数的**运行时类型（字典）已由调用方 API 使用方式直证**。

---

## 2. 为什么第二参数不是 confirmOrderDO 模型（关键判定）

`WDNetworkContext` 只在 `resultClass != nil` 时做模型转换：

`research/service-static/network-tail-disass.txt:24-98`（`-[WDNHttpThorHandler thorSuccess:context:]`）
```
0x105832ab8  bl "resultClass"        ; context.resultClass
0x105832abc  cbz x0, loc_105832b70   ; ← nil 则跳转
...
0x105832b70  ; loc_105832b70         ; resultClass == nil 分支
0x105832b70  mov x0, x19
0x105832b74  bl  j__objc_retain     ; 原样 retain payload（原始 JSON→NSDictionary/NSArray/NSString）
0x105832b78  ; loc_105832b78
0x105832b7c  mov x0, x20
0x105832b80  mov w2, #0x1            ; type = 1 (success)
0x105832b84  mov x3, x21             ; objectData
0x105832b88  bl  "fireEventWithType:objectData:"
```
`resultClass` 非 nil 时才 `yy_modelWithDictionary:`（`0x105832b4c`）或 `yy_modelArrayWithClass:json:`（`0x105832af8`）。

`fireEventWithType:objectData:` 的调用形式（`confirm-abi/fireEvent-block-disass.txt`）：
```
sub_105831220:
0x105831230  ldr x0, [x0, #0x30]   ; listener block
0x105831234  ldp x1, x2, [x19, #0x20]  ; x1 = context, x2 = objectData
0x105831238  ldr x8, [x0, #0x10]   ; invoke
0x10583123c  blr x8                ; listener(context, objectData)
```
⇒ listener 恒以 `(context, data)` 两参调用，`WDNHttpThorHandler` 的 listener descriptor 签名
`v24@?0@"WDNetworkContext"8@16`（`confirm-abi/success-listener-descriptor.txt`，sig `0x106a80d93`）
印证 `request:context:` 的 listener 是 `(WDNetworkContext *, id)`。

失败路径：`0x1058330a8 mov w2,#0x2` / `0x1058330ac mov x3,x26` / `0x1058330b0 bl "fireEventWithType:objectData:"`
（`network-tail-disass.txt:433-436`），`x26` 是 `WDNErrorDO`（`serverErrorWithCode:msg:` 构造），
listener descriptor `0x10768abe8` → sig `v24@?0@"WDNetworkContext"8@"WDNErrorDO"16`（`confirm-abi/failed-listener-descriptor.txt`）。

`request:context:` 的 trampoline 直接证明 block 调用形（`confirm-abi/request-context-disass.txt:85-104`）：
```
sub_104cd02bc:                     ; success trampoline
0x104cd02bc  ldr x0, [x0, #0x20]   ; captured block
0x104cd02c0  cbz x0, ret
0x104cd02c4  ldr x4, [x0, #0x10]   ; invoke
0x104cd02c8  mov w1, #0x1          ; BOOL = 1  (success)
0x104cd02cc  mov x3, #0            ; error = nil
0x104cd02d0  br  x4                ; block(context, 1, nil)   ← x2 = context 原样保留
sub_104cd02d8:                     ; failed trampoline
0x104cd02e0  mov x3, x2            ; error = data
0x104cd02e8  mov w1, #0            ; BOOL = 0
0x104cd02ec  mov x2, #0            ; context = nil
0x104cd02f0  br  x4                ; block(nil, 0, error)
```
⇒ **三个方法转发出去的 result block 的精确调用形**：
- 成功：`block(context, payload, nil)`，其中 `w1 = 1`
- 失败：`block(nil, nil, error)`，其中 `w1 = 0`

因此 `v28@?0B8@12@"WDNErrorDO"20` 的 ARM64 映射：
`x0`=block, `w1`=BOOL success, `x2`=id（成功=payload / 失败=nil）, `x3`=WDNErrorDO*（成功=nil / 失败=error）。

---

## 3. ARM64 参数映射（逐 selector）

### `+confirmOrderWithRequestDO:result:` @ `0x104ccb140`
| 位置 | 含义 |
|---|---|
| `x0` | `self` = `VDTradeConfOrderService` class |
| `x1` | `_cmd` = `confirmOrderWithRequestDO:result:` |
| `x2` | `VDTradeConfOrderRequestDO *requestDO` |
| `x3` | `void(^)(BOOL, id, WDNErrorDO *)` result block |

result block 被调用时：
| 位置 | 含义 |
|---|---|
| `x0` | block |
| `w1` | `BOOL success` |
| `x2` | 成功：`NSDictionary`（原始 response payload）；失败：`nil` |
| `x3` | 成功：`nil`；失败：`WDNErrorDO *` |

### `+reconfirmOrderRequestDO:confirmOrderDO:result:` @ `0x104ccb49c`
| 位置 | 含义 |
|---|---|
| `x2` | `requestDO` |
| `x3` | `VDTradeConfirmOrderDO *confirmOrderDO`（`0x104ccb4c0 mov x20, x3`） |
| `x4` | result block（`0x104ccb4bc mov x21, x4`） |

result block 被调用时：`w1` = BOOL，`x2` = **`VDTradeConfirmOrderDO *`（模型，因 resultClass 已设）**，`x3` = `WDNErrorDO *`

### `+confirmOrderCheckRepeatWithRequestDO:confirmOrderDO:result:` @ `0x104ccab70`
| 位置 | 含义 |
|---|---|
| `x2` | `requestDO` |
| `x3` | `confirmOrderDO` |
| `x4` | result block（`0x104ccab90 mov x21, x4`） |

result block 被调用时：`w1` = BOOL，`x2` = **原始 payload（NSDictionary，无模型转换）**，`x3` = `WDNErrorDO *`
> 类型直证：控制器 block 对 `x2` 发 `allKeys` / `objectForKeyedSubscript:` / `containsObject:`，
> 见 `confirm-abi/controller-checkrepeat-block-arg2.txt` 与 §1.3。

---

## 4. 对「预热」的直接影响

1. **`confirmOrderWithRequestDO:result:` 拿不到确认模型。**
   block 第二参数是原始 response 字典。要得到 `VDTradeConfirmOrderDO` 必须自己转换，
   且转换方式已由真实调用方固定（`confirm-abi/caller-requestConfirmOrder-disass.txt:65-71`）：
   ```
   0x104ce4c74  bl "yy_modelWithDictionary:"   ; VDTradeConfirmOrderDO
   0x104ce4c90  bl "yy_modelWithDictionary:"   ; 第二次（preConfirmOrderDO）
   ```
   注意它**连续调用两次** `yy_modelWithDictionary:` 生成两个独立实例，
   分别落到 `_confirmOrderDO`（`[x22,#0x20]`）与 `_preConfirmOrderDO`（`[x22,#0x18]`，`0x104ce4d44`）。
2. **`reconfirmOrderRequestDO:confirmOrderDO:result:` 第二参数是模型**（`VDTradeConfirmOrderDO *`），
   因其内部设置了 `resultClass`，可直接当模型消费。
3. **`confirmOrderCheckRepeatWithRequestDO:confirmOrderDO:result:` 第二参数同样是原始 payload**，
   与 `confirm` 一致，需自行 `yy_modelWithDictionary:`。
   该点已由真实调用方**直证**：控制器 block 对第二参数发 `allKeys` / `objectForKeyedSubscript:` /
   `containsObject:`（`confirm-abi/controller-checkrepeat-block-arg2.txt:1-12`），是 NSDictionary 用法。
4. 失败分支三者统一：`block(nil, nil, WDNErrorDO *)`，`w1 = 0`。
   即**失败时第二参数必为 nil**，预热实现不能假设非空。
5. 成功分支 `w1 = 1` 且 `x3 = nil`（trampoline `0x104cd02cc mov x3, #0`）。

---

## 5. 未确证项（明确标注）

- `confirmOrderCheckRepeatWithRequestDO:confirmOrderDO:result:` 的 block signature **不是**由该 selector 自身的
  block literal descriptor 直接取得的；本样本中该 selector 无 block literal、无直接静态调用方。
  其签名 `v28@?0B8@12@"WDNErrorDO"20` 来自控制器 `createOrderHelp:` 提供的 block（descriptor `0x107819be0`）
  经 `checkRepeatOrder:result:` 两层原样透传。若需 100% 直连证据，需运行时抓取，本次为静态分析，**未做**。
  （注：该 block 第二参数的**运行时类型**已由调用方 API 用法直证为 NSDictionary，见 §1.3；
  未直证的是 descriptor 归属链路的直接性。）
- `confirmOrderWithRequestDO:result:` 的 block 第二参数**运行时具体 class**
  （`NSDictionary` vs `NSArray` vs `NSString`）取决于服务端 JSON 顶层类型，静态无法判定；
  但可确定**不是** `VDTradeConfirmOrderDO` 模型对象。
- `thorSuccess:` 中 `resultClass == nil` 时 payload 是否再经过 `WDNHttpVapInfo` 层加工，
  未逐层追踪到 `NSJSONSerialization`；本次只确证到「不做 yy_model 转换、原样 retain 透传」。

---

## 6. 证据文件清单

| 文件 | 内容 |
|---|---|
| `confirm-abi/confirm-disass.txt` | `confirmOrderWithRequestDO:result:` 全量反汇编 |
| `confirm-abi/reconfirm-disass.txt` | `reconfirmOrderRequestDO:confirmOrderDO:result:` 全量反汇编 |
| `confirm-abi/checkrepeat-disass.txt` | `confirmOrderCheckRepeatWithRequestDO:confirmOrderDO:result:` 全量反汇编 |
| `confirm-abi/request-context-disass.txt` | `request:context:` 及 success/failed trampoline |
| `confirm-abi/fireEvent-disass.txt` / `fireEvent-block-disass.txt` | `fireEventWithType:objectData:` 及分发 block |
| `confirm-abi/addlistener-disass.txt` | listener 类型常量（success=1, failed=2） |
| `confirm-abi/success-listener-descriptor.txt` | success listener descriptor `0x10768abb8` → sig `0x106a80d93` |
| `confirm-abi/failed-listener-descriptor.txt` | failed listener descriptor `0x10768abe8` → sig `0x106a79702` |
| `confirm-abi/signature-strings.txt` | 三条 signature 字符串原文 |
| `confirm-abi/caller-block-descriptor.txt` | 调用方 block descriptor `0x107818630` |
| `confirm-abi/caller-reconfirm-descriptor.txt` | 调用方 block descriptor `0x107818690` |
| `confirm-abi/caller-requestConfirmOrder-disass.txt` | `requestConfirmOrder:` + block 体 `sub_104ce4c2c` |
| `confirm-abi/caller-requestReConfirmOrder-disass.txt` | `requestReConfirmOrder:` |
| `confirm-abi/caller-reconfirm-block-body.txt` | reconfirm 调用方 block 体 |
| `confirm-abi/caller-checkRepeatOrder-disass.txt` | `checkRepeatOrder:result:` 全量 |
| `confirm-abi/controller-checkRepeat-callsite.txt` | 控制器 `createOrderHelp:` 内 callsite + descriptor |
| `confirm-abi/controller-checkrepeat-block-invoke.txt` | 控制器 block 体 `sub_104cde158` |
| `confirm-abi/controller-checkrepeat-block-arg2.txt` | 控制器 block 对第二参数发 `allKeys`/`objectForKeyedSubscript:` —— 字典直证 |
| `confirm-abi/controller-block-body.txt` | `create` 的控制器 block copy/dispose helper |
