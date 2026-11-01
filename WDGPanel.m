#import "WDGCore.h"
#import "WDGCart.h"
#import "WDGOrderService.h"

@interface WDGPassWindow : UIWindow @end
@implementation WDGPassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    if(hit==self||hit==self.rootViewController.view)return nil;
    return hit;
}
@end

@interface WDGPanel : NSObject
@property (nonatomic,strong) WDGPassWindow *window;
@property (nonatomic,weak) UIWindow *previousKey;
@property (nonatomic,strong) UIButton *bubble;
@property (nonatomic,strong) UIView *card;
@property (nonatomic,strong) UILabel *stateLabel;
@property (nonatomic,strong) UILabel *sampleLabel;
@property (nonatomic,strong) UILabel *noticeLabel;
@property (nonatomic,strong) UILabel *countdownLabel;
@property (nonatomic,strong) UIButton *captureButton;
@property (nonatomic,strong) UIButton *payButton;
@property (nonatomic,strong) UIButton *validateButton;
@property (nonatomic,strong) UITextField *maximumAmount;
@property (nonatomic,strong) UISegmentedControl *action;
@property (nonatomic,strong) UIDatePicker *datePicker;
@property (nonatomic,strong) NSNumber *payType;
@property (nonatomic,strong) NSTimer *refreshTimer;
@property (nonatomic,copy) NSString *shownSample;
+ (instancetype)shared;
- (void)ensureWindow;
@end

@implementation WDGPanel
+ (instancetype)shared {static WDGPanel *p;static dispatch_once_t once;dispatch_once(&once,^{p=[WDGPanel new];});return p;}
- (instancetype)init {
    if((self=[super init])){
        NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [nc addObserver:self selector:@selector(inactive:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [nc addObserver:self selector:@selector(changed:) name:WDGStateDidChange object:nil];
    }
    return self;
}
- (void)active:(NSNotification *)n {[self ensureWindow];}
- (void)inactive:(NSNotification *)n {[self closePanel];self.window.hidden=YES;}
- (void)changed:(NSNotification *)n {[self refresh];}
- (UIButton *)button:(NSString *)title action:(SEL)selector identifier:(NSString *)identifier {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    b.backgroundColor=[UIColor colorWithWhite:0.94 alpha:1];b.layer.cornerRadius=9;
    [b.heightAnchor constraintGreaterThanOrEqualToConstant:38].active=YES;
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    b.accessibilityIdentifier=identifier;return b;
}
- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l=[UILabel new];l.numberOfLines=0;l.font=[UIFont systemFontOfSize:size weight:weight];l.textColor=UIColor.labelColor;return l;
}
- (void)ensureWindow {
    NSAssert(NSThread.isMainThread,@"overlay uses main thread");
    UIApplication *app=UIApplication.sharedApplication;
    if(app.applicationState!=UIApplicationStateActive)return;
    if(self.window){self.window.hidden=NO;return;}
    UIWindowScene *scene=nil;
    for(UIScene *s in app.connectedScenes){if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive){scene=(UIWindowScene *)s;break;}}
    WDGPassWindow *w=scene?[[WDGPassWindow alloc] initWithWindowScene:scene]:[[WDGPassWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    w.frame=UIScreen.mainScreen.bounds;w.backgroundColor=UIColor.clearColor;w.windowLevel=UIWindowLevelAlert+2;
    UIViewController *vc=[UIViewController new];vc.view.backgroundColor=UIColor.clearColor;w.rootViewController=vc;self.window=w;
    self.bubble=[UIButton buttonWithType:UIButtonTypeSystem];
    self.bubble.frame=CGRectMake(w.bounds.size.width-64,MAX(140,w.bounds.size.height*0.3),48,48);
    self.bubble.layer.cornerRadius=24;self.bubble.layer.shadowOpacity=0.2;self.bubble.layer.shadowRadius=4;
    self.bubble.backgroundColor=[UIColor colorWithRed:0.91 green:0.16 blue:0.30 alpha:0.94];
    [self.bubble setTitle:@"微助" forState:UIControlStateNormal];[self.bubble setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.bubble.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    self.bubble.accessibilityLabel=@"微店助手，打开面板";self.bubble.accessibilityIdentifier=@"WDG.FloatingButton";
    [self.bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.bubble addGestureRecognizer:pan];[vc.view addSubview:self.bubble];w.hidden=NO;
    [WDGCore.shared recordEvent:@"overlay_ready" details:@{@"version":WDGVersion,@"build":WDGBuildID}];
}
- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint d=[g translationInView:self.window];
    CGPoint c=self.bubble.center;
    CGFloat insetTop=MAX(self.window.safeAreaInsets.top,24)+24;
    self.bubble.center=CGPointMake(MIN(MAX(c.x+d.x,26),self.window.bounds.size.width-26),MIN(MAX(c.y+d.y,insetTop),self.window.bounds.size.height-MAX(self.window.safeAreaInsets.bottom,20)-26));
    [g setTranslation:CGPointZero inView:self.window];
    if(g.state==UIGestureRecognizerStateEnded){CGPoint dest=self.bubble.center;dest.x=dest.x<self.window.bounds.size.width/2?28:self.window.bounds.size.width-28;[UIView animateWithDuration:0.2 animations:^{self.bubble.center=dest;}];}
}
- (void)togglePanel {if(self.card&&!self.card.hidden)[self closePanel];else [self openPanel];}
- (void)openPanel {
    [self ensureWindow];if(!self.window)return;
    WDGRefreshTradeSnapshot();
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if(w.isKeyWindow&&w!=self.window) self.previousKey=w;
    }
    if (!self.previousKey) {
        id<UIApplicationDelegate> delegate=UIApplication.sharedApplication.delegate;
        if ([delegate respondsToSelector:@selector(window)]) self.previousKey=delegate.window;
    }
    if(!self.card)[self buildCard];
    self.card.hidden=NO;self.bubble.hidden=YES;
    [self.window makeKeyWindow];
    if(self.datePicker.date.timeIntervalSinceNow<2)self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:60];
    self.refreshTimer=[NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];
    [self refresh];
}
- (void)closePanel {
    self.card.hidden=YES;self.bubble.hidden=NO;[self.refreshTimer invalidate];self.refreshTimer=nil;
    [self.previousKey makeKeyWindow];self.previousKey=nil;
}
- (void)buildCard {
    UIView *root=self.window.rootViewController.view;
    self.card=[UIView new];self.card.backgroundColor=UIColor.systemBackgroundColor;self.card.layer.cornerRadius=18;
    self.card.layer.shadowOpacity=0.25;self.card.layer.shadowRadius=12;self.card.translatesAutoresizingMaskIntoConstraints=NO;
    [root addSubview:self.card];
    [NSLayoutConstraint activateConstraints:@[[self.card.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],[self.card.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],[self.card.widthAnchor constraintEqualToConstant:MIN(380,self.window.bounds.size.width-24)],[self.card.heightAnchor constraintEqualToConstant:MIN(690,self.window.bounds.size.height-100)]]];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.card addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:14],[scroll.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-14],[scroll.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],[scroll.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16]]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *title=[self label:19 weight:UIFontWeightBold];title.text=@"微店助手";[stack addArrangedSubview:title];
    self.stateLabel=[self label:11 weight:UIFontWeightRegular];[stack addArrangedSubview:self.stateLabel];
    self.captureButton=[self button:@"自动采集" action:@selector(toggleCapture) identifier:@"WDG.CaptureToggle"];[stack addArrangedSubview:self.captureButton];
    self.sampleLabel=[self label:12 weight:UIFontWeightRegular];self.sampleLabel.accessibilityIdentifier=@"WDG.SampleSummary";[stack addArrangedSubview:self.sampleLabel];
    [stack addArrangedSubview:[self button:@"选择购物车目标（含未开售商品）" action:@selector(chooseCartTarget) identifier:@"WDG.CartTarget"]];
    self.action=[[UISegmentedControl alloc] initWithItems:@[@"到点提醒",@"本地演练",@"购物车直提"]];self.action.selectedSegmentIndex=1;
    [self.action addTarget:self action:@selector(actionChanged) forControlEvents:UIControlEventValueChanged];self.action.accessibilityIdentifier=@"WDG.Action";[stack addArrangedSubview:self.action];
    self.datePicker=[UIDatePicker new];self.datePicker.datePickerMode=UIDatePickerModeDateAndTime;self.datePicker.preferredDatePickerStyle=UIDatePickerStyleCompact;
    self.datePicker.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];self.datePicker.timeZone=NSTimeZone.localTimeZone;
    self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:60];self.datePicker.accessibilityIdentifier=@"WDG.FireAt";[stack addArrangedSubview:self.datePicker];
    self.maximumAmount=[UITextField new];self.maximumAmount.borderStyle=UITextBorderStyleRoundedRect;
    self.maximumAmount.placeholder=@"最高实付金额（含运费），例如 99.00";
    self.maximumAmount.keyboardType=UIKeyboardTypeDecimalPad;self.maximumAmount.accessibilityIdentifier=@"WDG.MaximumTotal";
    self.maximumAmount.accessibilityLabel=@"最高实付金额，含运费";[stack addArrangedSubview:self.maximumAmount];
    self.payButton=[self button:@"支付方式：采用微店已选方式" action:@selector(selectPayType) identifier:@"WDG.PayType"];[stack addArrangedSubview:self.payButton];
    self.validateButton=[self button:@"校验参数（不联网）" action:@selector(validateCartParameters) identifier:@"WDG.ValidateCartParameters"];[stack addArrangedSubview:self.validateButton];
    [self actionChanged];
    [stack addArrangedSubview:[self button:@"设置定时任务" action:@selector(schedule) identifier:@"WDG.ArmTask"]];
    [stack addArrangedSubview:[self button:@"5 秒本地演练（不发请求）" action:@selector(localTest) identifier:@"WDG.DryRun5Seconds"]];
    self.countdownLabel=[self label:14 weight:UIFontWeightSemibold];self.countdownLabel.accessibilityIdentifier=@"WDG.Countdown";[stack addArrangedSubview:self.countdownLabel];
    [stack addArrangedSubview:[self button:@"取消当前任务" action:@selector(cancel) identifier:@"WDG.CancelTask"]];
    self.noticeLabel=[self label:11 weight:UIFontWeightRegular];self.noticeLabel.textColor=UIColor.secondaryLabelColor;
    self.noticeLabel.text=@"提前五秒预热确认数据，到点校验商品、最高实付金额及服务端状态后直提一次。仅保持微店前台时保证执行；后台或锁屏会停止尚未发出的创建请求。已发请求继续核对结果，本地取消不代表撤单。不打开支付链接。";[stack addArrangedSubview:self.noticeLabel];
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[[self button:@"清空采集" action:@selector(clear) identifier:@"WDG.ClearSnapshot"],[self button:@"导出诊断" action:@selector(export) identifier:@"WDG.Export"]]];row.axis=UILayoutConstraintAxisHorizontal;row.distribution=UIStackViewDistributionFillEqually;row.spacing=10;[stack addArrangedSubview:row];
    [stack addArrangedSubview:[self button:@"收起悬浮面板" action:@selector(closePanel) identifier:@"WDG.ClosePanel"]];
}
- (void)refresh {
    if(!self.card)return;
    NSDictionary *s=WDGCore.shared.status;NSDictionary *snapshot=s[@"snapshot"],*task=s[@"task"];
    self.stateLabel.text=[NSString stringWithFormat:@"v%@ · %@ · %@",s[@"version"],s[@"build"],[s[@"ioError"] length]?s[@"ioError"]:@"沙盒存储正常"];
    [self.captureButton setTitle:[s[@"captureEnabled"] boolValue]?@"自动采集：开启（点击暂停）":@"自动采集：暂停（点击开启）" forState:UIControlStateNormal];
    if(![self.shownSample isEqual:snapshot[@"sampleKey"]]){self.payType=nil;self.shownSample=snapshot[@"sampleKey"];[self.payButton setTitle:@"支付方式：采用微店已选方式" forState:UIControlStateNormal];}
    NSMutableArray *lines=[NSMutableArray array];
    NSArray *cartLines=WDGCartSelectedLines();
    if(cartLines.count){
        [lines addObject:[NSString stringWithFormat:@"购物车已选 %lu 件",(unsigned long)cartLines.count]];
        for(NSDictionary *item in cartLines){
            [lines addObject:[NSString stringWithFormat:@"%@ / %@ × %@",item[@"title"]?:item[@"itemRef"]?:@"商品",item[@"skuTitle"]?:item[@"skuRef"]?:@"未选规格",item[@"quantity"]?:@"?"]];
        }
    }
    if(![snapshot[@"items"] count]){
        if(!cartLines.count)[lines addObject:@"未采集到数据。进购物车或确认页停留几秒即可自动采集。"];
    }
    else {
        [lines addObject:[NSString stringWithFormat:@"%@ · %@",snapshot[@"pageKind"]?:@"",snapshot[@"stage"]?:@""]];
        for(NSDictionary *item in snapshot[@"items"]){ [lines addObject:[NSString stringWithFormat:@"%@ / %@ × %@",item[@"title"]?:item[@"itemRef"]?:@"商品",item[@"skuTitle"]?:item[@"skuRef"]?:@"未选规格",item[@"quantity"]?:@"?"]];}
        [lines addObject:[NSString stringWithFormat:@"确认金额：%@",snapshot[@"totalPrice"]?:@"待确认"]];
    }
    self.sampleLabel.text=[lines componentsJoinedByString:@"\n"];
    NSString *state=task[@"state"];
    if([state isEqual:@"armed"]){NSTimeInterval remain=MAX(0,[task[@"dueAt"] doubleValue]-NSDate.date.timeIntervalSince1970);self.countdownLabel.text=[NSString stringWithFormat:@"待执行：%02ld:%02ld:%04.1f",(long)(remain/3600),(long)((NSInteger)(remain/60)%60),fmod(remain,60)];}
    else self.countdownLabel.text=[NSString stringWithFormat:@"%@%@",@{@"idle":@"尚未设置任务",@"firing":@"准备接口参数",@"preheating":@"获取确认数据（尚未下单）",@"waitingSale":@"等待设定开售时刻",@"sending":@"创建接口已发出，等待响应",@"apiSucceeded":@"创建接口返回成功",@"unknown":@"订单结果待核对（不重试）",@"fired":@"本地任务已完成",@"cancelled":@"任务已取消",@"failed":@"接口任务未完成"}[state]?:state,[task[@"reason"] length]?[NSString stringWithFormat:@"\n%@",task[@"reason"]]:@""];
}
- (void)actionChanged {BOOL cart=self.action.selectedSegmentIndex==2;self.payButton.hidden=!cart;self.maximumAmount.hidden=!cart;self.validateButton.hidden=!cart;}
- (void)toggleCapture {WDGCore *c=WDGCore.shared;[c setCaptureEnabled:![c.status[@"captureEnabled"] boolValue]];}
- (void)clear {[WDGCore.shared clearSnapshot];}
- (void)cancel {[WDGCore.shared cancelTask:@"用户在悬浮面板取消"];}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)localTest {
    self.action.selectedSegmentIndex=1;[self actionChanged];NSError *error=nil;
    if(![WDGCore.shared armAt:[NSDate dateWithTimeIntervalSinceNow:5] action:@"dryRun" payType:nil error:&error])[self alert:@"任务未设置" message:error.localizedDescription];
}
- (void)selectPayType {
    [self alert:@"支付方式由微店确认结果决定" message:@"助手采用服务端当前选中且可用的唯一按钮，不猜数字参数。它可能对应极速支付；请先在微店设置你希望使用的支付方式。若按钮有歧义，任务停止。"];
}
- (void)chooseCartTarget {
    NSArray *candidates=[[NSArray alloc] initWithArray:WDGCartCandidates() copyItems:YES];
    if(!candidates.count){[self alert:@"尚未采集购物车" message:@"先在购物车页刷新一次。开售前的商品也可以在这里选择。 "];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择购物车目标" message:@"只选择待提交商品，不修改 App 购物车，不发订单。" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"使用购物车已勾选的商品" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){
        if(![candidates isEqual:WDGCartCandidates()]){[self alert:@"购物车已更新" message:@"请重新打开选择框核对已勾选商品。"];return;}
        WDGCartChooseLine(nil);[self refresh];
    }]];
    for(NSDictionary *line in candidates){
        NSString *lineKey=[line[@"lineKey"] copy];NSDictionary *raw=[WDGCartRawLine(lineKey) copy];
        NSString *title=[NSString stringWithFormat:@"%@ · %@ × %@",line[@"title"]?:@"商品",line[@"skuTitle"]?:@"未选规格",line[@"quantity"]?:@"?"];
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){
            if(!raw||![raw isEqual:WDGCartRawLine(lineKey)]||!WDGCartChooseLine(lineKey)){[self alert:@"商品已更新" message:@"请重新打开选择框核对商品、规格和数量。"];return;}
            [self refresh];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.card;a.popoverPresentationController.sourceRect=self.card.bounds;
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (NSDecimalNumber *)maximumValue {
    NSString *text=[self.maximumAmount.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"\\A[0-9]+(?:\\.[0-9]{1,2})?\\z" options:0 error:NULL];
    if(!text.length||[pattern numberOfMatchesInString:text options:0 range:NSMakeRange(0,text.length)]!=1){[self alert:@"请确认最高实付金额" message:@"输入含运费的最高金额，例如 99.00；确认金额超过它就不提交。"];return nil;}
    NSDecimalNumber *maximum=[NSDecimalNumber decimalNumberWithString:text locale:@{NSLocaleDecimalSeparator:@"."}];
    if([maximum isEqual:NSDecimalNumber.notANumber]||[maximum compare:NSDecimalNumber.zero]!=NSOrderedDescending){[self alert:@"金额格式有误" message:@"最高金额应大于零，最多保留两位小数。"];return nil;}
    return maximum;
}
- (void)validateCartParameters {
    NSDecimalNumber *maximum=[self maximumValue];if(!maximum)return;
    NSDate *date=[self.datePicker.date copy];
    if(date.timeIntervalSinceNow<2||date.timeIntervalSinceNow>43200){[self alert:@"请选择校验时间" message:@"请选择未来 2 秒至 12 小时内的时间。仅校验参数，不设置定时任务。"];return;}
    NSString *key=[WDGCartSnapshotKey() copy];
    if(!key.length){[self alert:@"请先选择购物车目标" message:@"进入购物车采集数据，再明确选择目标商品。"];return;}
    NSError *error=nil;
    id request=WDGCartBuildRequest(&error);
    WDGOrderService *service=request?[WDGOrderService preparePreheatRequest:request sampleKey:key payType:nil error:&error]:nil;
    if(![key isEqual:WDGCartSnapshotKey()]){[self alert:@"目标已变化" message:@"请重新选择商品后校验。"];return;}
    if(!service||![service configureCartDueAt:date maximumTotal:maximum error:&error]){[self alert:@"本地校验未通过" message:error.localizedDescription?:@"请检查购物车商品、模型及金额参数。"];return;}
    [self.card endEditing:YES];
    [self alert:@"本地参数校验成功" message:[NSString stringWithFormat:@"已构建购物车请求并校验预热服务及最高实付金额 %@。采用微店已选方式。\n\n未联网，未设置任务，未调用确认或创建订单接口。地址、运费和最终金额仍需服务端确认。",maximum.stringValue]];
}
- (void)schedule {
    NSInteger index=self.action.selectedSegmentIndex;if(index<0||index>2)return;
    NSString *action=@[@"reminder",@"dryRun",@"preheatOnce"][index];
    NSDate *date=[self.datePicker.date copy];
    if(![action isEqual:@"preheatOnce"]){NSError *error=nil;if(![WDGCore.shared armAt:date action:action payType:nil error:&error])[self alert:@"任务未设置" message:error.localizedDescription];return;}
    NSDecimalNumber *maximum=[self maximumValue];if(!maximum)return;
    [self.card endEditing:YES];
    NSArray *lines=[[NSArray alloc] initWithArray:WDGCartSelectedLines() copyItems:YES];
    NSString *key=[WDGCartSnapshotKey() copy];
    NSArray *lineKeys=[[lines valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];
    NSString *reason=nil;
    if(!lines.count||!key.length){[self alert:@"请先打开购物车" message:@"购物车预热需要先采集并明确选择商品，请进入购物车页后回来。"];return;}
    if(![WDGOrderService preheatReady:&reason]){[self alert:@"预热接口未就绪" message:reason?:@"接口不可用"];return;}
    NSDateFormatter *df=[NSDateFormatter new];df.dateFormat=@"yyyy-MM-dd HH:mm:ss ZZZZ";df.timeZone=self.datePicker.timeZone?:NSTimeZone.localTimeZone;
    NSMutableString *review=[NSMutableString stringWithFormat:@"购物车 %lu 个条目：\n",(unsigned long)lines.count];
    for(NSDictionary *line in lines){
        [review appendFormat:@"· %@ / %@ × %@\n",line[@"title"]?:@"商品",line[@"skuTitle"]?:@"未选规格",line[@"quantity"]?:@"?"];
    }
    [review appendFormat:@"\n执行时间：%@\n时区：%@\n最高实付金额（含运费）：%@\n支付方式：采用微店已选方式\n\n提前五秒预热，到点校验后通过 Service 创建一次订单。可能产生订单及已选支付方式的服务端效果。请保持微店前台；已发请求的本地取消不代表撤单。",[df stringFromDate:date],df.timeZone.name,maximum.stringValue];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认购物车预热直提" message:review preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确认以上商品、时间及最高金额" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *v){
        NSArray *currentKeys=[[WDGCartSelectedLines() valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];
        if(![key isEqual:WDGCartSnapshotKey()]||![lineKeys isEqual:currentKeys]){[self alert:@"购物车目标已变化" message:@"商品、规格、数量或目标行已更新，请重新核对并设置任务。"];return;}
        NSError *error=nil;
        if(![WDGCore.shared armCartAt:date maximumTotal:maximum error:&error])[self alert:@"任务未设置" message:error.localizedDescription];
    }]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)export {
    NSError *error=nil;NSString *file=[WDGCore.shared exportReport:&error];
    if(!file){[self alert:@"导出失败" message:error.localizedDescription?:@"请查看诊断状态"];return;}
    UIActivityViewController *vc=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:file]] applicationActivities:nil];
    vc.popoverPresentationController.sourceView=self.card;vc.popoverPresentationController.sourceRect=self.card.bounds;
    [self.window.rootViewController presentViewController:vc animated:YES completion:nil];
}
@end

void WDGShowOverlay(void) {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WDGShowOverlay();});return;}
    [[WDGPanel shared] ensureWindow];
}
