#import "WDGCore.h"
#import "WDGCart.h"
#import "WDGOrderService.h"

@interface WDGPassWindow : UIWindow @end
@implementation WDGPassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    return hit==self || hit==self.rootViewController.view ? nil : hit;
}
@end

@interface WDGPanel : NSObject
@property(nonatomic,strong) WDGPassWindow *window;
@property(nonatomic,weak) UIWindow *previousKey;
@property(nonatomic,strong) UIButton *bubble;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UILabel *productLabel;
@property(nonatomic,strong) UILabel *detailLabel;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *statusDetail;
@property(nonatomic,strong) UILabel *versionLabel;
@property(nonatomic,strong) UIDatePicker *datePicker;
@property(nonatomic,strong) UITextField *maximumAmount;
@property(nonatomic,strong) UIButton *primaryButton;
@property(nonatomic,strong) UIButton *cancelButton;
@property(nonatomic,strong) NSTimer *refreshTimer;
+ (instancetype)shared;
@end
@implementation WDGPanel
+ (instancetype)shared {static WDGPanel *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];});return p;}
- (instancetype)init {
    if((self=[super init])) {
        NSNotificationCenter *n=NSNotificationCenter.defaultCenter;
        [n addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [n addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [n addObserver:self selector:@selector(stateChanged:) name:WDGStateDidChange object:nil];
    }
    return self;
}
- (UIColor *)accent {return [UIColor colorWithRed:0.90 green:0.14 blue:0.30 alpha:1];}
- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l=[UILabel new];l.font=[UIFont systemFontOfSize:size weight:weight];l.textColor=UIColor.labelColor;l.numberOfLines=0;return l;
}
- (UIButton *)iconButton:(NSString *)symbol action:(SEL)selector label:(NSString *)label {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];b.tintColor=UIColor.secondaryLabelColor;
    b.accessibilityLabel=label;[b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [b.widthAnchor constraintEqualToConstant:36].active=YES;[b.heightAnchor constraintEqualToConstant:36].active=YES;return b;
}
- (void)becameActive:(NSNotification *)n {[self ensureWindow];}
- (void)enteredBackground:(NSNotification *)n {[self closePanel];self.window.hidden=YES;}
- (void)stateChanged:(NSNotification *)n {[self refresh];}
- (void)ensureWindow {
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    if(self.window){self.window.hidden=NO;return;}
    UIWindowScene *scene=nil;
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive){scene=(UIWindowScene *)s;break;}
    WDGPassWindow *w=scene?[[WDGPassWindow alloc] initWithWindowScene:scene]:[[WDGPassWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    w.frame=UIScreen.mainScreen.bounds;w.backgroundColor=UIColor.clearColor;w.windowLevel=UIWindowLevelAlert+2;
    UIViewController *root=[UIViewController new];root.view.backgroundColor=UIColor.clearColor;w.rootViewController=root;self.window=w;
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];self.bubble=b;
    b.frame=CGRectMake(w.bounds.size.width-60,MAX(130,w.bounds.size.height*0.30),46,46);b.layer.cornerRadius=23;
    b.backgroundColor=[self accent];b.layer.shadowOpacity=0.18;b.layer.shadowRadius=7;b.layer.shadowOffset=CGSizeMake(0,3);
    [b setImage:[UIImage systemImageNamed:@"bag.fill"] forState:UIControlStateNormal];b.tintColor=UIColor.whiteColor;
    b.accessibilityLabel=@"微店助手，打开面板";b.accessibilityIdentifier=@"WDG.FloatingButton";
    [b addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [root.view addSubview:b];w.hidden=NO;
    [WDGCore.shared recordEvent:@"overlay_ready" details:@{@"version":WDGVersion,@"build":WDGBuildID}];
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint d=[g translationInView:self.window],p=self.bubble.center;
    self.bubble.center=CGPointMake(MIN(MAX(p.x+d.x,26),self.window.bounds.size.width-26),MIN(MAX(p.y+d.y,MAX(self.window.safeAreaInsets.top,24)+26),self.window.bounds.size.height-MAX(self.window.safeAreaInsets.bottom,20)-26));
    [g setTranslation:CGPointZero inView:self.window];
    if(g.state==UIGestureRecognizerStateEnded){CGPoint c=self.bubble.center;c.x=c.x<self.window.bounds.size.width/2?27:self.window.bounds.size.width-27;[UIView animateWithDuration:0.2 animations:^{self.bubble.center=c;}];}
}
- (void)togglePanel {if(self.card&&!self.card.hidden)[self closePanel];else [self openPanel];}
- (void)openPanel {
    [self ensureWindow];if(!self.window)return;WDGRefreshTradeSnapshot();
    for(UIWindow *w in self.window.windowScene.windows)if(w.isKeyWindow&&w!=self.window)self.previousKey=w;
    if(!self.previousKey){id<UIApplicationDelegate> d=UIApplication.sharedApplication.delegate;if([d respondsToSelector:@selector(window)])self.previousKey=d.window;}
    if(!self.card)[self buildCard];
    self.card.hidden=NO;self.bubble.hidden=YES;[self.window makeKeyWindow];
    if(self.datePicker.date.timeIntervalSinceNow<2)self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:120];
    [self.refreshTimer invalidate];self.refreshTimer=[NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];[self refresh];
}
- (void)closePanel {
    [self.card endEditing:YES];self.card.hidden=YES;self.bubble.hidden=NO;
    [self.refreshTimer invalidate];self.refreshTimer=nil;[self.previousKey makeKeyWindow];self.previousKey=nil;
}
- (void)buildCard {
    UIView *root=self.window.rootViewController.view;
    self.card=[UIView new];self.card.backgroundColor=UIColor.systemBackgroundColor;self.card.layer.cornerRadius=25;
    self.card.layer.shadowOpacity=0.20;self.card.layer.shadowRadius=22;self.card.layer.shadowOffset=CGSizeMake(0,7);
    self.card.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:self.card];
    CGFloat width=MIN(376,self.window.bounds.size.width-32),height=MIN(544,self.window.bounds.size.height-110);
    [NSLayoutConstraint activateConstraints:@[[self.card.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],[self.card.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],[self.card.widthAnchor constraintEqualToConstant:width],[self.card.heightAnchor constraintEqualToConstant:height]]];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.card addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:22],[scroll.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-22],[scroll.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:18],[scroll.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-18]]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=17;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *title=[self label:23 weight:UIFontWeightBold];title.text=@"准备开抢";
    UIButton *more=[self iconButton:@"ellipsis" action:@selector(showMore) label:@"更多选项"],*close=[self iconButton:@"xmark" action:@selector(closePanel) label:@"收起面板"];
    more.accessibilityIdentifier=@"WDG.More";close.accessibilityIdentifier=@"WDG.ClosePanel";
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[title,more,close]];header.axis=UILayoutConstraintAxisHorizontal;header.alignment=UIStackViewAlignmentCenter;header.spacing=4;[stack addArrangedSubview:header];
    UIButton *product=[UIButton buttonWithType:UIButtonTypeSystem];product.backgroundColor=UIColor.secondarySystemBackgroundColor;product.layer.cornerRadius=16;
    product.accessibilityIdentifier=@"WDG.CartTarget";product.accessibilityLabel=@"选择购物车目标";[product addTarget:self action:@selector(chooseCartTarget) forControlEvents:UIControlEventTouchUpInside];
    UIImageView *bag=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bag"]];bag.tintColor=[self accent];bag.translatesAutoresizingMaskIntoConstraints=NO;bag.userInteractionEnabled=NO;
    self.productLabel=[self label:15 weight:UIFontWeightSemibold];self.productLabel.numberOfLines=2;self.productLabel.translatesAutoresizingMaskIntoConstraints=NO;self.productLabel.userInteractionEnabled=NO;
    self.detailLabel=[self label:12 weight:UIFontWeightRegular];self.detailLabel.textColor=UIColor.secondaryLabelColor;self.detailLabel.numberOfLines=2;self.detailLabel.translatesAutoresizingMaskIntoConstraints=NO;self.detailLabel.userInteractionEnabled=NO;
    UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];chevron.tintColor=UIColor.tertiaryLabelColor;chevron.translatesAutoresizingMaskIntoConstraints=NO;
    [product addSubview:bag];[product addSubview:self.productLabel];[product addSubview:self.detailLabel];[product addSubview:chevron];
    [NSLayoutConstraint activateConstraints:@[[product.heightAnchor constraintGreaterThanOrEqualToConstant:104],[bag.leadingAnchor constraintEqualToAnchor:product.leadingAnchor constant:14],[bag.centerYAnchor constraintEqualToAnchor:product.centerYAnchor],[bag.widthAnchor constraintEqualToConstant:24],[bag.heightAnchor constraintEqualToConstant:27],[chevron.trailingAnchor constraintEqualToAnchor:product.trailingAnchor constant:-13],[chevron.centerYAnchor constraintEqualToAnchor:product.centerYAnchor],[chevron.widthAnchor constraintEqualToConstant:8],[self.productLabel.leadingAnchor constraintEqualToAnchor:bag.trailingAnchor constant:12],[self.productLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-10],[self.productLabel.topAnchor constraintEqualToAnchor:product.topAnchor constant:16],[self.detailLabel.leadingAnchor constraintEqualToAnchor:self.productLabel.leadingAnchor],[self.detailLabel.trailingAnchor constraintEqualToAnchor:self.productLabel.trailingAnchor],[self.detailLabel.topAnchor constraintEqualToAnchor:self.productLabel.bottomAnchor constant:5],[self.detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:product.bottomAnchor constant:-14]]];
    [stack addArrangedSubview:product];
    UILabel *timeLabel=[self label:13 weight:UIFontWeightMedium];timeLabel.text=@"开抢时间";timeLabel.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:timeLabel];
    self.datePicker=[UIDatePicker new];self.datePicker.datePickerMode=UIDatePickerModeDateAndTime;self.datePicker.preferredDatePickerStyle=UIDatePickerStyleCompact;
    self.datePicker.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];self.datePicker.timeZone=NSTimeZone.localTimeZone;self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:120];self.datePicker.accessibilityIdentifier=@"WDG.FireAt";[stack addArrangedSubview:self.datePicker];
    UIStackView *money=[UIStackView new];money.axis=UILayoutConstraintAxisHorizontal;money.spacing=8;money.alignment=UIStackViewAlignmentCenter;
    UILabel *moneyLabel=[self label:14 weight:UIFontWeightMedium];moneyLabel.text=@"最高实付";[moneyLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.maximumAmount=[UITextField new];self.maximumAmount.placeholder=@"含运费 · ¥";self.maximumAmount.borderStyle=UITextBorderStyleRoundedRect;self.maximumAmount.keyboardType=UIKeyboardTypeDecimalPad;self.maximumAmount.textAlignment=NSTextAlignmentRight;self.maximumAmount.font=[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];self.maximumAmount.accessibilityLabel=@"最高实付金额，含运费";self.maximumAmount.accessibilityIdentifier=@"WDG.MaximumTotal";
    UIToolbar *toolbar=[UIToolbar new];[toolbar sizeToFit];toolbar.items=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(endEditing)]];self.maximumAmount.inputAccessoryView=toolbar;
    [money addArrangedSubview:moneyLabel];[money addArrangedSubview:self.maximumAmount];[self.maximumAmount.heightAnchor constraintEqualToConstant:45].active=YES;[stack addArrangedSubview:money];
    self.statusLabel=[self label:15 weight:UIFontWeightSemibold];self.statusLabel.textColor=[self accent];self.statusLabel.accessibilityIdentifier=@"WDG.Countdown";[stack addArrangedSubview:self.statusLabel];
    self.statusDetail=[self label:11 weight:UIFontWeightRegular];self.statusDetail.textColor=UIColor.secondaryLabelColor;self.statusDetail.numberOfLines=3;[stack addArrangedSubview:self.statusDetail];
    self.primaryButton=[UIButton buttonWithType:UIButtonTypeSystem];self.primaryButton.backgroundColor=[self accent];self.primaryButton.layer.cornerRadius=14;[self.primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];self.primaryButton.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];[self.primaryButton setTitle:@"准备抢购" forState:UIControlStateNormal];self.primaryButton.accessibilityIdentifier=@"WDG.ArmTask";[self.primaryButton.heightAnchor constraintEqualToConstant:50].active=YES;[self.primaryButton addTarget:self action:@selector(schedule) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:self.primaryButton];
    self.cancelButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.cancelButton setTitle:@"取消任务" forState:UIControlStateNormal];[self.cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];self.cancelButton.accessibilityIdentifier=@"WDG.CancelTask";self.cancelButton.hidden=YES;[stack addArrangedSubview:self.cancelButton];
    self.versionLabel=[self label:10 weight:UIFontWeightRegular];self.versionLabel.textColor=UIColor.tertiaryLabelColor;self.versionLabel.textAlignment=NSTextAlignmentCenter;[stack addArrangedSubview:self.versionLabel];
}
- (void)endEditing {[self.card endEditing:YES];}
- (void)refresh {
    if(!self.card)return;
    NSArray *items=WDGCartSelectedLines();NSDictionary *state=WDGCore.shared.status,*task=state[@"task"];NSString *phase=task[@"state"];
    if(items.count){NSDictionary *first=items.firstObject;self.productLabel.text=first[@"title"]?:@"购物车商品";self.detailLabel.text=[NSString stringWithFormat:@"%@  × %@%@",first[@"skuTitle"]?:@"未选规格",first[@"quantity"]?:@"?",items.count>1?[NSString stringWithFormat:@"\n共 %lu 个条目，点此查看",(unsigned long)items.count]:@" · 点此更换商品"];}
    else {self.productLabel.text=@"选择要抢的商品";self.detailLabel.text=@"自动读取购物车勾选项，也可点此指定";}
    BOOL active=[@[@"armed",@"firing",@"preheating",@"waitingSale",@"sending"] containsObject:phase],unknown=[phase isEqual:@"unknown"];
    if([@[@"armed",@"waitingSale"] containsObject:phase]){NSTimeInterval s=MAX(0,[task[@"dueAt"] doubleValue]-NSDate.date.timeIntervalSince1970);self.statusLabel.text=[NSString stringWithFormat:@"距离开抢  %02ld:%02ld:%02ld",(long)(s/3600),(long)((NSInteger)s/60%60),(long)((NSInteger)s%60)];}
    else self.statusLabel.text=@{@"idle":@"待准备",@"firing":@"准备中",@"preheating":@"正在确认商品",@"sending":@"已提交 · 等待结果",@"apiSucceeded":@"接口已返回成功",@"failed":@"本次未完成",@"cancelled":@"任务已取消",@"fired":@"本地演练完成",@"unknown":@"订单结果待核对"}[phase]?:@"待准备";
    self.statusDetail.text=[task[@"reason"] length]?task[@"reason"]:@"前台运行 · 到点直提一次\n实付超上限或商品未开放会停止";
    self.primaryButton.enabled=!active&&!unknown;self.primaryButton.alpha=self.primaryButton.enabled?1:0.52;
    [self.primaryButton setTitle:active?@"已准备，等待执行":(unknown?@"请先核对订单结果":@"准备抢购") forState:UIControlStateNormal];
    self.cancelButton.hidden=!active;self.datePicker.enabled=!active&&!unknown;self.maximumAmount.enabled=!active&&!unknown;
    self.versionLabel.text=[NSString stringWithFormat:@"微店助手 %@ · %@",state[@"version"],state[@"build"]];
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)chooseCartTarget {
    NSArray *rows=[[NSArray alloc] initWithArray:WDGCartCandidates() copyItems:YES];
    if(!rows.count){[self alert:@"先刷新一下购物车" message:@"助手会自动读取商品。未开售的条目也能在这里选择。 "];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"要抢哪件" message:@"这里只选择目标，不修改购物车、不下单。" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"跟随购物车勾选项" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){if(![rows isEqual:WDGCartCandidates()]){[self alert:@"购物车有更新" message:@"请重新选择目标。 "];return;}WDGCartChooseLine(nil);[self refresh];}]];
    for(NSDictionary *row in rows){NSString *key=[row[@"lineKey"] copy];NSDictionary *raw=[WDGCartRawLine(key) copy];NSString *title=[NSString stringWithFormat:@"%@ · %@ × %@",row[@"title"]?:@"商品",row[@"skuTitle"]?:@"未选规格",row[@"quantity"]?:@"?"];[a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){if(!raw||![raw isEqual:WDGCartRawLine(key)]||!WDGCartChooseLine(key)){[self alert:@"商品已更新" message:@"请重新核对规格和数量。 "];return;}[self refresh];}]];}
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.card;a.popoverPresentationController.sourceRect=self.card.bounds;[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (NSDate *)selectedMinute {
    NSCalendar *c=[(self.datePicker.calendar?:NSCalendar.currentCalendar) copy];c.timeZone=self.datePicker.timeZone?:NSTimeZone.localTimeZone;
    NSDateComponents *p=[c components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute) fromDate:self.datePicker.date];p.second=0;p.nanosecond=0;return [c dateFromComponents:p];
}
- (NSDecimalNumber *)maximumValue {
    NSString *text=[self.maximumAmount.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *p=[NSRegularExpression regularExpressionWithPattern:@"\\A[0-9]+(?:\\.[0-9]{1,2})?\\z" options:0 error:NULL];
    if(!text.length||[p numberOfMatchesInString:text options:0 range:NSMakeRange(0,text.length)]!=1){[self alert:@"填写最高实付金额" message:@"含运费，最多两位小数；确认金额超过它就停止。 "];return nil;}
    NSDecimalNumber *value=[NSDecimalNumber decimalNumberWithString:text locale:@{NSLocaleDecimalSeparator:@"."}];
    if([value isEqual:NSDecimalNumber.notANumber]||[value compare:NSDecimalNumber.zero]!=NSOrderedDescending){[self alert:@"金额应大于零" message:@"请核对最高实付金额。 "];return nil;}return value;
}
- (void)validateCartParameters {
    NSDecimalNumber *maximum=[self maximumValue];if(!maximum)return;
    NSDate *date=[self selectedMinute];if(date.timeIntervalSinceNow<2||date.timeIntervalSinceNow>43200){[self alert:@"请选择未来的开抢时间" message:@"范围为十二小时内，本次只做本地校验。 "];return;}
    NSString *key=[WDGCartSnapshotKey() copy];if(!key.length){[self alert:@"先选好商品" message:@"刷新购物车或点商品卡选择目标。 "];return;}
    NSError *error=nil;id request=WDGCartBuildRequest(&error);
    WDGOrderService *s=request?[WDGOrderService preparePreheatRequest:request sampleKey:key payType:nil error:&error]:nil;
    if(![key isEqual:WDGCartSnapshotKey()]){[self alert:@"目标已变化" message:@"请重新选择后校验。 "];return;}
    if(!s||![s configureCartDueAt:date maximumTotal:maximum error:&error]){[self alert:@"本地校验未通过" message:error.localizedDescription?:@"请核对商品和规格。 "];return;}
    [self endEditing];[self alert:@"本地参数校验成功" message:@"商品请求、原生服务与金额参数已就绪。\n未联网，未设置任务，未调用确认或创建订单接口。最终地址、运费及实付仍由服务端确认。 "];
}
- (void)schedule {
    NSDecimalNumber *maximum=[self maximumValue];if(!maximum)return;[self endEditing];
    NSArray *items=[[NSArray alloc] initWithArray:WDGCartSelectedLines() copyItems:YES];NSString *key=[WDGCartSnapshotKey() copy];NSArray *keys=[[items valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];
    if(!items.count||!key.length){[self alert:@"先选好商品" message:@"刷新购物车或点商品卡选择目标。 "];return;}
    NSDate *date=[self selectedMinute];if(date.timeIntervalSinceNow<2||date.timeIntervalSinceNow>43200){[self alert:@"请选择未来的开抢时间" message:@"设置在十二小时以内，精确到整分钟。 "];return;}
    NSDateFormatter *df=[NSDateFormatter new];df.dateFormat=@"yyyy-MM-dd HH:mm:ss ZZZZ";df.timeZone=self.datePicker.timeZone?:NSTimeZone.localTimeZone;
    NSMutableString *message=[NSMutableString string];for(NSDictionary *item in items)[message appendFormat:@"%@\n%@ × %@\n\n",item[@"title"]?:@"商品",item[@"skuTitle"]?:@"未选规格",item[@"quantity"]?:@"?"];
    [message appendFormat:@"时间：%@\n最高实付（含运费）：¥%@\n支付：采用微店确认结果的已选方式\n\n到点将直接创建一次真实订单，不打开支付链接。请保持微店前台。",[df stringFromDate:date],maximum.stringValue];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认这笔任务" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"再看看" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确认准备" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *v){NSArray *nowKeys=[[WDGCartSelectedLines() valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];if(![key isEqual:WDGCartSnapshotKey()]||![keys isEqual:nowKeys]){[self alert:@"购物车目标已变化" message:@"请重新核对商品和规格。 "];return;}NSError *error=nil;if(![WDGCore.shared armCartAt:date maximumTotal:maximum error:&error])[self alert:@"任务未设置" message:error.localizedDescription];}]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)cancel {[WDGCore.shared cancelTask:@"用户取消任务"];}
- (void)localTest {NSError *error=nil;if(![WDGCore.shared armAt:[NSDate dateWithTimeIntervalSinceNow:5] action:@"dryRun" payType:nil error:&error])[self alert:@"演练未开始" message:error.localizedDescription];}
- (void)export {
    NSError *error=nil;NSString *file=[WDGCore.shared exportReport:&error];if(!file){[self alert:@"导出失败" message:error.localizedDescription?:@"请稍后重试"];return;}
    UIActivityViewController *a=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:file]] applicationActivities:nil];a.popoverPresentationController.sourceView=self.card;a.popoverPresentationController.sourceRect=self.card.bounds;[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)showMore {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"更多" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"校验参数（不联网）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){[self validateCartParameters];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"5 秒本地演练" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){[self localTest];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"导出诊断" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){[self export];}]];
    BOOL capture=[WDGCore.shared.status[@"captureEnabled"] boolValue];
    [a addAction:[UIAlertAction actionWithTitle:capture?@"暂停自动采集":@"开启自动采集" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){[WDGCore.shared setCaptureEnabled:!capture];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"清空采集" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *v){[WDGCore.shared clearSnapshot];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.card;a.popoverPresentationController.sourceRect=self.card.bounds;[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
@end
void WDGShowOverlay(void) {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WDGShowOverlay();});return;}
    [[WDGPanel shared] ensureWindow];
}
