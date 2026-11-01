#import "WDGCore.h"
#import "WDGCart.h"
#import "WDGOrderService.h"

// Local declaration lets the UI compile while Core adopts the new selector.
@interface WDGCore (WDGPanelConcurrentArming)
- (BOOL)armCartAt:(NSDate *)date maximumTotal:(NSDecimalNumber *)maximumTotal concurrentLanes:(NSUInteger)lanes error:(NSError **)error;
@end

@interface WDGPassWindow : UIWindow @end
@implementation WDGPassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    return hit==self || hit==self.rootViewController.view ? nil : hit;
}
@end

@interface WDGPanel : NSObject <UIAdaptivePresentationControllerDelegate>
@property(nonatomic,strong) WDGPassWindow *window;
@property(nonatomic,weak) UIWindow *previousKey;
@property(nonatomic,strong) UIButton *bubble;
@property(nonatomic,strong) UIControl *scrim;
@property(nonatomic,strong) UIView *card;
@property(nonatomic,strong) UILabel *productLabel;
@property(nonatomic,strong) UILabel *detailLabel;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *statusDetail;
@property(nonatomic,strong) UILabel *versionLabel;
@property(nonatomic,strong) UIView *statusPill;
@property(nonatomic,strong) UIView *statusDot;
@property(nonatomic,strong) UILabel *lanesBadge;
@property(nonatomic,strong) UIDatePicker *datePicker;
@property(nonatomic,strong) UIButton *timeButton;
@property(nonatomic,strong) UILabel *timeValue;
@property(nonatomic,strong) NSDate *dateBeforeEditing;
@property(nonatomic,strong) UIViewController *timeSheet;
@property(nonatomic,strong) UITextField *maximumAmount;
@property(nonatomic,strong) UIButton *primaryButton;
@property(nonatomic,strong) UIButton *cancelButton;
@property(nonatomic,strong) NSTimer *refreshTimer;
@property(nonatomic,assign) NSUInteger concurrentLanes;
+ (instancetype)shared;
@end
@implementation WDGPanel
+ (instancetype)shared {static WDGPanel *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];});return p;}
- (instancetype)init {
    if((self=[super init])) {
        _concurrentLanes=1;
        NSNotificationCenter *n=NSNotificationCenter.defaultCenter;
        [n addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [n addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [n addObserver:self selector:@selector(stateChanged:) name:WDGStateDidChange object:nil];
    }
    return self;
}
- (UIColor *)accent {return [UIColor colorWithRed:0.90 green:0.14 blue:0.30 alpha:1];}
- (UIColor *)softBackground {return UIColor.secondarySystemBackgroundColor;}
- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l=[UILabel new];l.font=[UIFont systemFontOfSize:size weight:weight];l.textColor=UIColor.labelColor;l.numberOfLines=0;return l;
}
- (UIButton *)iconButton:(NSString *)symbol action:(SEL)selector label:(NSString *)label {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];b.tintColor=UIColor.secondaryLabelColor;
    b.accessibilityLabel=label;[b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [b.widthAnchor constraintEqualToConstant:36].active=YES;[b.heightAnchor constraintEqualToConstant:36].active=YES;return b;
}
- (UIImageView *)rowIcon:(NSString *)symbol inView:(UIView *)row {
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor=[self accent];icon.contentMode=UIViewContentModeScaleAspectFit;icon.translatesAutoresizingMaskIntoConstraints=NO;icon.userInteractionEnabled=NO;[row addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[[icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],[icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],[icon.widthAnchor constraintEqualToConstant:23],[icon.heightAnchor constraintEqualToConstant:25]]];return icon;
}
- (UILabel *)rowTitle:(NSString *)text icon:(UIView *)icon inView:(UIView *)row {
    UILabel *label=[self label:12 weight:UIFontWeightMedium];label.text=text;label.textColor=UIColor.secondaryLabelColor;label.translatesAutoresizingMaskIntoConstraints=NO;label.userInteractionEnabled=NO;[row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],[label.topAnchor constraintEqualToAnchor:row.topAnchor constant:15],[label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-16]]];return label;
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
    b.backgroundColor=[self accent];b.layer.shadowColor=UIColor.blackColor.CGColor;b.layer.shadowOpacity=0.18;b.layer.shadowRadius=7;b.layer.shadowOffset=CGSizeMake(0,3);
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
    self.scrim.hidden=NO;self.card.hidden=NO;self.bubble.hidden=YES;[self.window makeKeyWindow];
    if(self.datePicker.date.timeIntervalSinceNow<2){self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:120];self.datePicker.date=[self selectedMinute];}
    [self updateTimeDisplay];
    [self.refreshTimer invalidate];self.refreshTimer=[NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];[self refresh];
}
- (void)closePanel {
    [self.card endEditing:YES];
    if(self.dateBeforeEditing){self.datePicker.date=self.dateBeforeEditing;self.dateBeforeEditing=nil;}
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];self.timeSheet=nil;
    self.card.hidden=YES;self.scrim.hidden=YES;self.bubble.hidden=NO;
    [self.refreshTimer invalidate];self.refreshTimer=nil;[self.previousKey makeKeyWindow];self.previousKey=nil;
}
- (void)buildCard {
    UIView *root=self.window.rootViewController.view;
    self.scrim=[UIControl new];self.scrim.backgroundColor=[UIColor colorWithWhite:0 alpha:0.25];self.scrim.translatesAutoresizingMaskIntoConstraints=NO;self.scrim.accessibilityLabel=@"收起任务面板";self.scrim.accessibilityIdentifier=@"WDG.PanelScrim";
    [self.scrim addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];[root addSubview:self.scrim];
    [NSLayoutConstraint activateConstraints:@[[self.scrim.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[self.scrim.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[self.scrim.topAnchor constraintEqualToAnchor:root.topAnchor],[self.scrim.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
    self.card=[UIView new];self.card.backgroundColor=UIColor.systemBackgroundColor;self.card.layer.cornerRadius=22;self.card.layer.cornerCurve=kCACornerCurveContinuous;
    self.card.layer.shadowColor=UIColor.blackColor.CGColor;self.card.layer.shadowOpacity=0.12;self.card.layer.shadowRadius=28;self.card.layer.shadowOffset=CGSizeMake(0,12);
    self.card.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:self.card];
    CGFloat width=MIN(376,self.window.bounds.size.width-32),height=MIN(654,self.window.bounds.size.height-110);
    [NSLayoutConstraint activateConstraints:@[[self.card.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],[self.card.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],[self.card.widthAnchor constraintEqualToConstant:width],[self.card.heightAnchor constraintEqualToConstant:height]]];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.showsVerticalScrollIndicator=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self.card addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:20],[scroll.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-20],[scroll.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:20],[scroll.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-20]]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *title=[self label:23 weight:UIFontWeightBold];title.text=@"准备开抢";
    UIButton *more=[self iconButton:@"ellipsis" action:@selector(showMore) label:@"更多选项"],*close=[self iconButton:@"xmark" action:@selector(closePanel) label:@"收起面板"];
    more.accessibilityIdentifier=@"WDG.More";close.accessibilityIdentifier=@"WDG.ClosePanel";
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[title,more,close]];header.axis=UILayoutConstraintAxisHorizontal;header.alignment=UIStackViewAlignmentCenter;header.spacing=4;[stack addArrangedSubview:header];[stack setCustomSpacing:20 afterView:header];
    UIButton *product=[UIButton buttonWithType:UIButtonTypeSystem];product.backgroundColor=[self softBackground];product.layer.cornerRadius=16;product.layer.cornerCurve=kCACornerCurveContinuous;
    product.accessibilityIdentifier=@"WDG.CartTarget";product.accessibilityLabel=@"选择购物车目标";[product addTarget:self action:@selector(chooseCartTarget) forControlEvents:UIControlEventTouchUpInside];
    UIImageView *bag=[self rowIcon:@"bag" inView:product];
    self.productLabel=[self label:15 weight:UIFontWeightSemibold];self.productLabel.numberOfLines=2;self.productLabel.translatesAutoresizingMaskIntoConstraints=NO;self.productLabel.userInteractionEnabled=NO;
    self.detailLabel=[self label:11 weight:UIFontWeightRegular];self.detailLabel.textColor=UIColor.secondaryLabelColor;self.detailLabel.numberOfLines=2;self.detailLabel.translatesAutoresizingMaskIntoConstraints=NO;self.detailLabel.userInteractionEnabled=NO;
    UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];chevron.tintColor=UIColor.tertiaryLabelColor;chevron.translatesAutoresizingMaskIntoConstraints=NO;chevron.contentMode=UIViewContentModeScaleAspectFit;chevron.userInteractionEnabled=NO;
    [product addSubview:self.productLabel];[product addSubview:self.detailLabel];[product addSubview:chevron];
    [NSLayoutConstraint activateConstraints:@[[product.heightAnchor constraintGreaterThanOrEqualToConstant:96],[chevron.trailingAnchor constraintEqualToAnchor:product.trailingAnchor constant:-14],[chevron.centerYAnchor constraintEqualToAnchor:product.centerYAnchor],[chevron.widthAnchor constraintEqualToConstant:7],[chevron.heightAnchor constraintEqualToConstant:12],[self.productLabel.leadingAnchor constraintEqualToAnchor:bag.trailingAnchor constant:14],[self.productLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-10],[self.productLabel.topAnchor constraintEqualToAnchor:product.topAnchor constant:15],[self.detailLabel.leadingAnchor constraintEqualToAnchor:self.productLabel.leadingAnchor],[self.detailLabel.trailingAnchor constraintEqualToAnchor:self.productLabel.trailingAnchor],[self.detailLabel.topAnchor constraintEqualToAnchor:self.productLabel.bottomAnchor constant:6],[self.detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:product.bottomAnchor constant:-14]]];
    [stack addArrangedSubview:product];[stack setCustomSpacing:20 afterView:product];
    self.datePicker=[UIDatePicker new];self.datePicker.datePickerMode=UIDatePickerModeDateAndTime;self.datePicker.preferredDatePickerStyle=UIDatePickerStyleWheels;self.datePicker.minuteInterval=1;
    self.datePicker.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];self.datePicker.timeZone=NSTimeZone.localTimeZone;self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:120];self.datePicker.date=[self selectedMinute];self.datePicker.accessibilityIdentifier=@"WDG.FireAt";
    self.timeButton=[UIButton buttonWithType:UIButtonTypeSystem];self.timeButton.backgroundColor=[self softBackground];self.timeButton.layer.cornerRadius=16;self.timeButton.layer.cornerCurve=kCACornerCurveContinuous;self.timeButton.accessibilityIdentifier=@"WDG.OpenTimePicker";
    [self.timeButton addTarget:self action:@selector(showTimePicker) forControlEvents:UIControlEventTouchUpInside];
    UIImageView *clock=[self rowIcon:@"clock" inView:self.timeButton];UILabel *timeTitle=[self rowTitle:@"开抢时间" icon:clock inView:self.timeButton];
    self.timeValue=[self label:22 weight:UIFontWeightSemibold];self.timeValue.font=[UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightSemibold];self.timeValue.numberOfLines=1;self.timeValue.adjustsFontSizeToFitWidth=YES;self.timeValue.minimumScaleFactor=0.75;self.timeValue.translatesAutoresizingMaskIntoConstraints=NO;self.timeValue.userInteractionEnabled=NO;[self.timeButton addSubview:self.timeValue];
    UIImageView *timeChevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];timeChevron.tintColor=UIColor.tertiaryLabelColor;timeChevron.contentMode=UIViewContentModeScaleAspectFit;timeChevron.translatesAutoresizingMaskIntoConstraints=NO;timeChevron.userInteractionEnabled=NO;[self.timeButton addSubview:timeChevron];
    [NSLayoutConstraint activateConstraints:@[[self.timeButton.heightAnchor constraintEqualToConstant:86],[self.timeValue.leadingAnchor constraintEqualToAnchor:timeTitle.leadingAnchor],[self.timeValue.topAnchor constraintEqualToAnchor:timeTitle.bottomAnchor constant:5],[self.timeValue.trailingAnchor constraintEqualToAnchor:timeChevron.leadingAnchor constant:-10],[timeChevron.trailingAnchor constraintEqualToAnchor:self.timeButton.trailingAnchor constant:-16],[timeChevron.centerYAnchor constraintEqualToAnchor:self.timeButton.centerYAnchor],[timeChevron.widthAnchor constraintEqualToConstant:7],[timeChevron.heightAnchor constraintEqualToConstant:12]]];
    [stack addArrangedSubview:self.timeButton];[stack setCustomSpacing:12 afterView:self.timeButton];
    UIView *money=[UIView new];money.backgroundColor=[self softBackground];money.layer.cornerRadius=16;money.layer.cornerCurve=kCACornerCurveContinuous;
    UIImageView *moneyIcon=[self rowIcon:@"creditcard" inView:money];UILabel *moneyTitle=[self rowTitle:@"最高实付 · 含运费" icon:moneyIcon inView:money];
    UILabel *currency=[self label:22 weight:UIFontWeightMedium];currency.text=@"¥";currency.textColor=UIColor.secondaryLabelColor;currency.translatesAutoresizingMaskIntoConstraints=NO;[money addSubview:currency];
    self.maximumAmount=[UITextField new];self.maximumAmount.placeholder=@"0.00";self.maximumAmount.borderStyle=UITextBorderStyleNone;self.maximumAmount.backgroundColor=UIColor.clearColor;self.maximumAmount.keyboardType=UIKeyboardTypeDecimalPad;self.maximumAmount.textAlignment=NSTextAlignmentLeft;self.maximumAmount.font=[UIFont monospacedDigitSystemFontOfSize:26 weight:UIFontWeightSemibold];self.maximumAmount.textColor=UIColor.labelColor;self.maximumAmount.tintColor=[self accent];self.maximumAmount.adjustsFontSizeToFitWidth=YES;self.maximumAmount.minimumFontSize=18;self.maximumAmount.accessibilityLabel=@"最高实付金额，含运费";self.maximumAmount.accessibilityIdentifier=@"WDG.MaximumTotal";self.maximumAmount.translatesAutoresizingMaskIntoConstraints=NO;[money addSubview:self.maximumAmount];
    UIToolbar *toolbar=[UIToolbar new];toolbar.tintColor=[self accent];[toolbar sizeToFit];toolbar.items=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(endEditing)]];self.maximumAmount.inputAccessoryView=toolbar;
    [NSLayoutConstraint activateConstraints:@[[money.heightAnchor constraintEqualToConstant:86],[currency.leadingAnchor constraintEqualToAnchor:moneyTitle.leadingAnchor],[currency.centerYAnchor constraintEqualToAnchor:self.maximumAmount.centerYAnchor],[self.maximumAmount.leadingAnchor constraintEqualToAnchor:currency.trailingAnchor constant:7],[self.maximumAmount.trailingAnchor constraintEqualToAnchor:money.trailingAnchor constant:-16],[self.maximumAmount.topAnchor constraintEqualToAnchor:moneyTitle.bottomAnchor constant:2],[self.maximumAmount.heightAnchor constraintEqualToConstant:36]]];[stack addArrangedSubview:money];
    self.lanesBadge=[self label:11 weight:UIFontWeightSemibold];self.lanesBadge.text=@"2路竞速·可能重复下单";self.lanesBadge.textColor=[self accent];self.lanesBadge.hidden=YES;self.lanesBadge.accessibilityIdentifier=@"WDG.ConcurrentLanesBadge";[stack addArrangedSubview:self.lanesBadge];[stack setCustomSpacing:12 afterView:self.lanesBadge];
    self.statusPill=[UIView new];self.statusPill.layer.cornerRadius=12;self.statusPill.backgroundColor=[[self accent] colorWithAlphaComponent:0.08];
    self.statusDot=[UIView new];self.statusDot.layer.cornerRadius=3;self.statusDot.backgroundColor=[self accent];self.statusDot.translatesAutoresizingMaskIntoConstraints=NO;[self.statusPill addSubview:self.statusDot];
    self.statusLabel=[self label:12 weight:UIFontWeightSemibold];self.statusLabel.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];self.statusLabel.textColor=[self accent];self.statusLabel.numberOfLines=1;self.statusLabel.accessibilityIdentifier=@"WDG.Countdown";self.statusLabel.translatesAutoresizingMaskIntoConstraints=NO;[self.statusPill addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[[self.statusPill.heightAnchor constraintEqualToConstant:25],[self.statusDot.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor constant:10],[self.statusDot.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],[self.statusDot.widthAnchor constraintEqualToConstant:6],[self.statusDot.heightAnchor constraintEqualToConstant:6],[self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:6],[self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor constant:-10],[self.statusLabel.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor]]];
    UIStackView *statusRow=[[UIStackView alloc] initWithArrangedSubviews:@[self.statusPill,[UIView new]]];statusRow.axis=UILayoutConstraintAxisHorizontal;[self.statusPill setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];[self.statusLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];[stack addArrangedSubview:statusRow];[stack setCustomSpacing:6 afterView:statusRow];
    self.statusDetail=[self label:11 weight:UIFontWeightRegular];self.statusDetail.textColor=UIColor.secondaryLabelColor;self.statusDetail.numberOfLines=2;[stack addArrangedSubview:self.statusDetail];
    self.primaryButton=[UIButton buttonWithType:UIButtonTypeSystem];self.primaryButton.backgroundColor=[self accent];self.primaryButton.layer.cornerRadius=16;self.primaryButton.layer.cornerCurve=kCACornerCurveContinuous;[self.primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];self.primaryButton.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];[self.primaryButton setTitle:@"准备抢购" forState:UIControlStateNormal];self.primaryButton.accessibilityIdentifier=@"WDG.ArmTask";[self.primaryButton.heightAnchor constraintEqualToConstant:52].active=YES;[self.primaryButton addTarget:self action:@selector(schedule) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:self.primaryButton];[stack setCustomSpacing:10 afterView:self.primaryButton];
    self.cancelButton=[UIButton buttonWithType:UIButtonTypeSystem];self.cancelButton.tintColor=UIColor.secondaryLabelColor;self.cancelButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];[self.cancelButton setTitle:@"取消任务" forState:UIControlStateNormal];[self.cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];self.cancelButton.accessibilityIdentifier=@"WDG.CancelTask";self.cancelButton.hidden=YES;[stack addArrangedSubview:self.cancelButton];[stack setCustomSpacing:8 afterView:self.cancelButton];
    self.versionLabel=[self label:10 weight:UIFontWeightRegular];self.versionLabel.textColor=UIColor.tertiaryLabelColor;self.versionLabel.textAlignment=NSTextAlignmentCenter;[stack addArrangedSubview:self.versionLabel];
    [self updateTimeDisplay];
}
- (void)endEditing {[self.card endEditing:YES];}
- (void)updateTimeDisplay {
    NSDate *date=[self selectedMinute];NSCalendar *calendar=NSCalendar.currentCalendar;NSDateFormatter *df=[NSDateFormatter new];df.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];df.timeZone=self.datePicker.timeZone?:NSTimeZone.localTimeZone;
    df.dateFormat=@"HH:mm";NSString *clock=[df stringFromDate:date];NSString *day=nil;
    if([calendar isDateInToday:date])day=@"今天";else if([calendar isDateInTomorrow:date])day=@"明天";else {df.dateFormat=@"M月d日";day=[df stringFromDate:date];}
    self.timeValue.text=[NSString stringWithFormat:@"%@  %@",day,clock];self.timeButton.accessibilityLabel=[NSString stringWithFormat:@"开抢时间，%@，精确到整分钟",self.timeValue.text];
}
- (void)showTimePicker {
    if(!self.timeButton.enabled||self.timeSheet)return;[self endEditing];self.dateBeforeEditing=self.datePicker.date;
    UIViewController *sheet=[UIViewController new];self.timeSheet=sheet;sheet.modalPresentationStyle=UIModalPresentationPageSheet;sheet.view.backgroundColor=UIColor.systemBackgroundColor;sheet.preferredContentSize=CGSizeMake(376,360);
    UIButton *cancel=[UIButton buttonWithType:UIButtonTypeSystem];[cancel setTitle:@"取消" forState:UIControlStateNormal];cancel.tintColor=UIColor.secondaryLabelColor;[cancel addTarget:self action:@selector(cancelTimePicker) forControlEvents:UIControlEventTouchUpInside];
    UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem];[done setTitle:@"完成" forState:UIControlStateNormal];done.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];done.tintColor=[self accent];[done addTarget:self action:@selector(finishTimePicker) forControlEvents:UIControlEventTouchUpInside];
    UILabel *title=[self label:17 weight:UIFontWeightSemibold];title.text=@"选择开抢时间";title.textAlignment=NSTextAlignmentCenter;
    [cancel.widthAnchor constraintEqualToConstant:48].active=YES;[done.widthAnchor constraintEqualToConstant:48].active=YES;
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[cancel,title,done]];header.axis=UILayoutConstraintAxisHorizontal;header.alignment=UIStackViewAlignmentCenter;header.spacing=8;header.translatesAutoresizingMaskIntoConstraints=NO;[sheet.view addSubview:header];
    UILabel *hint=[self label:12 weight:UIFontWeightRegular];hint.text=@"本地时间 · 精确到整分钟（秒为 00）";hint.textColor=UIColor.secondaryLabelColor;hint.textAlignment=NSTextAlignmentCenter;hint.translatesAutoresizingMaskIntoConstraints=NO;[sheet.view addSubview:hint];
    [self.datePicker removeFromSuperview];self.datePicker.translatesAutoresizingMaskIntoConstraints=NO;[sheet.view addSubview:self.datePicker];
    [NSLayoutConstraint activateConstraints:@[[header.leadingAnchor constraintEqualToAnchor:sheet.view.leadingAnchor constant:20],[header.trailingAnchor constraintEqualToAnchor:sheet.view.trailingAnchor constant:-20],[header.topAnchor constraintEqualToAnchor:sheet.view.safeAreaLayoutGuide.topAnchor constant:18],[header.heightAnchor constraintEqualToConstant:40],[hint.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6],[hint.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],[hint.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],[self.datePicker.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:12],[self.datePicker.leadingAnchor constraintEqualToAnchor:sheet.view.leadingAnchor constant:12],[self.datePicker.trailingAnchor constraintEqualToAnchor:sheet.view.trailingAnchor constant:-12],[self.datePicker.heightAnchor constraintEqualToConstant:216]]];
    UISheetPresentationController *presentation=sheet.sheetPresentationController;presentation.detents=@[UISheetPresentationControllerDetent.mediumDetent];presentation.prefersGrabberVisible=YES;presentation.preferredCornerRadius=28.0;sheet.presentationController.delegate=self;
    [self.window.rootViewController presentViewController:sheet animated:YES completion:nil];
}
- (void)cancelTimePicker {
    if(self.dateBeforeEditing)self.datePicker.date=self.dateBeforeEditing;self.dateBeforeEditing=nil;[self updateTimeDisplay];[self.timeSheet dismissViewControllerAnimated:YES completion:nil];self.timeSheet=nil;
}
- (void)finishTimePicker {
    self.datePicker.date=[self selectedMinute];self.dateBeforeEditing=nil;[self updateTimeDisplay];[self.timeSheet dismissViewControllerAnimated:YES completion:nil];self.timeSheet=nil;
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if(presentationController.presentedViewController==self.timeSheet){if(self.dateBeforeEditing)self.datePicker.date=self.dateBeforeEditing;self.dateBeforeEditing=nil;self.timeSheet=nil;[self updateTimeDisplay];}
}
- (void)refresh {
    if(!self.card)return;
    NSArray *items=WDGCartSelectedLines();NSDictionary *state=WDGCore.shared.status,*task=state[@"task"];NSString *phase=task[@"state"];
    NSString *source=[WDGCartDiagnostics()[@"selectionSource"] isEqual:@"assistant_explicit"]?@"手动指定":@"购物车勾选";
    if(items.count){NSDictionary *first=items.firstObject;self.productLabel.text=first[@"title"]?:@"购物车商品";self.detailLabel.text=[NSString stringWithFormat:@"%@ · %@ × %@%@",source,first[@"skuTitle"]?:@"未选规格",first[@"quantity"]?:@"?",items.count>1?[NSString stringWithFormat:@"\n共 %lu 个条目 · 点此查看",(unsigned long)items.count]:@""];}
    else {self.productLabel.text=@"选择要抢的商品";self.detailLabel.text=@"默认跟随购物车勾选 · 点此手动指定";}
    BOOL active=[@[@"armed",@"firing",@"preheating",@"waitingSale",@"sending"] containsObject:phase],unknown=[phase isEqual:@"unknown"];
    if([@[@"armed",@"waitingSale"] containsObject:phase]){NSTimeInterval s=MAX(0,[task[@"dueAt"] doubleValue]-NSDate.date.timeIntervalSince1970);self.statusLabel.text=[NSString stringWithFormat:@"距离开抢  %02ld:%02ld:%02ld",(long)(s/3600),(long)((NSInteger)s/60%60),(long)((NSInteger)s%60)];}
    else self.statusLabel.text=@{@"idle":@"待准备",@"firing":@"准备中",@"preheating":@"正在确认商品",@"sending":@"已提交 · 等待结果",@"apiSucceeded":@"接口已返回成功",@"failed":@"本次未完成",@"cancelled":@"任务已取消",@"fired":@"本地演练完成",@"unknown":@"订单结果待核对"}[phase]?:@"待准备";
    NSUInteger lanes=(active||unknown)?MAX((NSUInteger)1,[task[@"concurrentLanes"] unsignedIntegerValue]):self.concurrentLanes;
    self.lanesBadge.hidden=lanes!=2;
    self.statusDetail.text=[task[@"reason"] length]?task[@"reason"]:(lanes==2?@"前台运行 · 同一商品最多 2 单\n已发请求可能各自成功，请核对订单":@"保持微店前台 · 到点提交 1 次\n实付超上限或商品未开放会停止");
    UIColor *statusColor=[phase isEqual:@"apiSucceeded"]?UIColor.systemGreenColor:((unknown||[phase isEqual:@"failed"])?UIColor.systemOrangeColor:[self accent]);
    self.statusLabel.textColor=statusColor;self.statusDot.backgroundColor=statusColor;self.statusPill.backgroundColor=[statusColor colorWithAlphaComponent:0.09];
    self.primaryButton.enabled=!active&&!unknown;self.primaryButton.alpha=self.primaryButton.enabled?1:0.52;
    [self.primaryButton setTitle:active?@"已准备，等待执行":(unknown?@"请先核对订单结果":@"准备抢购") forState:UIControlStateNormal];
    self.cancelButton.hidden=!active;self.datePicker.enabled=!active&&!unknown;self.timeButton.enabled=!active&&!unknown;self.timeButton.alpha=self.timeButton.enabled?1:0.6;self.maximumAmount.enabled=!active&&!unknown;
    self.versionLabel.text=[NSString stringWithFormat:@"微店助手 %@ · %@",state[@"version"],state[@"build"]];
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)chooseCartTarget {
    NSArray *rows=[[NSArray alloc] initWithArray:WDGCartCandidates() copyItems:YES];
    if(!rows.count){[self alert:@"先刷新一下购物车" message:@"助手会自动读取商品。未开售的条目也能在这里选择。 "];return;}
    BOOL explicit=[WDGCartDiagnostics()[@"selectionSource"] isEqual:@"assistant_explicit"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"要抢哪件" message:explicit?@"当前来源：手动指定\n只选择目标，不修改购物车、不下单。":@"当前来源：购物车勾选（默认）\n只选择目标，不修改购物车、不下单。" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"跟随购物车勾选项（默认）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){if(![rows isEqual:WDGCartCandidates()]){[self alert:@"购物车有更新" message:@"请重新选择目标。 "];return;}WDGCartChooseLine(nil);[self refresh];}]];
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
- (NSString *)formattedAmount:(NSDecimalNumber *)amount {
    NSNumberFormatter *formatter=[NSNumberFormatter new];formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];formatter.numberStyle=NSNumberFormatterDecimalStyle;formatter.usesGroupingSeparator=NO;formatter.minimumFractionDigits=2;formatter.maximumFractionDigits=2;return [formatter stringFromNumber:amount]?:amount.stringValue;
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
    NSUInteger lanes=self.concurrentLanes==2?2:1;
    NSDecimalNumber *total=[maximum decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithMantissa:lanes exponent:0 isNegative:NO]];
    NSDateFormatter *df=[NSDateFormatter new];df.dateFormat=@"yyyy-MM-dd HH:mm:ss ZZZZ";df.timeZone=self.datePicker.timeZone?:NSTimeZone.localTimeZone;
    NSMutableString *message=[NSMutableString string];for(NSDictionary *item in items)[message appendFormat:@"%@\n%@ × %@\n\n",item[@"title"]?:@"商品",item[@"skuTitle"]?:@"未选规格",item[@"quantity"]?:@"?"];
    [message appendFormat:@"时间：%@\n每单最高实付（含运费）：¥%@\n支付：采用微店确认结果的已选方式\n\n",[df stringFromDate:date],[self formattedAmount:maximum]];
    if(lanes==2)[message appendFormat:@"双路竞速：同商品最多2单\n最高总扣款上限：¥%@（每单上限 × 2）\n\n到点发出 2 路真实下单请求，可能重复下单。已发出的请求可能各自成功，首个成功不会撤销另一已发请求。请保持微店前台。",[self formattedAmount:total]];
    else [message appendFormat:@"单路：最多 1 单\n最高总扣款上限：¥%@\n\n到点将直接创建一次真实订单，不打开支付链接。请保持微店前台。",[self formattedAmount:total]];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:lanes==2?@"确认双路竞速任务":@"确认这笔任务" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"再看看" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:lanes==2?@"确认双路 · 接受最多2单":@"确认单路 · 最多1单" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *v){NSArray *nowKeys=[[WDGCartSelectedLines() valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];if(![key isEqual:WDGCartSnapshotKey()]||![keys isEqual:nowKeys]){[self alert:@"购物车目标已变化" message:@"请重新核对商品和规格。 "];return;}NSError *error=nil;if(![WDGCore.shared armCartAt:date maximumTotal:maximum concurrentLanes:lanes error:&error])[self alert:@"任务未设置" message:error.localizedDescription];}]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)cancel {[WDGCore.shared cancelTask:@"用户取消任务"];}
- (void)localTest {NSError *error=nil;if(![WDGCore.shared armAt:[NSDate dateWithTimeIntervalSinceNow:5] action:@"dryRun" payType:nil error:&error])[self alert:@"演练未开始" message:error.localizedDescription];}
- (void)export {
    NSError *error=nil;NSString *file=[WDGCore.shared exportReport:&error];if(!file){[self alert:@"导出失败" message:error.localizedDescription?:@"请稍后重试"];return;}
    UIActivityViewController *a=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:file]] applicationActivities:nil];a.popoverPresentationController.sourceView=self.card;a.popoverPresentationController.sourceRect=self.card.bounds;[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)chooseConcurrentLanes {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"下单并发" message:@"双路会对同一订单目标发出 2 路请求，可能分别成功并重复下单。最终确认会列出最多订单数及总扣款上限。" preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:self.concurrentLanes==1?@"✓ 单路（默认）":@"单路（默认）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){self.concurrentLanes=1;[self refresh];}]];
    [a addAction:[UIAlertAction actionWithTitle:self.concurrentLanes==2?@"✓ 双路竞速 · 可能重复下单":@"双路竞速 · 可能重复下单" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){self.concurrentLanes=2;[self refresh];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.card;a.popoverPresentationController.sourceRect=self.card.bounds;[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)showMore {
    [self endEditing];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"更多" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *lanes=[UIAlertAction actionWithTitle:self.concurrentLanes==2?@"并发：双路竞速":@"并发：单路" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){[self chooseConcurrentLanes];}];lanes.enabled=self.primaryButton.enabled;[a addAction:lanes];
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
