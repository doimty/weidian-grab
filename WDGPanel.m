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
    self.action=[[UISegmentedControl alloc] initWithItems:@[@"到点提醒",@"本地演练",@"购物车预热"]];self.action.selectedSegmentIndex=1;
    [self.action addTarget:self action:@selector(actionChanged) forControlEvents:UIControlEventValueChanged];self.action.accessibilityIdentifier=@"WDG.Action";[stack addArrangedSubview:self.action];
    self.datePicker=[UIDatePicker new];self.datePicker.datePickerMode=UIDatePickerModeDateAndTime;self.datePicker.preferredDatePickerStyle=UIDatePickerStyleCompact;
    self.datePicker.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];self.datePicker.timeZone=NSTimeZone.localTimeZone;
    self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:60];self.datePicker.accessibilityIdentifier=@"WDG.FireAt";[stack addArrangedSubview:self.datePicker];
    self.payButton=[self button:@"选择已采集支付参数" action:@selector(selectPayType) identifier:@"WDG.PayType"];[stack addArrangedSubview:self.payButton];self.payButton.hidden=YES;
    [stack addArrangedSubview:[self button:@"设置定时任务" action:@selector(schedule) identifier:@"WDG.ArmTask"]];
    [stack addArrangedSubview:[self button:@"5 秒本地演练（不发请求）" action:@selector(localTest) identifier:@"WDG.DryRun5Seconds"]];
    self.countdownLabel=[self label:14 weight:UIFontWeightSemibold];self.countdownLabel.accessibilityIdentifier=@"WDG.Countdown";[stack addArrangedSubview:self.countdownLabel];
    [stack addArrangedSubview:[self button:@"取消当前任务" action:@selector(cancel) identifier:@"WDG.CancelTask"]];
    self.noticeLabel=[self label:11 weight:UIFontWeightRegular];self.noticeLabel.textColor=UIColor.secondaryLabelColor;
    self.noticeLabel.text=@"POST vbuy/CreateOrder/1.0 · 接口直提。悬浮面板只配置任务，不执行页面点击。保持 App 前台，发出前可取消；发出后取消不代表撤单。不打开支付 URL。";[stack addArrangedSubview:self.noticeLabel];
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[[self button:@"清空采集" action:@selector(clear) identifier:@"WDG.ClearSnapshot"],[self button:@"导出诊断" action:@selector(export) identifier:@"WDG.Export"]]];row.axis=UILayoutConstraintAxisHorizontal;row.distribution=UIStackViewDistributionFillEqually;row.spacing=10;[stack addArrangedSubview:row];
    [stack addArrangedSubview:[self button:@"收起悬浮面板" action:@selector(closePanel) identifier:@"WDG.ClosePanel"]];
}
- (void)refresh {
    if(!self.card)return;
    NSDictionary *s=WDGCore.shared.status;NSDictionary *snapshot=s[@"snapshot"],*task=s[@"task"];
    self.stateLabel.text=[NSString stringWithFormat:@"v%@ · %@ · %@",s[@"version"],s[@"build"],[s[@"ioError"] length]?s[@"ioError"]:@"沙盒存储正常"];
    [self.captureButton setTitle:[s[@"captureEnabled"] boolValue]?@"自动采集：开启（点击暂停）":@"自动采集：暂停（点击开启）" forState:UIControlStateNormal];
    if(![self.shownSample isEqual:snapshot[@"sampleKey"]]){self.payType=nil;self.shownSample=snapshot[@"sampleKey"];[self.payButton setTitle:@"选择已采集支付参数" forState:UIControlStateNormal];}
    NSMutableArray *lines=[NSMutableArray array];
    NSArray *cartLines=WDGCartSelectedLines();
    if(cartLines.count){
        [lines addObject:[NSString stringWithFormat:@"购物车 %lu 件（预热可用）",(unsigned long)cartLines.count]];
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
    else self.countdownLabel.text=[NSString stringWithFormat:@"%@%@",@{@"idle":@"尚未设置任务",@"firing":@"准备接口参数",@"sending":@"接口已发出，等待响应",@"apiSucceeded":@"创建接口返回成功",@"unknown":@"订单结果待核对（不重试）",@"fired":@"本地任务已完成",@"cancelled":@"任务已取消",@"failed":@"接口任务未完成"}[state]?:state,[task[@"reason"] length]?[NSString stringWithFormat:@"\n%@",task[@"reason"]]:@""];
}
- (void)actionChanged {self.payButton.hidden=self.action.selectedSegmentIndex!=2;}
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
    NSArray *options=WDGCore.shared.status[@"snapshot"][@"payOptions"];
    if(options.count==0){
        // Cart mode has no confirmation page, so offer the App's own button
        // enum values that the confirmation model declared (0-3). The user
        // still picks explicitly; nothing is inferred from price or title.
        UIAlertController *c=[UIAlertController alertControllerWithTitle:@"选择支付参数" message:@"购物车模式没有确认页按钮。请选择你在 App 中使用的支付方式对应的参数值。" preferredStyle:UIAlertControllerStyleActionSheet];
        for(NSNumber *type in @[@0,@1,@2,@3]){
            [c addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"参数 %@",type] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
                self.payType=type;[self.payButton setTitle:[NSString stringWithFormat:@"接口支付参数：%@",type] forState:UIControlStateNormal];
            }]];
        }
        [c addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        c.popoverPresentationController.sourceView=self.card;c.popoverPresentationController.sourceRect=self.card.bounds;
        [self.window.rootViewController presentViewController:c animated:YES completion:nil];
        return;
    }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"选择当前页按钮" message:@"这里只选择按钮，不执行点击或下单。" preferredStyle:UIAlertControllerStyleAlert];
    for(NSDictionary *o in options){NSString *title=o[@"title"]?:@"按钮";NSNumber *type=o[@"type"];if(![type isKindOfClass:NSNumber.class])continue;[a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@（%@）",title,type] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){self.payType=type;[self.payButton setTitle:[NSString stringWithFormat:@"接口支付参数：%@",title] forState:UIControlStateNormal];}]];}
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)schedule {
    NSString *action=@[@"reminder",@"dryRun",@"preheatOnce"][self.action.selectedSegmentIndex];
    NSDate *date=self.datePicker.date;
    void (^arm)(void)=^{NSError *error=nil;if(![WDGCore.shared armAt:date action:action payType:self.payType error:&error])[self alert:@"任务未设置" message:error.localizedDescription];};
    if(![action isEqual:@"preheatOnce"]){arm();return;}
    NSArray *lines=WDGCartSelectedLines();
    NSString *reason=nil;
    if(!lines.count){[self alert:@"请先打开购物车" message:@"购物车预热需要先让插件采集到购物车商品。请进入购物车页，保持几秒后回来。"];return;}
    if(![WDGOrderService preheatReady:&reason]){[self alert:@"预热接口未就绪" message:reason?:@"接口不可用"];return;}
    NSDateFormatter *df=[NSDateFormatter new];df.dateFormat=@"yyyy-MM-dd HH:mm:ss ZZZZ";
    NSMutableString *review=[NSMutableString stringWithFormat:@"购物车 %lu 件：\n",(unsigned long)lines.count];
    for(NSDictionary *line in lines){
        [review appendFormat:@"· %@ / %@ × %@\n",line[@"title"]?:@"商品",line[@"skuTitle"]?:@"未选规格",line[@"quantity"]?:@"?"];
    }
    [review appendFormat:@"\n执行时间：%@\n支付参数：%@\n\n到点先调确认接口，再用返回数据调 CreateOrder。可能产生真实订单及所选支付方式的服务端效果。插件不执行页面点击、不打开支付链接。",[df stringFromDate:date],self.payType?:@"未选择"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认购物车预热直提" message:review preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确认以上商品及时间" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *v){arm();}]];
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
