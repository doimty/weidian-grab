#import "WDGCore.h"
#import "WDGCart.h"
#import "WDGOrderService.h"
#import "WDGClock.h"
#import <math.h>

static const CGFloat kWDGCardRadius=22;
static const CGFloat kWDGPadding=18;
static const CGFloat kWDGSectionGap=10;
static const CGFloat kWDGRowPadding=11;
static const CGFloat kWDGRowMinHeight=48;
static const CGFloat kWDGIconSide=20;
static const CGFloat kWDGHairlineHeight=0.5;
static const CGFloat kWDGButtonHeight=46;
static const CGFloat kWDGButtonRadius=14;
static const CGFloat kWDGCardMaxHeight=480;

@interface WDGPassWindow : UIWindow @end
@implementation WDGPassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    return hit==self || hit==self.rootViewController.view ? nil : hit;
}
@end

@interface WDGRowControl : UIControl @end
@implementation WDGRowControl
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor=highlighted?[UIColor.labelColor colorWithAlphaComponent:0.06]:UIColor.clearColor;
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
@property(nonatomic,strong) UIView *statusDot;
@property(nonatomic,strong) UILabel *lanesBadge;
@property(nonatomic,strong) UILabel *clockDetail;
@property(nonatomic,strong) UIDatePicker *datePicker;
@property(nonatomic,strong) UIControl *timeButton;
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
- (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l=[UILabel new];l.font=[UIFont systemFontOfSize:size weight:weight];l.textColor=UIColor.labelColor;l.numberOfLines=0;l.translatesAutoresizingMaskIntoConstraints=NO;return l;
}
- (UIButton *)iconButton:(NSString *)symbol action:(SEL)selector label:(NSString *)label {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];b.tintColor=UIColor.secondaryLabelColor;
    b.accessibilityLabel=label;[b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [b.widthAnchor constraintEqualToConstant:32].active=YES;[b.heightAnchor constraintEqualToConstant:32].active=YES;return b;
}
- (UIView *)hairline {
    UIView *line=[UIView new];line.translatesAutoresizingMaskIntoConstraints=NO;line.userInteractionEnabled=NO;
    line.backgroundColor=[UIColor.separatorColor colorWithAlphaComponent:0.5];
    [line.heightAnchor constraintEqualToConstant:kWDGHairlineHeight].active=YES;return line;
}
- (UILabel *)rowTitle:(NSString *)text {
    UILabel *l=[self label:15 weight:UIFontWeightMedium];l.text=text;l.numberOfLines=1;l.userInteractionEnabled=NO;return l;
}
- (UILabel *)rowDetail:(NSString *)text {
    UILabel *l=[self label:12 weight:UIFontWeightRegular];l.text=text;l.numberOfLines=1;l.textColor=UIColor.secondaryLabelColor;
    l.adjustsFontSizeToFitWidth=YES;l.minimumScaleFactor=0.8;l.userInteractionEnabled=NO;return l;
}
- (UILabel *)rowValue:(NSString *)text mono:(BOOL)mono {
    UILabel *l=[UILabel new];l.font=mono?[UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold]:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    l.text=text;l.textColor=UIColor.labelColor;l.numberOfLines=1;l.textAlignment=NSTextAlignmentRight;
    l.adjustsFontSizeToFitWidth=YES;l.minimumScaleFactor=0.8;l.translatesAutoresizingMaskIntoConstraints=NO;l.userInteractionEnabled=NO;return l;
}
- (UIControl *)rowWithSymbol:(NSString *)symbol title:(UILabel *)title detail:(UILabel *)detail value:(UIView *)value chevron:(BOOL)chevron {
    UIControl *row=[WDGRowControl new];row.translatesAutoresizingMaskIntoConstraints=NO;row.layer.cornerRadius=10;row.layer.cornerCurve=kCACornerCurveContinuous;row.layer.masksToBounds=YES;
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor=[self accent];icon.contentMode=UIViewContentModeScaleAspectFit;icon.translatesAutoresizingMaskIntoConstraints=NO;icon.userInteractionEnabled=NO;[row addSubview:icon];
    NSMutableArray<UIView *> *texts=[NSMutableArray arrayWithObject:title];if(detail)[texts addObject:detail];
    UIStackView *textStack=[[UIStackView alloc] initWithArrangedSubviews:texts];
    textStack.axis=UILayoutConstraintAxisVertical;textStack.spacing=2;textStack.translatesAutoresizingMaskIntoConstraints=NO;textStack.userInteractionEnabled=NO;[row addSubview:textStack];
    NSMutableArray<NSLayoutConstraint *> *rules=[NSMutableArray arrayWithObjects:
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:kWDGIconSide],
        [icon.heightAnchor constraintEqualToConstant:kWDGIconSide],
        [textStack.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [textStack.topAnchor constraintEqualToAnchor:row.topAnchor constant:kWDGRowPadding],
        [textStack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-kWDGRowPadding],
        [title.heightAnchor constraintGreaterThanOrEqualToConstant:18],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:kWDGRowMinHeight],nil];
    UIView *right=nil;
    if(chevron){
        UIImageView *arrow=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        arrow.tintColor=UIColor.tertiaryLabelColor;arrow.contentMode=UIViewContentModeScaleAspectFit;arrow.translatesAutoresizingMaskIntoConstraints=NO;arrow.userInteractionEnabled=NO;[row addSubview:arrow];
        [rules addObjectsFromArray:@[[arrow.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],[arrow.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],[arrow.widthAnchor constraintEqualToConstant:12],[arrow.heightAnchor constraintEqualToConstant:16]]];
        right=arrow;
    }
    if(value){
        [row addSubview:value];
        if(right)[rules addObjectsFromArray:@[[value.trailingAnchor constraintEqualToAnchor:right.leadingAnchor constant:-10],[value.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]]];
        else [rules addObjectsFromArray:@[[value.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],[value.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]]];
        right=value;
    }
    if(right)[rules addObject:[textStack.trailingAnchor constraintLessThanOrEqualToAnchor:right.leadingAnchor constant:-10]];
    else [rules addObject:[textStack.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor]];
    [NSLayoutConstraint activateConstraints:rules];return row;
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
    [WDGCore.shared refreshServerClock];
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
    self.scrim=[UIControl new];self.scrim.backgroundColor=[UIColor colorWithWhite:0 alpha:0.22];self.scrim.translatesAutoresizingMaskIntoConstraints=NO;self.scrim.accessibilityLabel=@"收起任务面板";self.scrim.accessibilityIdentifier=@"WDG.PanelScrim";
    [self.scrim addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];[root addSubview:self.scrim];
    [NSLayoutConstraint activateConstraints:@[[self.scrim.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[self.scrim.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[self.scrim.topAnchor constraintEqualToAnchor:root.topAnchor],[self.scrim.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
    self.card=[UIView new];self.card.backgroundColor=UIColor.systemBackgroundColor;self.card.layer.cornerRadius=kWDGCardRadius;self.card.layer.cornerCurve=kCACornerCurveContinuous;
    self.card.layer.shadowColor=UIColor.blackColor.CGColor;self.card.layer.shadowOpacity=0.10;self.card.layer.shadowRadius=26;self.card.layer.shadowOffset=CGSizeMake(0,12);
    self.card.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:self.card];
    CGFloat width=MIN(376,self.window.bounds.size.width-32);
    [NSLayoutConstraint activateConstraints:@[[self.card.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],[self.card.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],[self.card.widthAnchor constraintEqualToConstant:width],[self.card.topAnchor constraintGreaterThanOrEqualToAnchor:root.topAnchor constant:16],[self.card.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-16]]];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.showsVerticalScrollIndicator=NO;scroll.alwaysBounceVertical=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[self.card addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:kWDGPadding],[scroll.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-kWDGPadding],[scroll.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:kWDGPadding],[scroll.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-kWDGPadding]]];
    NSLayoutConstraint *fitsContent=[scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor];fitsContent.priority=UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *capHeight=[scroll.heightAnchor constraintLessThanOrEqualToConstant:kWDGCardMaxHeight-2*kWDGPadding];
    [NSLayoutConstraint activateConstraints:@[fitsContent,capHeight]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=kWDGSectionGap;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *title=[self label:23 weight:UIFontWeightBold];title.text=@"准备开抢";
    UIButton *more=[self iconButton:@"ellipsis" action:@selector(showMore) label:@"更多选项"],*close=[self iconButton:@"xmark" action:@selector(closePanel) label:@"收起面板"];
    more.accessibilityIdentifier=@"WDG.More";close.accessibilityIdentifier=@"WDG.ClosePanel";
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[title,more,close]];header.axis=UILayoutConstraintAxisHorizontal;header.alignment=UIStackViewAlignmentCenter;header.spacing=2;[stack addArrangedSubview:header];
    self.productLabel=[self label:15 weight:UIFontWeightMedium];self.productLabel.numberOfLines=2;self.productLabel.userInteractionEnabled=NO;
    self.detailLabel=[self rowDetail:nil];
    UIControl *product=[self rowWithSymbol:@"bag.fill" title:self.productLabel detail:self.detailLabel value:nil chevron:YES];
    product.accessibilityIdentifier=@"WDG.CartTarget";product.accessibilityLabel=@"选择购物车目标";[product addTarget:self action:@selector(chooseCartTarget) forControlEvents:UIControlEventTouchUpInside];
    self.datePicker=[UIDatePicker new];self.datePicker.datePickerMode=UIDatePickerModeDateAndTime;self.datePicker.preferredDatePickerStyle=UIDatePickerStyleWheels;self.datePicker.minuteInterval=1;
    self.datePicker.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];self.datePicker.timeZone=NSTimeZone.localTimeZone;self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:120];self.datePicker.date=[self selectedMinute];self.datePicker.accessibilityIdentifier=@"WDG.FireAt";
    self.timeValue=[self rowValue:nil mono:YES];
    self.timeButton=[self rowWithSymbol:@"clock" title:[self rowTitle:@"开抢时间"] detail:[self rowDetail:@"点按选择 · 秒归零"] value:self.timeValue chevron:YES];
    self.timeButton.accessibilityIdentifier=@"WDG.OpenTimePicker";[self.timeButton addTarget:self action:@selector(showTimePicker) forControlEvents:UIControlEventTouchUpInside];
    self.clockDetail=[self rowDetail:nil];self.clockDetail.text=[self clockSummary:WDGCore.shared.status[@"clock"]];
    UIControl *clockRow=[self rowWithSymbol:@"arrow.triangle.2.circlepath" title:[self rowTitle:@"时钟校准"] detail:self.clockDetail value:nil chevron:YES];
    clockRow.accessibilityIdentifier=@"WDG.ClockRow";clockRow.accessibilityLabel=@"时钟校准，点按查看来源与说明";[clockRow addTarget:self action:@selector(readServerClock) forControlEvents:UIControlEventTouchUpInside];
    UIView *amountBox=[UIView new];amountBox.translatesAutoresizingMaskIntoConstraints=NO;
    UILabel *currency=[self label:18 weight:UIFontWeightMedium];currency.text=@"¥";currency.textColor=UIColor.secondaryLabelColor;currency.numberOfLines=1;
    self.maximumAmount=[UITextField new];self.maximumAmount.placeholder=@"0.00";self.maximumAmount.borderStyle=UITextBorderStyleNone;self.maximumAmount.backgroundColor=UIColor.clearColor;self.maximumAmount.keyboardType=UIKeyboardTypeDecimalPad;self.maximumAmount.textAlignment=NSTextAlignmentRight;self.maximumAmount.font=[UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightSemibold];self.maximumAmount.textColor=UIColor.labelColor;self.maximumAmount.tintColor=[self accent];self.maximumAmount.adjustsFontSizeToFitWidth=YES;self.maximumAmount.minimumFontSize=16;self.maximumAmount.accessibilityLabel=@"最高实付金额，含运费";self.maximumAmount.accessibilityIdentifier=@"WDG.MaximumTotal";self.maximumAmount.translatesAutoresizingMaskIntoConstraints=NO;
    UIToolbar *toolbar=[UIToolbar new];toolbar.tintColor=[self accent];[toolbar sizeToFit];toolbar.items=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(endEditing)]];self.maximumAmount.inputAccessoryView=toolbar;
    [amountBox addSubview:currency];[amountBox addSubview:self.maximumAmount];
    [NSLayoutConstraint activateConstraints:@[[currency.leadingAnchor constraintEqualToAnchor:amountBox.leadingAnchor],[currency.centerYAnchor constraintEqualToAnchor:amountBox.centerYAnchor],[self.maximumAmount.leadingAnchor constraintEqualToAnchor:currency.trailingAnchor constant:4],[self.maximumAmount.trailingAnchor constraintEqualToAnchor:amountBox.trailingAnchor],[self.maximumAmount.centerYAnchor constraintEqualToAnchor:amountBox.centerYAnchor],[self.maximumAmount.widthAnchor constraintEqualToConstant:104],[self.maximumAmount.heightAnchor constraintEqualToConstant:32],[amountBox.heightAnchor constraintEqualToConstant:32]]];
    [amountBox addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusAmount)]];
    UIView *money=[self rowWithSymbol:@"creditcard" title:[self rowTitle:@"最高实付"] detail:[self rowDetail:@"含运费 · 超上限即停"] value:amountBox chevron:NO];
    money.accessibilityIdentifier=@"WDG.AmountRow";
    UIStackView *rows=[[UIStackView alloc] initWithArrangedSubviews:@[product,[self hairline],self.timeButton,[self hairline],clockRow,[self hairline],money]];
    rows.axis=UILayoutConstraintAxisVertical;rows.spacing=0;[stack addArrangedSubview:rows];
    self.lanesBadge=[self label:11 weight:UIFontWeightSemibold];self.lanesBadge.text=@"2 路并发 · 可能重复下单";self.lanesBadge.textColor=[self accent];self.lanesBadge.numberOfLines=1;self.lanesBadge.hidden=YES;self.lanesBadge.accessibilityIdentifier=@"WDG.ConcurrentLanesBadge";[stack addArrangedSubview:self.lanesBadge];
    self.statusDot=[UIView new];self.statusDot.layer.cornerRadius=3;self.statusDot.backgroundColor=[self accent];self.statusDot.translatesAutoresizingMaskIntoConstraints=NO;
    [self.statusDot.widthAnchor constraintEqualToConstant:6].active=YES;[self.statusDot.heightAnchor constraintEqualToConstant:6].active=YES;
    self.statusLabel=[self label:12 weight:UIFontWeightMedium];self.statusLabel.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];self.statusLabel.textColor=UIColor.secondaryLabelColor;self.statusLabel.numberOfLines=1;self.statusLabel.adjustsFontSizeToFitWidth=YES;self.statusLabel.minimumScaleFactor=0.85;self.statusLabel.accessibilityIdentifier=@"WDG.Countdown";
    UIStackView *statusRow=[[UIStackView alloc] initWithArrangedSubviews:@[self.statusDot,self.statusLabel]];statusRow.axis=UILayoutConstraintAxisHorizontal;statusRow.alignment=UIStackViewAlignmentCenter;statusRow.spacing=6;[stack addArrangedSubview:statusRow];
    self.statusDetail=[self label:12 weight:UIFontWeightRegular];self.statusDetail.textColor=UIColor.secondaryLabelColor;self.statusDetail.numberOfLines=1;self.statusDetail.adjustsFontSizeToFitWidth=YES;self.statusDetail.minimumScaleFactor=0.85;self.statusDetail.hidden=YES;[stack addArrangedSubview:self.statusDetail];
    self.primaryButton=[UIButton buttonWithType:UIButtonTypeSystem];self.primaryButton.backgroundColor=[self accent];self.primaryButton.layer.cornerRadius=kWDGButtonRadius;self.primaryButton.layer.cornerCurve=kCACornerCurveContinuous;[self.primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];self.primaryButton.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];[self.primaryButton setTitle:@"准备抢购" forState:UIControlStateNormal];self.primaryButton.accessibilityIdentifier=@"WDG.ArmTask";[self.primaryButton.heightAnchor constraintEqualToConstant:kWDGButtonHeight].active=YES;[self.primaryButton addTarget:self action:@selector(schedule) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:self.primaryButton];
    self.cancelButton=[UIButton buttonWithType:UIButtonTypeSystem];self.cancelButton.tintColor=UIColor.secondaryLabelColor;self.cancelButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];[self.cancelButton setTitle:@"取消任务" forState:UIControlStateNormal];[self.cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];self.cancelButton.accessibilityIdentifier=@"WDG.CancelTask";self.cancelButton.hidden=YES;[stack addArrangedSubview:self.cancelButton];
    self.versionLabel=[self label:10 weight:UIFontWeightRegular];self.versionLabel.textColor=UIColor.tertiaryLabelColor;self.versionLabel.textAlignment=NSTextAlignmentCenter;self.versionLabel.numberOfLines=1;[stack addArrangedSubview:self.versionLabel];
    [self updateTimeDisplay];
}
- (void)focusAmount {if(self.maximumAmount.enabled)[self.maximumAmount becomeFirstResponder];}
- (void)endEditing {[self.card endEditing:YES];}
- (void)updateTimeDisplay {
    NSDate *date=[self selectedMinute];NSCalendar *calendar=NSCalendar.currentCalendar;NSDateFormatter *df=[NSDateFormatter new];df.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];df.timeZone=self.datePicker.timeZone?:NSTimeZone.localTimeZone;
    df.dateFormat=@"HH:mm";NSString *clock=[df stringFromDate:date];NSString *day=nil;
    if([calendar isDateInToday:date])day=@"今天";else if([calendar isDateInTomorrow:date])day=@"明天";else {df.dateFormat=@"M月d日";day=[df stringFromDate:date];}
    self.timeValue.text=[NSString stringWithFormat:@"%@ %@",day,clock];self.timeButton.accessibilityLabel=[NSString stringWithFormat:@"开抢时间，%@，精确到整分钟",self.timeValue.text];
}
- (void)showTimePicker {
    if(!self.timeButton.enabled||self.timeSheet)return;[self endEditing];self.dateBeforeEditing=self.datePicker.date;
    UIViewController *sheet=[UIViewController new];self.timeSheet=sheet;sheet.modalPresentationStyle=UIModalPresentationPageSheet;sheet.view.backgroundColor=UIColor.systemBackgroundColor;sheet.preferredContentSize=CGSizeMake(376,360);
    UIButton *cancel=[UIButton buttonWithType:UIButtonTypeSystem];[cancel setTitle:@"取消" forState:UIControlStateNormal];cancel.tintColor=UIColor.secondaryLabelColor;[cancel addTarget:self action:@selector(cancelTimePicker) forControlEvents:UIControlEventTouchUpInside];
    UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem];[done setTitle:@"完成" forState:UIControlStateNormal];done.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];done.tintColor=[self accent];[done addTarget:self action:@selector(finishTimePicker) forControlEvents:UIControlEventTouchUpInside];
    UILabel *title=[self label:17 weight:UIFontWeightSemibold];title.text=@"选择开抢时间";title.textAlignment=NSTextAlignmentCenter;
    [cancel.widthAnchor constraintEqualToConstant:48].active=YES;[done.widthAnchor constraintEqualToConstant:48].active=YES;
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[cancel,title,done]];header.axis=UILayoutConstraintAxisHorizontal;header.alignment=UIStackViewAlignmentCenter;header.spacing=8;header.translatesAutoresizingMaskIntoConstraints=NO;[sheet.view addSubview:header];
    UILabel *hint=[self label:12 weight:UIFontWeightRegular];hint.text=[NSString stringWithFormat:@"公告时刻 · %@ · 秒为 00",(self.datePicker.timeZone?:NSTimeZone.localTimeZone).name];hint.textColor=UIColor.secondaryLabelColor;hint.textAlignment=NSTextAlignmentCenter;hint.translatesAutoresizingMaskIntoConstraints=NO;[sheet.view addSubview:hint];
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
    if(items.count){NSDictionary *first=items.firstObject;self.productLabel.text=first[@"title"]?:@"购物车商品";self.detailLabel.text=[NSString stringWithFormat:@"%@ · %@ × %@%@",source,first[@"skuTitle"]?:@"未选规格",first[@"quantity"]?:@"?",items.count>1?[NSString stringWithFormat:@" · 共 %lu 条",(unsigned long)items.count]:@""];}
    else {self.productLabel.text=@"选择要抢的商品";self.detailLabel.text=@"跟随购物车勾选 · 点此手动指定";}
    BOOL active=[@[@"armed",@"firing",@"preheating",@"waitingSale",@"sending"] containsObject:phase],unknown=[phase isEqual:@"unknown"];
    if([@[@"armed",@"waitingSale"] containsObject:phase]){NSTimeInterval s=MAX(0,[task[@"dueAt"] doubleValue]-NSDate.date.timeIntervalSince1970);self.statusLabel.text=[NSString stringWithFormat:@"距离开抢 %02ld:%02ld:%02ld · 保持前台",(long)(s/3600),(long)((NSInteger)s/60%60),(long)((NSInteger)s%60)];}
    else self.statusLabel.text=@{@"idle":@"待准备 · 保持微店前台",@"firing":@"准备中 · 正在提交",@"preheating":@"正在确认商品",@"sending":@"已提交 · 等待结果",@"apiSucceeded":@"接口已返回成功 · 请核对订单",@"failed":@"本次未完成",@"cancelled":@"任务已取消",@"fired":@"本地演练完成",@"unknown":@"订单结果待核对"}[phase]?:@"待准备";
    NSUInteger lanes=(active||unknown)?MAX((NSUInteger)1,[task[@"concurrentLanes"] unsignedIntegerValue]):self.concurrentLanes;
    self.lanesBadge.hidden=lanes!=2;
    NSString *reason=task[@"reason"];
    self.statusDetail.text=reason;self.statusDetail.hidden=!reason.length;
    UIColor *statusColor=[phase isEqual:@"apiSucceeded"]?UIColor.systemGreenColor:((unknown||[phase isEqual:@"failed"])?UIColor.systemOrangeColor:[self accent]);
    self.statusDot.backgroundColor=statusColor;self.statusLabel.textColor=UIColor.secondaryLabelColor;
    self.primaryButton.enabled=!active&&!unknown;self.primaryButton.alpha=self.primaryButton.enabled?1:0.52;
    [self.primaryButton setTitle:active?@"已准备，等待执行":(unknown?@"请先核对订单结果":@"准备抢购") forState:UIControlStateNormal];
    self.cancelButton.hidden=!active;self.datePicker.enabled=!active&&!unknown;self.timeButton.enabled=!active&&!unknown;self.timeButton.alpha=self.timeButton.enabled?1:0.6;self.maximumAmount.enabled=!active&&!unknown;
    self.clockDetail.text=[self clockSummary:state[@"clock"]];
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
- (NSString *)clockSummary:(NSDictionary *)clock {
    if([clock[@"valid"] boolValue]&&[clock[@"status"] isEqual:@"native_recent"]&&[clock[@"offsetMs"] isKindOfClass:NSNumber.class])
        return [NSString stringWithFormat:@"微店时钟 %+.0f ms",[clock[@"offsetMs"] doubleValue]];
    return @"本地时间 · 尚无有效校准样本";
}
- (NSDate *)localDeadlineForDate:(NSDate *)date clockSnapshot:(NSDictionary **)snapshot {
    [WDGCore.shared refreshServerClock];
    NSDictionary *clock=[WDGCore.shared.status[@"clock"] copy];NSString *reason=nil;
    NSDate *local=WDGLocalDeadlineFromClock(date,clock,&reason);
    if(!local){
        local=date;NSMutableDictionary *fallback=[clock mutableCopy];
        fallback[@"valid"]=@NO;fallback[@"offsetMs"]=NSNull.null;
        fallback[@"reason"]=[clock[@"valid"] boolValue]?(reason?:@"读取样本已失效"):(clock[@"reason"]?:reason?:@"尚无有效校准样本");clock=[fallback copy];
    }
    if(snapshot)*snapshot=clock;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970,announcedDelta=date.timeIntervalSince1970-now,localDelta=local.timeIntervalSince1970-now;
    if(!date||!isfinite(announcedDelta)||announcedDelta<2||announcedDelta>43200||!isfinite(localDelta)||localDelta<2||localDelta>43200){
        [self alert:@"请重新选择开抢时间" message:@"公告时刻与本地执行时刻都须在未来 2 秒至 12 小时内；时差校正后也按此范围校验。 "];return nil;
    }
    return local;
}
- (NSString *)clockReview:(NSDictionary *)clock announced:(NSDate *)date localDue:(NSDate *)localDue {
    NSTimeZone *zone=self.datePicker.timeZone?:NSTimeZone.localTimeZone;
    NSDateFormatter *df=[NSDateFormatter new];df.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];df.timeZone=zone;df.dateFormat=@"yyyy-MM-dd HH:mm:ss.SSS ZZZZ";
    BOOL native=[clock[@"valid"] boolValue]&&[clock[@"status"] isEqual:@"native_recent"];
    NSString *mode=native?@"按微店时钟校正一次":@"回退：明确按本地时间运行（不应用新样本）";
    return [NSString stringWithFormat:@"公告时刻：%@\n时区：%@\n本地%@时刻：%@\n%@\n%@\n来源：%@ · %@\n%@\n只读 App 已有样本，未网络测 RTT；偏差不是精度保证。",
        [df stringFromDate:date],zone.name,native?@"校正":@"执行",[df stringFromDate:localDue],mode,[self clockSummary:clock],clock[@"source"]?:@"none",clock[@"status"]?:@"unavailable",clock[@"reason"]?:@""];
}
- (void)readServerClock {
    [WDGCore.shared refreshServerClock];NSDictionary *clock=WDGCore.shared.status[@"clock"];[self refresh];
    BOOL native=[clock[@"valid"] boolValue]&&[clock[@"status"] isEqual:@"native_recent"];
    NSString *title=native?[self clockSummary:clock]:@"本地时间 · 未校准";
    NSString *source=clock[@"source"]?:@"none";
    if([source isEqual:@"WDTNServerClockProofreader"])source=@"微店原生";
    NSMutableString *message=[NSMutableString stringWithFormat:@"来源 %@ · %@",source,clock[@"status"]?:@"unavailable"];
    [message appendString:native?@"\n快照 5 秒内有效":@"\n无有效样本 · 按本地时间执行"];
    NSString *reason=clock[@"reason"],*note=@"偏差不代表毫秒精度";
    if(!native&&reason.length)note=[NSString stringWithFormat:@"原因 %@",reason.length>20?[[reason substringToIndex:20] stringByAppendingString:@"…"]:reason];
    [message appendFormat:@"\n%@",note];
    [message appendString:@"\n不联网 · 不改系统时间"];
    UIAlertController *detail=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakDetail=detail;
    [detail addAction:[UIAlertAction actionWithTitle:@"说明" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        UIAlertController *alert=weakDetail;if(!alert)return;
        [alert dismissViewControllerAnimated:YES completion:^{[self explainServerClock];}];
    }]];
    [detail addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [self.window.rootViewController presentViewController:detail animated:YES completion:nil];
}
- (void)explainServerClock {
    [self alert:@"时钟说明" message:@"只读微店缓存样本，不联网。\n不测 RTT，不改系统时钟。\n显示偏差，非毫秒精度。\n只影响下一笔任务。\n确认与执行前会重核对。"];
}
- (void)validateCartParameters {
    NSDecimalNumber *maximum=[self maximumValue];if(!maximum)return;
    NSDate *date=[self selectedMinute];NSDictionary *clock=nil;NSDate *localDue=[self localDeadlineForDate:date clockSnapshot:&clock];if(!localDue)return;
    NSString *key=[WDGCartSnapshotKey() copy];if(!key.length){[self alert:@"先选好商品" message:@"刷新购物车或点商品卡选择目标。 "];return;}
    NSError *error=nil;id request=WDGCartBuildRequest(&error);
    WDGOrderService *s=request?[WDGOrderService preparePreheatRequest:request sampleKey:key payType:nil error:&error]:nil;
    if(![key isEqual:WDGCartSnapshotKey()]){[self alert:@"目标已变化" message:@"请重新选择后校验。 "];return;}
    if(!s||![s configureConcurrentLanes:self.concurrentLanes==2?2:1 error:&error]||![s configureCartDueAt:localDue maximumTotal:maximum error:&error]){[self alert:@"本地校验未通过" message:error.localizedDescription?:@"请核对商品和规格。 "];return;}
    [self endEditing];[self alert:@"本地参数校验成功" message:[NSString stringWithFormat:@"%@\n\n商品请求、原生服务与金额参数已就绪。未联网，未设置任务，未调用确认或创建订单接口。最终地址、运费及实付仍由服务端确认。",[self clockReview:clock announced:date localDue:localDue]]];
}
- (void)schedule {
    NSDecimalNumber *maximum=[self maximumValue];if(!maximum)return;[self endEditing];
    NSArray *items=[[NSArray alloc] initWithArray:WDGCartSelectedLines() copyItems:YES];NSString *key=[WDGCartSnapshotKey() copy];NSArray *keys=[[items valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];
    if(!items.count||!key.length){[self alert:@"先选好商品" message:@"刷新购物车或点商品卡选择目标。 "];return;}
    NSDate *date=[self selectedMinute];NSDictionary *clock=nil;NSDate *localDue=[self localDeadlineForDate:date clockSnapshot:&clock];if(!localDue)return;
    NSUInteger lanes=self.concurrentLanes==2?2:1;
    NSDecimalNumber *total=[maximum decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithMantissa:lanes exponent:0 isNegative:NO]];
    NSMutableString *message=[NSMutableString string];for(NSDictionary *item in items)[message appendFormat:@"%@\n%@ × %@\n\n",item[@"title"]?:@"商品",item[@"skuTitle"]?:@"未选规格",item[@"quantity"]?:@"?"];
    [message appendFormat:@"%@\n\n每单最高实付（含运费）：¥%@\n支付：采用微店确认结果的已选方式\n\n",[self clockReview:clock announced:date localDue:localDue],[self formattedAmount:maximum]];
    if(lanes==2)[message appendFormat:@"双路竞速：同商品最多2单\n最高总扣款上限：¥%@（每单上限 × 2）\n\n到点发出 2 路真实下单请求，可能重复下单。已发出的请求可能各自成功，首个成功不会撤销另一已发请求。请保持微店前台。",[self formattedAmount:total]];
    else [message appendFormat:@"单路：最多 1 单\n最高总扣款上限：¥%@\n\n到点将直接创建一次真实订单，不打开支付链接。请保持微店前台。",[self formattedAmount:total]];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:lanes==2?@"确认双路竞速任务":@"确认这笔任务" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"再看看" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:lanes==2?@"确认双路 · 接受最多2单":@"确认单路 · 最多1单" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *v){NSArray *nowKeys=[[WDGCartSelectedLines() valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];if(![key isEqual:WDGCartSnapshotKey()]||![keys isEqual:nowKeys]){[self alert:@"购物车目标已变化" message:@"请重新核对商品和规格。 "];return;}NSError *error=nil;if(![WDGCore.shared armCartAt:date maximumTotal:maximum concurrentLanes:lanes clockSnapshot:clock error:&error])[self alert:@"任务未设置" message:error.localizedDescription];}]];
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
    BOOL adsOn=[WDGCore.shared.status[@"ads"][@"enabled"] boolValue];
    [a addAction:[UIAlertAction actionWithTitle:adsOn?@"去广告：已开启（点按关闭）":@"去广告：已关闭（点按开启）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){[WDGCore.shared setAdsEnabled:!adsOn];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"读取微店时钟" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *v){[self readServerClock];}]];
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
