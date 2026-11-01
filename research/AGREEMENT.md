# 0.8.2 协议校验纠正

目标：微店买家 7.9.62 主程序 WDBuyerUniv（已下载样本）。

旧插件错误：直接以 `agreement_info_list.count > 0 && !isAgreementChecked` 停止，并把所有情况称为“新增协议”。原始列表可能包含会被 App 过滤掉的展示项；“新增”一词也无证据。

原生控制器的实际 gate（静态机器码）：

```text
-[VDTradeConfOrderViewController createOrderHelp:] 0x104cddc4c
  0x104cddd40  getRealAgreementInfos
  0x104cddd50  count
  0x104cddd54  cbz -> 继续 checkOrderRepeat
  0x104cddd6c  isAgreementChecked
  0x104cddd8c  tbnz -> 继续
  否则 showAgreementAlertViewIfNeed:
```

新插件调用经过对象返回 ABI 检查的 `getRealAgreementInfos`，仅当筛选结果非空且已确认状态为 false 才提示用户查看交易协议。未知 getter ABI 保持停止，不通过设置 `isAgreementChecked=YES` 来消除提示。

`getRealAgreementInfos`（0x104c943bc）会按协议类型、支付方式和 installment URL 筛选；其内部调用 `shouldShowAgreementInCheckbox`（0x104c960e8）。后者不是控制器的直接 gate，不能额外把其 false 当作所有协议均已同意。`backFillStatus:`（0x104c95518）只从旧模型复制用户已有的勾选状态；显式确认弹层才会设 YES。

新增5个生产集成回归用例：

- 原始列表非空、原生筛选结果为空：正常继续。
- 原生筛选非空、用户未确认：不创建订单。
- 原生筛选非空且已确认：正常继续。
- checkbox 展示 helper 为 false，但筛选结果仍非空：仍遵循原生 gate，不漏拦。
- 筛选 getter ABI 未知：不调用未知函数，不创建订单。

可复现查看：

```powershell
& tools/ipsw/ipsw.exe macho disass tools/weidian-grab/WDBuyerUniv.bin --vaddr 0x104cddc4c
& tools/ipsw/ipsw.exe macho disass tools/weidian-grab/WDBuyerUniv.bin --vaddr 0x104c943bc
& tools/ipsw/ipsw.exe macho disass tools/weidian-grab/WDBuyerUniv.bin --vaddr 0x104c960e8
```

真机旧版此次任务已记录为 failed，reason 为旧协议提示，停止在确认数据检查阶段。这不是订单创建成功，也不是来自微店的“新增协议”报错文案。
