# WDTN 对时更新：只读静态核实

结论：已定位 `WDTNServerClockProofreader.updateServerTime:` 的真实调用点 **0x1058785d0**。它位于 `-[WDTNNetworkManager thor_processData:task:response:cfError:reSendBlock:callback:]` 的 **业务 `status.code == 40` 校正分支**，输入是解析后响应的 **`result.serverTime`**。本地实现把该数值当作 Unix epoch 毫秒；该字段只是一次响应提供的时间样本，静态证据没有证明它等于调用瞬间的远端实时时钟。

本轮只分析本地样本及已有 `.a2s`，未连接设备、未发送网络请求、未读取密钥值、未修改业务代码。Catalog 无适用逆向技能，未加载 Office 或 ACL 技能。所有新增文件均为本目录报告和必要反汇编。

## 五组关键证据

1. **从网络响应到业务容器。** 方法起点 **0x105877f6c**；在 `cfError == nil` 后，**0x105878074** 调用 `WDTNThorResponseProcessor.parseForResponse:data:config:error:`，解析对象先验证为 `NSDictionary`。**0x105878114 / 0x105878134** 分别加载 CFString **0x107865478 = `status`**、**0x107867b18 = `result`**。`status` 为字典后，**0x105878320** 使用 **0x107869238 = `code`** 并经 `integerValue` 读取。Thor 响应解析器还要求 HTTP **200** 才走正常解析；这里的 40 是业务码，非 HTTP 状态。
   证据：[thor-processData-disass.txt](<C:/Users/Krylov/Documents/deepseek-harness/default-workspace/tools/weidian-grab/research/clock-evidence/thor-processData-disass.txt#L58>)；[thor-response-disass.txt](<C:/Users/Krylov/Documents/deepseek-harness/default-workspace/tools/weidian-grab/research/clock-evidence/thor-response-disass.txt#L23>)。

2. **字段与真实 receiver。** **0x10587849c–0x105878528** 验证 `result` 为字典、取 CFString **0x1078a3ab8 = `serverTime`**、确认支持 `longLongValue` 后读取。其原始 CFString 指针编码为 `0x20000006bf5d70`，对应字符串地址 **0x106bf5d70**、长度 10。**0x1058785a8** 比较业务码 `0x28`；相等时 **0x1058785b0–0x1058785c4** 明确取 `WDTNServerClockProofreader.sharedInstance`，**0x1058785cc** 把原始 long long 放入 x2，**0x1058785d0** 调用 `updateServerTime:`。此处没有秒/毫秒缩放。字段缺失或不支持转换时，前置分支把输入置 **0**，随后 code40 分支仍可调用更新；未见正值或合理日期范围校验。
   证据：[update-caller-disass.txt](<C:/Users/Krylov/Documents/deepseek-harness/default-workspace/tools/weidian-grab/research/clock-evidence/update-caller-disass.txt#L27>)。

3. **校正后续。** 更新调用后 **0x1058785f4** 进入 `thor_completeWithCode40:result:reSendBlock:callback:`（起点 **0x105878d8c**）。该方法在 **0x105878ddc–0x105878df8** 检查并增加 `verifyTimes`，然后 **0x105878e0c** 执行既有 reSendBlock；计数超过 2 时走 callback。这是观察到的原应用校正/重发逻辑，本轮未执行或改动该逻辑。
   证据：[code40-disass.txt](<C:/Users/Krylov/Documents/deepseek-harness/default-workspace/tools/weidian-grab/research/clock-evidence/code40-disass.txt#L22>)。

4. **单位与时间语义。** 更新方法 **0x10587bf04** 于 **0x10587bf4c** 异步提交 block；block **0x10587bf5c** 先在 **0x10587bf78** 原样保存 `serverTimeMS`，再于 **0x10587bf98–0x10587bfc8** 计算 `timeOffsetMS = input - trunc(NSDate.timeIntervalSince1970 * 1000)`。浮点常量 **0x1067eecb0** 已直接读取为 **1000.0**。因此内部契约明确是 epoch 毫秒，而本轮没有实际响应样本可核实服务端生产该字段的精确时刻或数值单位。`currentServerTime` **0x10587bdd8** 每次取本地 epoch 毫秒，block **0x10587becc** 于 **0x10587bef0** 加 offset；`serverTimeMS` 本身则保持最近一次入参的快照值。
   证据：[clock-core-disass.txt](<C:/Users/Krylov/Documents/deepseek-harness/default-workspace/tools/weidian-grab/research/clock-evidence/clock-core-disass.txt#L142>)。

5. **缓存与陈旧性。** `init` **0x10587bbcc** 仅从 NSUserDefaults 恢复 offset（**0x10587bc4c–0x10587bc78**），没有恢复 `serverTimeMS`，故新对象初值为 0 而 offset 可能来自前一进程。更新 block 在 **0x10587c028** 仅缓存 offset。本轮所见路径没有保存样本采集时间/接收时间、TTL、RTT 补偿或顺序版本；code0 正常分支也未更新本对象。offset 可长期沿用，`serverTimeMS > 0` 仅表明发生过一次非零更新，并不说明样本新鲜。由于 local 时间在异步 block 执行时才取，传输、解码和排队延迟会计入 offset 误差；量级未知。设备墙钟调整、跨进程旧 offset、缺失字段写 0 也会影响结果。
   证据：[clock-core-disass.txt](<C:/Users/Krylov/Documents/deepseek-harness/default-workspace/tools/weidian-grab/research/clock-evidence/clock-core-disass.txt#L27>)。

## 覆盖与未知

- 已有缓存解析出 selector 跳板 **0x106272a80** 和 selector ref **0x1080fc6b0**；对 `__text` 的直接 B/BL 扫描找到 **0x1023e6734、0x1023e7654、0x1023f5e30、0x1058785d0**。前三处邻近 EBAppLog 跟踪/配置/注册方法；本轮仅将 receiver 经反汇编明确确认为 WDTNServerClockProofreader 的最后一处计为本对象真实调用，不据此宣称所有动态发送均已穷尽。
- 服务端 `serverTime` 生成时刻、真实响应样本、精确网络误差、活跃进程是否经过 code40、当前缓存 offset 的年龄均未知。
- 读取 `currentServerTime` 会继续前进，但这只证明 `本地墙钟 + 保存的 offset` 的计算行为；新鲜度应由独立观测到的校正事件/时间记录判断，本轮未添加任何运行时观测或代码修改。
