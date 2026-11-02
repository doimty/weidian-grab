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
static const CGFloat kWDGCardMaxHeightRatio=0.72;
static const CGFloat kWDGFooterHitHeight=44;
static const CGFloat kWDGScrollFooterGap=12;
static const CGFloat kWDGCardMaxWidth=376;
static const CGFloat kWDGCardScreenMargin=32;
static const CGFloat kWDGOverlayScrimAlpha=0.45;
static const CGFloat kWDGOverlayScale=0.98;
static const CGFloat kWDGOverlayDuration=0.18;
static const CGFloat kWDGOverlayMaxHeightRatio=0.70;
static const CGFloat kWDGTimeCardMaxHeightRatio=0.88;
static const CGFloat kWDGOverlayVerticalBias=0.92;

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

typedef void (^WDGSheetBlock)(void);
typedef void (^WDGSheetCloseRequest)(WDGSheetBlock action);

static UIColor *WDGSheetAccent(void) {return [UIColor colorWithRed:0.90 green:0.14 blue:0.30 alpha:1];}
static NSDictionary *WDGSheetRow(NSString *label,NSString *value,BOOL mono) {return @{@"label":label?:@"",@"value":value?:@"",@"mono":@(mono)};}

// 面板窗口内的浮层：全屏遮罩 + 与面板卡片同宽的居中卡片，菜单与确认框共用这一套视觉与动画。
@interface WDGOverlayView : UIView
@property(nonatomic,strong,readonly) UIView *card;
@property(nonatomic,copy) void (^scrimAction)(void);
@property(nonatomic,assign) BOOL tornDown;
- (instancetype)initWithCardWidth:(CGFloat)width maxHeightRatio:(CGFloat)ratio;
- (void)presentWithCompletion:(void (^)(void))completion;
- (void)dismissWithCompletion:(void (^)(void))completion;
- (void)removeImmediately;
@end

@implementation WDGOverlayView {
    UIControl *_scrim;
}
- (instancetype)initWithCardWidth:(CGFloat)width maxHeightRatio:(CGFloat)ratio {
    if((self=[super init])) {
        self.translatesAutoresizingMaskIntoConstraints=NO;self.backgroundColor=UIColor.clearColor;self.accessibilityViewIsModal=YES;self.alpha=0;
        _scrim=[UIControl new];_scrim.translatesAutoresizingMaskIntoConstraints=NO;
        _scrim.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:kWDGOverlayScrimAlpha];
        _scrim.accessibilityLabel=@"关闭浮层";
        [_scrim addTarget:self action:@selector(tapScrim) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_scrim];
        _card=[UIView new];_card.translatesAutoresizingMaskIntoConstraints=NO;
        _card.backgroundColor=UIColor.systemBackgroundColor;
        // Keep controls vivid: an alert-level overlay window can be treated as
        // inactive, which desaturates switches and icons.
        _card.tintAdjustmentMode=UIViewTintAdjustmentModeNormal;
        _card.layer.cornerRadius=kWDGCardRadius;_card.layer.cornerCurve=kCACornerCurveContinuous;
        _card.layer.shadowColor=UIColor.blackColor.CGColor;_card.layer.shadowOpacity=0.08;
        _card.layer.shadowRadius=18;_card.layer.shadowOffset=CGSizeMake(0,8);
        [self addSubview:_card];
        UILayoutGuide *centerGuide=[UILayoutGuide new];[self addLayoutGuide:centerGuide];
        [NSLayoutConstraint activateConstraints:@[
            [_scrim.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_scrim.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_scrim.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_scrim.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [centerGuide.topAnchor constraintEqualToAnchor:self.topAnchor],
            [centerGuide.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:kWDGOverlayVerticalBias],
            [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_card.centerYAnchor constraintEqualToAnchor:centerGuide.centerYAnchor],
            [_card.widthAnchor constraintEqualToConstant:width],
            [_card.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:16],
            [_card.bottomAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-16],
            [_card.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor multiplier:ratio]]];
    }
    return self;
}
- (void)tapScrim {if(self.scrimAction)self.scrimAction();}
- (void)presentWithCompletion:(void (^)(void))completion {
    self.userInteractionEnabled=NO;self.alpha=0;
    self.card.transform=CGAffineTransformMakeScale(kWDGOverlayScale,kWDGOverlayScale);
    [UIView animateWithDuration:kWDGOverlayDuration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.alpha=1;self.card.transform=CGAffineTransformIdentity;
    } completion:^(BOOL finished){self.userInteractionEnabled=YES;if(completion)completion();}];
}
- (void)dismissWithCompletion:(void (^)(void))completion {
    self.userInteractionEnabled=NO;
    [UIView animateWithDuration:kWDGOverlayDuration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.alpha=0;self.card.transform=CGAffineTransformMakeScale(kWDGOverlayScale,kWDGOverlayScale);
    } completion:^(BOOL finished){
        [self removeFromSuperview];
        if(completion)completion();
    }];
}
- (void)removeImmediately {
    self.tornDown=YES;
    [self.layer removeAllAnimations];[self.card.layer removeAllAnimations];
    [self removeFromSuperview];
}
@end

@interface WDGSheetController : NSObject {
    UIView *_contentView;
}
@property(nonatomic,copy) NSString *sheetTitle;
@property(nonatomic,copy) NSArray<NSDictionary *> *sheetRows;
@property(nonatomic,copy) NSString *sheetFootnote;
@property(nonatomic,assign) BOOL footnoteWarning;
@property(nonatomic,copy) NSString *primaryTitle;
@property(nonatomic,copy) NSString *secondaryTitle;
@property(nonatomic,copy) WDGSheetBlock primaryAction;
@property(nonatomic,copy) WDGSheetBlock secondaryAction;
@property(nonatomic,copy) WDGSheetCloseRequest requestClose;
@property(nonatomic,strong,readonly) UIView *contentView;
@property(nonatomic,assign) BOOL dismissed;
+ (instancetype)sheetWithTitle:(NSString *)title rows:(NSArray<NSDictionary *> *)rows footnote:(NSString *)footnote warning:(BOOL)warning primaryTitle:(NSString *)primaryTitle primaryAction:(WDGSheetBlock)primaryAction secondaryTitle:(NSString *)secondaryTitle;
@end

@implementation WDGSheetController
+ (instancetype)sheetWithTitle:(NSString *)title rows:(NSArray<NSDictionary *> *)rows footnote:(NSString *)footnote warning:(BOOL)warning primaryTitle:(NSString *)primaryTitle primaryAction:(WDGSheetBlock)primaryAction secondaryTitle:(NSString *)secondaryTitle {
    WDGSheetController *sheet=[self new];
    sheet.sheetTitle=title;sheet.sheetRows=rows;sheet.sheetFootnote=footnote;sheet.footnoteWarning=warning;
    sheet.primaryTitle=primaryTitle;sheet.primaryAction=primaryAction;sheet.secondaryTitle=secondaryTitle;
    return sheet;
}
- (UIView *)contentView {
    if(!_contentView)[self buildContentView];
    return _contentView;
}
- (void)buildContentView {
    UIView *root=[UIView new];root.translatesAutoresizingMaskIntoConstraints=NO;root.backgroundColor=UIColor.clearColor;
    _contentView=root;
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.showsVerticalScrollIndicator=NO;scroll.showsHorizontalScrollIndicator=NO;scroll.alwaysBounceVertical=NO;scroll.alwaysBounceHorizontal=NO;
    scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[root addSubview:scroll];
    NSLayoutConstraint *fitsContent=[scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor];fitsContent.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kWDGPadding],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kWDGPadding],
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor constant:kWDGPadding],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kWDGPadding],
        fitsContent]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *title=[UILabel new];title.translatesAutoresizingMaskIntoConstraints=NO;title.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];title.textColor=UIColor.labelColor;title.numberOfLines=0;title.text=self.sheetTitle;
    [stack addArrangedSubview:title];[stack setCustomSpacing:14 afterView:title];
    if(self.sheetRows.count){
        NSMutableArray<UIView *> *views=[NSMutableArray array];
        [self.sheetRows enumerateObjectsUsingBlock:^(NSDictionary *row,NSUInteger index,__unused BOOL *stop){if(index>0)[views addObject:[self separatorLine]];[views addObject:[self rowView:row]];}];
        UIStackView *rows=[[UIStackView alloc] initWithArrangedSubviews:views];rows.axis=UILayoutConstraintAxisVertical;rows.spacing=0;rows.translatesAutoresizingMaskIntoConstraints=NO;
        [stack addArrangedSubview:rows];[stack setCustomSpacing:14 afterView:rows];
    }
    if(self.sheetFootnote.length){
        UILabel *note=[UILabel new];note.translatesAutoresizingMaskIntoConstraints=NO;note.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];note.numberOfLines=0;note.text=self.sheetFootnote;
        note.textColor=self.footnoteWarning?UIColor.systemOrangeColor:UIColor.secondaryLabelColor;
        [stack addArrangedSubview:note];[stack setCustomSpacing:16 afterView:note];
    }
    if(self.primaryTitle.length){
        UIButton *primary=[UIButton buttonWithType:UIButtonTypeSystem];primary.translatesAutoresizingMaskIntoConstraints=NO;
        primary.backgroundColor=WDGSheetAccent();primary.layer.cornerRadius=kWDGButtonRadius;primary.layer.cornerCurve=kCACornerCurveContinuous;primary.clipsToBounds=YES;
        [primary setTitle:self.primaryTitle forState:UIControlStateNormal];[primary setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        primary.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [primary.heightAnchor constraintEqualToConstant:kWDGButtonHeight].active=YES;
        [primary addTarget:self action:@selector(tapPrimary) forControlEvents:UIControlEventTouchUpInside];primary.accessibilityIdentifier=@"WDG.SheetPrimary";
        [stack addArrangedSubview:primary];[stack setCustomSpacing:4 afterView:primary];
    }
    if(self.secondaryTitle.length){
        UIButton *secondary=[UIButton buttonWithType:UIButtonTypeSystem];secondary.translatesAutoresizingMaskIntoConstraints=NO;secondary.tintColor=UIColor.secondaryLabelColor;
        [secondary setTitle:self.secondaryTitle forState:UIControlStateNormal];secondary.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        [secondary.heightAnchor constraintEqualToConstant:40].active=YES;
        [secondary addTarget:self action:@selector(tapSecondary) forControlEvents:UIControlEventTouchUpInside];secondary.accessibilityIdentifier=@"WDG.SheetSecondary";
        [stack addArrangedSubview:secondary];
    }
}
- (UIView *)separatorLine {
    UIView *line=[UIView new];line.translatesAutoresizingMaskIntoConstraints=NO;line.userInteractionEnabled=NO;
    line.backgroundColor=[UIColor.separatorColor colorWithAlphaComponent:0.5];
    [line.heightAnchor constraintEqualToConstant:kWDGHairlineHeight].active=YES;return line;
}
- (UIView *)rowView:(NSDictionary *)row {
    UIView *box=[UIView new];box.translatesAutoresizingMaskIntoConstraints=NO;
    UILabel *left=[UILabel new];left.translatesAutoresizingMaskIntoConstraints=NO;left.font=[UIFont systemFontOfSize:13 weight:UIFontWeightRegular];left.textColor=UIColor.secondaryLabelColor;left.text=row[@"label"];left.numberOfLines=1;
    [left setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *right=[UILabel new];right.translatesAutoresizingMaskIntoConstraints=NO;
    right.font=[row[@"mono"] boolValue]?[UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold]:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    right.textColor=UIColor.labelColor;right.text=row[@"value"];right.numberOfLines=1;right.textAlignment=NSTextAlignmentRight;
    right.lineBreakMode=[row[@"middle"] boolValue]?NSLineBreakByTruncatingMiddle:NSLineBreakByTruncatingTail;
    [right setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [box addSubview:left];[box addSubview:right];
    [NSLayoutConstraint activateConstraints:@[
        [left.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [left.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [right.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [right.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [left.trailingAnchor constraintLessThanOrEqualToAnchor:right.leadingAnchor constant:-12],
        [box.heightAnchor constraintEqualToConstant:44]]];
    return box;
}
- (void)tapPrimary {
    if(self.dismissed||!self.requestClose)return;
    WDGSheetBlock action=[self.primaryAction copy];self.primaryAction=nil;self.secondaryAction=nil;
    self.dismissed=YES;self.requestClose(action);
}
- (void)tapSecondary {
    if(self.dismissed||!self.requestClose)return;
    WDGSheetBlock action=[self.secondaryAction copy];self.primaryAction=nil;self.secondaryAction=nil;
    self.dismissed=YES;self.requestClose(action);
}
@end

static const CGFloat kWDGMenuRowHeight=52;
static const CGFloat kWDGMenuCheckSide=16;
static const CGFloat kWDGMenuCancelGap=8;

@interface WDGSwitch : UISwitch
@property(nonatomic,copy) void (^onToggle)(BOOL on);
@end
@implementation WDGSwitch
- (void)fireToggle { if(self.onToggle) self.onToggle(self.isOn); }
- (void)layoutSubviews {
    [super layoutSubviews];
    self.tintAdjustmentMode=UIViewTintAdjustmentModeNormal;
    UIColor *accent=[UIColor colorWithRed:0.90 green:0.14 blue:0.30 alpha:1.0];
    if(![self.onTintColor isEqual:accent]) self.onTintColor=accent;
}
@end

@interface WDGMenuItem : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,assign) BOOL checked;
@property(nonatomic,assign) BOOL destructive;
@property(nonatomic,assign) BOOL enabled;
@property(nonatomic,assign) BOOL isSwitch;
@property(nonatomic,assign) BOOL showsChevron;
@property(nonatomic,assign) BOOL switchOn;
@property(nonatomic,copy) WDGSheetBlock action;
@property(nonatomic,copy) void (^switchHandler)(BOOL on);
+ (instancetype)itemWithTitle:(NSString *)title checked:(BOOL)checked destructive:(BOOL)destructive action:(WDGSheetBlock)action;
+ (instancetype)switchItemWithTitle:(NSString *)title on:(BOOL)on handler:(void (^)(BOOL on))handler;
@end

@implementation WDGMenuItem
- (instancetype)init {if((self=[super init]))_enabled=YES;return self;}
+ (instancetype)itemWithTitle:(NSString *)title checked:(BOOL)checked destructive:(BOOL)destructive action:(WDGSheetBlock)action {
    WDGMenuItem *item=[self new];item.title=title?:@"";item.checked=checked;item.destructive=destructive;item.action=action;return item;
}
+ (instancetype)switchItemWithTitle:(NSString *)title on:(BOOL)on handler:(void (^)(BOOL))handler {
    WDGMenuItem *item=[self new];item.title=title?:@"";item.isSwitch=YES;item.switchOn=on;item.switchHandler=handler;return item;
}
@end

@interface WDGPanel : NSObject
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
@property(nonatomic,strong) UIButton *exportLink;
@property(nonatomic,strong) UIView *statusDot;
@property(nonatomic,strong) UILabel *lanesBadge;
@property(nonatomic,strong) UILabel *clockDetail;
@property(nonatomic,strong) UIDatePicker *datePicker;
@property(nonatomic,strong) UIControl *timeButton;
@property(nonatomic,strong) UILabel *timeValue;
@property(nonatomic,strong) NSDate *dateBeforeEditing;
@property(nonatomic,strong) UITextField *maximumAmount;
@property(nonatomic,strong) UIButton *primaryButton;
@property(nonatomic,strong) UIButton *cancelButton;
@property(nonatomic,strong) NSTimer *refreshTimer;
@property(nonatomic,assign) NSUInteger concurrentLanes;
@property(nonatomic,strong) WDGOverlayView *overlay;
@property(nonatomic,assign) BOOL overlayBusy;
@property(nonatomic,copy) NSArray<WDGMenuItem *> *menuItems;
@property(nonatomic,strong) WDGSheetController *activeSheet;
+ (instancetype)shared;
- (void)presentSheet:(WDGSheetController *)sheet;
- (void)presentMenuWithTitle:(NSString *)title subtitle:(NSString *)subtitle items:(NSArray<WDGMenuItem *> *)items;
- (void)dismissOverlayWithAction:(WDGSheetBlock)action;
- (void)removeOverlayImmediately;
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
- (UIButton *)textLink:(NSString *)text action:(SEL)selector {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.translatesAutoresizingMaskIntoConstraints=NO;
    b.backgroundColor=UIColor.clearColor;b.layer.borderWidth=0;b.tintColor=UIColor.secondaryLabelColor;
    NSDictionary<NSAttributedStringKey,id> *attributes=@{NSFontAttributeName:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName:UIColor.secondaryLabelColor,
        NSUnderlineStyleAttributeName:@(NSUnderlineStyleSingle)};
    [b setAttributedTitle:[[NSAttributedString alloc] initWithString:text attributes:attributes] forState:UIControlStateNormal];
    b.accessibilityLabel=text;[b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (UIView *)hairline {
    UIView *line=[UIView new];line.translatesAutoresizingMaskIntoConstraints=NO;line.userInteractionEnabled=NO;
    line.backgroundColor=[UIColor.separatorColor colorWithAlphaComponent:0.5];
    [line.heightAnchor constraintEqualToConstant:kWDGHairlineHeight].active=YES;return line;
}
- (UILabel *)rowTitle:(NSString *)text {
    UILabel *l=[self label:15 weight:UIFontWeightMedium];l.text=text;l.numberOfLines=1;l.lineBreakMode=NSLineBreakByTruncatingTail;l.userInteractionEnabled=NO;
    [l setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh+1 forAxis:UILayoutConstraintAxisHorizontal];
    [l setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    return l;
}
- (UILabel *)rowDetail:(NSString *)text {
    UILabel *l=[self label:11 weight:UIFontWeightRegular];l.text=text;l.numberOfLines=1;l.lineBreakMode=NSLineBreakByTruncatingTail;l.textColor=UIColor.secondaryLabelColor;l.userInteractionEnabled=NO;
    [l setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh-1 forAxis:UILayoutConstraintAxisHorizontal];
    [l setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    return l;
}
- (UILabel *)rowValue:(NSString *)text mono:(BOOL)mono {
    UILabel *l=[UILabel new];l.font=mono?[UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold]:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    l.text=text;l.textColor=UIColor.labelColor;l.numberOfLines=1;l.textAlignment=NSTextAlignmentRight;l.lineBreakMode=NSLineBreakByClipping;
    [l setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh+10 forAxis:UILayoutConstraintAxisHorizontal];
    [l setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    l.translatesAutoresizingMaskIntoConstraints=NO;l.userInteractionEnabled=NO;return l;
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
    [self ensureWindow];if(!self.window)return;[self removeOverlayImmediately];WDGRefreshTradeSnapshot();
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
    [self removeOverlayImmediately];
    [self.card endEditing:YES];
    if(self.dateBeforeEditing){self.datePicker.date=self.dateBeforeEditing;self.dateBeforeEditing=nil;}
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
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
    CGFloat width=MIN(kWDGCardMaxWidth,self.window.bounds.size.width-kWDGCardScreenMargin);
    [NSLayoutConstraint activateConstraints:@[[self.card.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],[self.card.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],[self.card.widthAnchor constraintEqualToConstant:width],[self.card.topAnchor constraintGreaterThanOrEqualToAnchor:root.topAnchor constant:16],[self.card.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-16]]];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.showsVerticalScrollIndicator=NO;scroll.alwaysBounceVertical=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[self.card addSubview:scroll];
    // 固定底区（状态行 + 可选 statusDetail + 红色主按钮 + 取消 + 版本/诊断行）整块在 scroll 之外：
    // 高度由内容决定、竖直不可压缩，卡片触到 0.72 屏高上限时只压 scroll，底区永远完整可见。
    UIStackView *footer=[UIStackView new];footer.axis=UILayoutConstraintAxisVertical;footer.spacing=kWDGSectionGap;footer.translatesAutoresizingMaskIntoConstraints=NO;
    [footer setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self.card addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:kWDGPadding],
        [scroll.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-kWDGPadding],
        [scroll.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:kWDGPadding],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-kWDGScrollFooterGap],
        [footer.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:kWDGPadding],
        [footer.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-kWDGPadding],
        [footer.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-kWDGPadding]]];
    NSLayoutConstraint *fitsContent=[scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor];fitsContent.priority=UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *softCap=[self.card.heightAnchor constraintLessThanOrEqualToAnchor:root.heightAnchor multiplier:kWDGCardMaxHeightRatio];
    [NSLayoutConstraint activateConstraints:@[fitsContent,softCap]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=kWDGSectionGap;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *title=[self label:23 weight:UIFontWeightBold];title.text=@"准备开抢";
    UIButton *more=[self iconButton:@"ellipsis" action:@selector(showMore) label:@"更多选项"],*close=[self iconButton:@"xmark" action:@selector(closePanel) label:@"收起面板"];
    more.accessibilityIdentifier=@"WDG.More";close.accessibilityIdentifier=@"WDG.ClosePanel";
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[title,more,close]];header.axis=UILayoutConstraintAxisHorizontal;header.alignment=UIStackViewAlignmentCenter;header.spacing=2;[stack addArrangedSubview:header];
    self.productLabel=[self label:15 weight:UIFontWeightMedium];self.productLabel.numberOfLines=2;self.productLabel.userInteractionEnabled=NO;
    self.detailLabel=[self rowDetail:nil];self.detailLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
    UIControl *product=[self rowWithSymbol:@"bag.fill" title:self.productLabel detail:self.detailLabel value:nil chevron:YES];
    product.accessibilityIdentifier=@"WDG.CartTarget";product.accessibilityLabel=@"选择购物车目标";[product addTarget:self action:@selector(chooseCartTarget) forControlEvents:UIControlEventTouchUpInside];
    self.datePicker=[UIDatePicker new];self.datePicker.datePickerMode=UIDatePickerModeDateAndTime;self.datePicker.preferredDatePickerStyle=UIDatePickerStyleWheels;self.datePicker.minuteInterval=1;
    self.datePicker.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];self.datePicker.timeZone=NSTimeZone.localTimeZone;self.datePicker.date=[NSDate dateWithTimeIntervalSinceNow:120];self.datePicker.date=[self selectedMinute];self.datePicker.accessibilityIdentifier=@"WDG.FireAt";
    self.timeValue=[self rowValue:nil mono:YES];
    self.timeButton=[self rowWithSymbol:@"clock" title:[self rowTitle:@"开抢时间"] detail:[self rowDetail:@"点按选择 · 秒归零"] value:self.timeValue chevron:YES];
    self.timeButton.accessibilityIdentifier=@"WDG.OpenTimePicker";[self.timeButton addTarget:self action:@selector(showTimePicker) forControlEvents:UIControlEventTouchUpInside];
    self.clockDetail=[self rowDetail:nil];self.clockDetail.text=[self clockSummary:WDGCore.shared.status[@"clock"]];
    UIControl *clockRow=[self rowWithSymbol:@"arrow.triangle.2.circlepath" title:[self rowTitle:@"时钟校准"] detail:self.clockDetail value:nil chevron:NO];
    clockRow.accessibilityIdentifier=@"WDG.ClockRow";clockRow.accessibilityLabel=@"时钟校准，只读展示";clockRow.userInteractionEnabled=NO;
    UIView *amountBox=[UIView new];amountBox.translatesAutoresizingMaskIntoConstraints=NO;
    UILabel *currency=[self label:13 weight:UIFontWeightMedium];currency.text=@"¥";currency.textColor=UIColor.secondaryLabelColor;currency.numberOfLines=1;
    self.maximumAmount=[UITextField new];self.maximumAmount.placeholder=@"0.00";self.maximumAmount.borderStyle=UITextBorderStyleNone;self.maximumAmount.backgroundColor=UIColor.clearColor;self.maximumAmount.keyboardType=UIKeyboardTypeDecimalPad;self.maximumAmount.textAlignment=NSTextAlignmentRight;self.maximumAmount.font=[UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightSemibold];self.maximumAmount.textColor=UIColor.labelColor;self.maximumAmount.tintColor=[self accent];self.maximumAmount.adjustsFontSizeToFitWidth=YES;self.maximumAmount.minimumFontSize=16;self.maximumAmount.accessibilityLabel=@"最高实付金额，含运费";self.maximumAmount.accessibilityIdentifier=@"WDG.MaximumTotal";self.maximumAmount.translatesAutoresizingMaskIntoConstraints=NO;
    UIToolbar *toolbar=[UIToolbar new];toolbar.tintColor=[self accent];[toolbar sizeToFit];toolbar.items=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(endEditing)]];self.maximumAmount.inputAccessoryView=toolbar;
    [amountBox addSubview:currency];[amountBox addSubview:self.maximumAmount];
    [NSLayoutConstraint activateConstraints:@[[currency.leadingAnchor constraintEqualToAnchor:amountBox.leadingAnchor],[currency.centerYAnchor constraintEqualToAnchor:amountBox.centerYAnchor],[self.maximumAmount.leadingAnchor constraintEqualToAnchor:currency.trailingAnchor constant:4],[self.maximumAmount.trailingAnchor constraintEqualToAnchor:amountBox.trailingAnchor],[self.maximumAmount.centerYAnchor constraintEqualToAnchor:amountBox.centerYAnchor],[self.maximumAmount.widthAnchor constraintEqualToConstant:84],[self.maximumAmount.heightAnchor constraintEqualToConstant:32],[amountBox.heightAnchor constraintEqualToConstant:32]]];
    [amountBox addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusAmount)]];
    UIView *money=[self rowWithSymbol:@"creditcard" title:[self rowTitle:@"最高实付"] detail:[self rowDetail:@"含运费"] value:amountBox chevron:NO];
    money.accessibilityIdentifier=@"WDG.AmountRow";
    UIStackView *rows=[[UIStackView alloc] initWithArrangedSubviews:@[product,[self hairline],self.timeButton,[self hairline],clockRow,[self hairline],money]];
    rows.axis=UILayoutConstraintAxisVertical;rows.spacing=0;[stack addArrangedSubview:rows];
    self.lanesBadge=[self label:11 weight:UIFontWeightSemibold];self.lanesBadge.text=@"2 路并发 · 可能重复下单";self.lanesBadge.textColor=[self accent];self.lanesBadge.numberOfLines=1;self.lanesBadge.hidden=YES;self.lanesBadge.accessibilityIdentifier=@"WDG.ConcurrentLanesBadge";[stack addArrangedSubview:self.lanesBadge];
    self.statusDot=[UIView new];self.statusDot.layer.cornerRadius=3;self.statusDot.backgroundColor=[self accent];self.statusDot.translatesAutoresizingMaskIntoConstraints=NO;
    [self.statusDot.widthAnchor constraintEqualToConstant:6].active=YES;[self.statusDot.heightAnchor constraintEqualToConstant:6].active=YES;
    self.statusLabel=[self label:12 weight:UIFontWeightMedium];self.statusLabel.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];self.statusLabel.textColor=UIColor.secondaryLabelColor;self.statusLabel.numberOfLines=0;self.statusLabel.lineBreakMode=NSLineBreakByWordWrapping;self.statusLabel.accessibilityIdentifier=@"WDG.Countdown";
    [self.statusLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];[self.statusLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *statusRow=[[UIStackView alloc] initWithArrangedSubviews:@[self.statusDot,self.statusLabel]];statusRow.axis=UILayoutConstraintAxisHorizontal;statusRow.alignment=UIStackViewAlignmentCenter;statusRow.spacing=6;
    [statusRow setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];[footer addArrangedSubview:statusRow];
    self.statusDetail=[self label:12 weight:UIFontWeightRegular];self.statusDetail.textColor=UIColor.secondaryLabelColor;self.statusDetail.numberOfLines=0;self.statusDetail.lineBreakMode=NSLineBreakByWordWrapping;self.statusDetail.hidden=YES;
    [self.statusDetail setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];[self.statusDetail setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [footer addArrangedSubview:self.statusDetail];
    self.primaryButton=[UIButton buttonWithType:UIButtonTypeSystem];self.primaryButton.backgroundColor=[self accent];self.primaryButton.layer.cornerRadius=kWDGButtonRadius;self.primaryButton.layer.cornerCurve=kCACornerCurveContinuous;[self.primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];self.primaryButton.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];[self.primaryButton setTitle:@"准备抢购" forState:UIControlStateNormal];self.primaryButton.accessibilityIdentifier=@"WDG.ArmTask";[self.primaryButton.heightAnchor constraintEqualToConstant:kWDGButtonHeight].active=YES;[self.primaryButton addTarget:self action:@selector(schedule) forControlEvents:UIControlEventTouchUpInside];[footer addArrangedSubview:self.primaryButton];
    self.cancelButton=[UIButton buttonWithType:UIButtonTypeSystem];self.cancelButton.tintColor=UIColor.secondaryLabelColor;self.cancelButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];[self.cancelButton setTitle:@"取消任务" forState:UIControlStateNormal];[self.cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];self.cancelButton.accessibilityIdentifier=@"WDG.CancelTask";self.cancelButton.hidden=YES;[footer addArrangedSubview:self.cancelButton];
    self.versionLabel=[self label:10 weight:UIFontWeightRegular];self.versionLabel.textColor=UIColor.tertiaryLabelColor;self.versionLabel.textAlignment=NSTextAlignmentRight;self.versionLabel.numberOfLines=1;self.versionLabel.userInteractionEnabled=NO;
    self.exportLink=[self textLink:@"导出诊断" action:@selector(export)];self.exportLink.accessibilityIdentifier=@"WDG.ExportDiagnostics";
    UIView *footerLeft=[UIView new],*footerRight=[UIView new];
    UIStackView *footerRow=[[UIStackView alloc] initWithArrangedSubviews:@[footerLeft,self.versionLabel,self.exportLink,footerRight]];
    footerRow.axis=UILayoutConstraintAxisHorizontal;footerRow.alignment=UIStackViewAlignmentCenter;footerRow.spacing=8;
    [footerLeft.widthAnchor constraintEqualToAnchor:footerRight.widthAnchor].active=YES;
    [footerRow.heightAnchor constraintEqualToConstant:kWDGFooterHitHeight].active=YES;[footerRow setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [footer addArrangedSubview:footerRow];
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
    if(!self.timeButton.enabled||self.overlay||self.overlayBusy)return;
    [self endEditing];self.dateBeforeEditing=self.datePicker.date;
    WDGOverlayView *overlay=[self beginOverlayWithIdentifier:@"WDG.TimePicker" maxHeightRatio:kWDGTimeCardMaxHeightRatio];
    if(!overlay){self.dateBeforeEditing=nil;return;}
    __weak WDGPanel *weakSelf=self;
    overlay.scrimAction=^{WDGPanel *panel=weakSelf;if(panel)[panel cancelTimePicker];};
    UIView *card=overlay.card;
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:stack];
    NSLayoutConstraint *fitsContent=[stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-kWDGPadding];fitsContent.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kWDGPadding],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kWDGPadding],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:kWDGPadding],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-kWDGPadding],
        fitsContent]];
    UILabel *title=[self label:17 weight:UIFontWeightSemibold];title.text=@"选择开抢时间";title.textAlignment=NSTextAlignmentCenter;title.numberOfLines=0;[stack addArrangedSubview:title];
    [stack setCustomSpacing:6 afterView:title];
    UILabel *hint=[self label:12 weight:UIFontWeightRegular];hint.text=@"本地时间 · 精确到整分钟（秒为 00）";hint.textColor=UIColor.secondaryLabelColor;hint.textAlignment=NSTextAlignmentCenter;hint.numberOfLines=0;[stack addArrangedSubview:hint];
    [stack setCustomSpacing:10 afterView:hint];
    [self.datePicker removeFromSuperview];self.datePicker.translatesAutoresizingMaskIntoConstraints=NO;
    self.datePicker.datePickerMode=UIDatePickerModeDateAndTime;self.datePicker.preferredDatePickerStyle=UIDatePickerStyleWheels;self.datePicker.minuteInterval=1;
    [stack addArrangedSubview:self.datePicker];[self.datePicker.heightAnchor constraintEqualToConstant:216].active=YES;
    [stack setCustomSpacing:16 afterView:self.datePicker];
    UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem];done.translatesAutoresizingMaskIntoConstraints=NO;
    done.backgroundColor=[self accent];done.layer.cornerRadius=kWDGButtonRadius;done.layer.cornerCurve=kCACornerCurveContinuous;done.clipsToBounds=YES;
    [done setTitle:@"完成" forState:UIControlStateNormal];[done setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];done.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [done.heightAnchor constraintEqualToConstant:kWDGButtonHeight].active=YES;
    [done addTarget:self action:@selector(finishTimePicker) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:done];
    UIButton *cancel=[UIButton buttonWithType:UIButtonTypeSystem];cancel.translatesAutoresizingMaskIntoConstraints=NO;cancel.tintColor=UIColor.secondaryLabelColor;
    [cancel setTitle:@"取消" forState:UIControlStateNormal];cancel.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    [cancel.heightAnchor constraintEqualToConstant:40].active=YES;
    [cancel addTarget:self action:@selector(cancelTimePicker) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:cancel];
    [self.window.rootViewController.view layoutIfNeeded];
    [overlay presentWithCompletion:nil];
}
- (void)cancelTimePicker {
    if(!self.overlay||self.overlayBusy)return;
    if(self.dateBeforeEditing)self.datePicker.date=self.dateBeforeEditing;
    self.dateBeforeEditing=nil;[self updateTimeDisplay];
    [self dismissOverlayWithAction:^{[self.datePicker removeFromSuperview];}];
}
- (void)finishTimePicker {
    if(!self.overlay||self.overlayBusy)return;
    self.datePicker.date=[self selectedMinute];self.dateBeforeEditing=nil;[self updateTimeDisplay];
    [self dismissOverlayWithAction:^{[self.datePicker removeFromSuperview];}];
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
    NSString *line=[[(message?:@"") stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:line preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (CGFloat)overlayCardWidth {
    CGFloat width=CGRectGetWidth(self.card.bounds);
    if(!(width>0))width=MIN(kWDGCardMaxWidth,self.window.bounds.size.width-kWDGCardScreenMargin);
    return width;
}
- (WDGOverlayView *)beginOverlayWithIdentifier:(NSString *)identifier {
    return [self beginOverlayWithIdentifier:identifier maxHeightRatio:kWDGOverlayMaxHeightRatio];
}
- (WDGOverlayView *)beginOverlayWithIdentifier:(NSString *)identifier maxHeightRatio:(CGFloat)ratio {
    if(self.overlay||self.overlayBusy)return nil;
    UIView *root=self.window.rootViewController.view;if(!root)return nil;
    WDGOverlayView *overlay=[[WDGOverlayView alloc] initWithCardWidth:[self overlayCardWidth] maxHeightRatio:ratio];
    overlay.accessibilityIdentifier=identifier;[root addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [overlay.topAnchor constraintEqualToAnchor:root.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
    self.overlay=overlay;self.overlayBusy=NO;self.menuItems=nil;self.activeSheet=nil;
    // Hide the panel card while a modal overlay is up: leaving the red primary
    // button visible under the scrim reads as a second, clipped button.
    self.card.hidden=YES;
    __weak WDGPanel *weakSelf=self;
    overlay.scrimAction=^{WDGPanel *panel=weakSelf;if(panel)[panel dismissOverlayWithAction:nil];};
    [root layoutIfNeeded];
    return overlay;
}
- (UIView *)navRowWithTitle:(NSString *)title tag:(NSInteger)tag {
    WDGRowControl *row=[self menuRowWithTitle:title color:UIColor.labelColor checked:NO tag:tag];
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:config]];
    chevron.tintColor=UIColor.tertiaryLabelColor;chevron.translatesAutoresizingMaskIntoConstraints=NO;chevron.userInteractionEnabled=NO;
    [row addSubview:chevron];
    [NSLayoutConstraint activateConstraints:@[
        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-4],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]]];
    return row;
}
- (UIView *)switchRowWithTitle:(NSString *)title on:(BOOL)on handler:(void (^)(BOOL on))handler {
    WDGRowControl *row=[WDGRowControl new];row.translatesAutoresizingMaskIntoConstraints=NO;
    row.accessibilityLabel=title;
    UILabel *label=[UILabel new];label.translatesAutoresizingMaskIntoConstraints=NO;label.userInteractionEnabled=NO;
    label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightRegular];label.textColor=UIColor.labelColor;label.text=title;label.numberOfLines=1;
    WDGSwitch *toggle=[WDGSwitch new];toggle.translatesAutoresizingMaskIntoConstraints=NO;toggle.onTintColor=WDGSheetAccent();toggle.on=on;
    toggle.tintAdjustmentMode=UIViewTintAdjustmentModeNormal;
    toggle.accessibilityLabel=title;
    __weak WDGSwitch *weakToggle=toggle;
    toggle.onToggle=^(BOOL value){if(handler)handler(value);if(weakToggle)[weakToggle setOn:value animated:YES];};
    [toggle addTarget:toggle action:@selector(fireToggle) forControlEvents:UIControlEventValueChanged];
    [row addSubview:label];[row addSubview:toggle];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-10],
        [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:kWDGMenuRowHeight]]];
    [row addTarget:self action:@selector(tapSwitchRow:) forControlEvents:UIControlEventTouchUpInside];
    return row;
}
- (void)tapSwitchRow:(WDGRowControl *)sender {
    for(UIView *view in sender.subviews) if([view isKindOfClass:WDGSwitch.class]){WDGSwitch *toggle=(WDGSwitch *)view;[toggle setOn:!toggle.isOn animated:YES];[toggle fireToggle];return;}
}
- (UIView *)menuHairline {
    UIView *line=[UIView new];line.translatesAutoresizingMaskIntoConstraints=NO;line.userInteractionEnabled=NO;
    line.backgroundColor=[UIColor.separatorColor colorWithAlphaComponent:0.5];
    [line.heightAnchor constraintEqualToConstant:kWDGHairlineHeight].active=YES;return line;
}
- (WDGRowControl *)menuRowWithTitle:(NSString *)title color:(UIColor *)color checked:(BOOL)checked tag:(NSInteger)tag {
    WDGRowControl *row=[WDGRowControl new];row.translatesAutoresizingMaskIntoConstraints=NO;row.tag=tag;
    row.layer.cornerRadius=10;row.layer.cornerCurve=kCACornerCurveContinuous;row.layer.masksToBounds=YES;
    row.accessibilityLabel=title;row.accessibilityIdentifier=tag<0?@"WDG.MenuCancel":[NSString stringWithFormat:@"WDG.MenuRow.%ld",(long)tag];
    UILabel *label=[UILabel new];label.translatesAutoresizingMaskIntoConstraints=NO;label.userInteractionEnabled=NO;
    label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightRegular];label.textColor=color;label.text=title;
    label.numberOfLines=2;label.lineBreakMode=NSLineBreakByTruncatingTail;[row addSubview:label];
    NSMutableArray<NSLayoutConstraint *> *rules=[NSMutableArray arrayWithObjects:
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:6],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-6],
        [row.heightAnchor constraintEqualToConstant:kWDGMenuRowHeight],nil];
    UIView *right=nil;
    if(checked){
        UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        UIImageView *check=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:config]];
        check.tintColor=WDGSheetAccent();check.contentMode=UIViewContentModeScaleAspectFit;check.translatesAutoresizingMaskIntoConstraints=NO;check.userInteractionEnabled=NO;[row addSubview:check];
        [rules addObjectsFromArray:@[[check.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],[check.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],[check.widthAnchor constraintEqualToConstant:kWDGMenuCheckSide],[check.heightAnchor constraintEqualToConstant:kWDGMenuCheckSide]]];
        right=check;
    }
    if(right)[rules addObject:[label.trailingAnchor constraintLessThanOrEqualToAnchor:right.leadingAnchor constant:-10]];
    else [rules addObject:[label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor]];
    [NSLayoutConstraint activateConstraints:rules];
    [row addTarget:self action:@selector(menuRowTapped:) forControlEvents:UIControlEventTouchUpInside];
    return row;
}
- (void)menuRowTapped:(WDGRowControl *)sender {
    if(self.overlayBusy||!self.overlay||!sender.enabled)return;
    NSInteger index=sender.tag;WDGMenuItem *item=nil;
    if(index>=0){
        if((NSUInteger)index>=self.menuItems.count)return;
        item=self.menuItems[(NSUInteger)index];
        if(!item.enabled)return;
    }
    WDGSheetBlock action=[item.action copy];
    [self dismissOverlayWithAction:action];
}
- (void)installMenuTitle:(NSString *)title subtitle:(NSString *)subtitle items:(NSArray<WDGMenuItem *> *)items inCard:(UIView *)card {
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.showsVerticalScrollIndicator=NO;scroll.showsHorizontalScrollIndicator=NO;scroll.alwaysBounceVertical=NO;scroll.alwaysBounceHorizontal=NO;
    scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[card addSubview:scroll];
    UIView *cancelBar=[UIView new];cancelBar.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:cancelBar];
    UIView *cancelLine=[UIView new];cancelLine.translatesAutoresizingMaskIntoConstraints=NO;cancelLine.userInteractionEnabled=NO;
    cancelLine.backgroundColor=[UIColor.separatorColor colorWithAlphaComponent:0.5];[cancelBar addSubview:cancelLine];
    WDGRowControl *cancelRow=[self menuRowWithTitle:@"取消" color:UIColor.secondaryLabelColor checked:NO tag:-1];
    for(UIView *view in cancelRow.subviews) if([view isKindOfClass:UILabel.class]){UILabel *label=(UILabel *)view;label.textAlignment=NSTextAlignmentCenter;[label.trailingAnchor constraintEqualToAnchor:cancelRow.trailingAnchor].active=YES;break;}
    [cancelBar addSubview:cancelRow];
    NSLayoutConstraint *fitsContent=[scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor];fitsContent.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kWDGPadding],
        [scroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kWDGPadding],
        [scroll.topAnchor constraintEqualToAnchor:card.topAnchor constant:kWDGPadding],
        [scroll.bottomAnchor constraintEqualToAnchor:cancelBar.topAnchor constant:-kWDGMenuCancelGap],
        [cancelBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [cancelBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [cancelBar.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [cancelBar.heightAnchor constraintEqualToConstant:kWDGHairlineHeight+kWDGMenuCancelGap+kWDGMenuRowHeight],
        [cancelLine.leadingAnchor constraintEqualToAnchor:cancelBar.leadingAnchor],
        [cancelLine.trailingAnchor constraintEqualToAnchor:cancelBar.trailingAnchor],
        [cancelLine.topAnchor constraintEqualToAnchor:cancelBar.topAnchor],
        [cancelLine.heightAnchor constraintEqualToConstant:kWDGHairlineHeight],
        [cancelRow.leadingAnchor constraintEqualToAnchor:cancelBar.leadingAnchor constant:kWDGPadding],
        [cancelRow.trailingAnchor constraintEqualToAnchor:cancelBar.trailingAnchor constant:-kWDGPadding],
        [cancelRow.topAnchor constraintEqualToAnchor:cancelLine.bottomAnchor constant:kWDGMenuCancelGap],
        [cancelRow.bottomAnchor constraintEqualToAnchor:cancelBar.bottomAnchor],
        fitsContent]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=0;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *titleLabel=[UILabel new];titleLabel.translatesAutoresizingMaskIntoConstraints=NO;titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];titleLabel.textColor=UIColor.labelColor;titleLabel.numberOfLines=0;titleLabel.text=title;titleLabel.textAlignment=NSTextAlignmentCenter;
    [stack addArrangedSubview:titleLabel];[stack setCustomSpacing:subtitle.length?6:14 afterView:titleLabel];
    if(subtitle.length){
        UILabel *subtitleLabel=[UILabel new];subtitleLabel.translatesAutoresizingMaskIntoConstraints=NO;subtitleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        subtitleLabel.textColor=UIColor.secondaryLabelColor;subtitleLabel.numberOfLines=0;subtitleLabel.text=subtitle;
        [stack addArrangedSubview:subtitleLabel];[stack setCustomSpacing:12 afterView:subtitleLabel];
    }
    if(items.count){
        NSMutableArray<UIView *> *views=[NSMutableArray array];
        [items enumerateObjectsUsingBlock:^(WDGMenuItem *item,NSUInteger index,__unused BOOL *stop){
            if(index>0)[views addObject:[self menuHairline]];
            if(item.isSwitch){[views addObject:[self switchRowWithTitle:item.title on:item.switchOn handler:item.switchHandler]];return;}
            if(item.showsChevron){[views addObject:[self navRowWithTitle:item.title tag:(NSInteger)index]];return;}
            WDGRowControl *row=[self menuRowWithTitle:item.title color:item.destructive?UIColor.systemRedColor:UIColor.labelColor checked:item.checked tag:(NSInteger)index];
            row.enabled=item.enabled;if(!item.enabled)row.alpha=0.4;
            [views addObject:row];
        }];
        UIStackView *rows=[[UIStackView alloc] initWithArrangedSubviews:views];rows.axis=UILayoutConstraintAxisVertical;rows.spacing=0;rows.translatesAutoresizingMaskIntoConstraints=NO;
        [stack addArrangedSubview:rows];
    }
}
- (void)presentMenuWithTitle:(NSString *)title subtitle:(NSString *)subtitle items:(NSArray<WDGMenuItem *> *)items {
    WDGOverlayView *overlay=[self beginOverlayWithIdentifier:@"WDG.Menu"];
    if(!overlay)return;
    self.menuItems=[items copy];
    [self installMenuTitle:title subtitle:subtitle items:items inCard:overlay.card];
    [self.window.rootViewController.view layoutIfNeeded];
    [overlay presentWithCompletion:nil];
}
- (void)presentSheet:(WDGSheetController *)sheet {
    if(!sheet)return;
    WDGOverlayView *overlay=[self beginOverlayWithIdentifier:@"WDG.Sheet"];
    if(!overlay)return;
    self.activeSheet=sheet;
    __weak WDGPanel *weakSelf=self;
    sheet.requestClose=^(WDGSheetBlock action){WDGPanel *panel=weakSelf;if(panel)[panel dismissOverlayWithAction:action];};
    UIView *content=sheet.contentView;[overlay.card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:overlay.card.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:overlay.card.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:overlay.card.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:overlay.card.bottomAnchor]]];
    [self.window.rootViewController.view layoutIfNeeded];
    [overlay presentWithCompletion:nil];
}
- (void)dismissOverlayWithAction:(WDGSheetBlock)action {
    if(!self.overlay||self.overlayBusy)return;
    WDGOverlayView *overlay=self.overlay;
    self.overlayBusy=YES;
    if(self.activeSheet)self.activeSheet.dismissed=YES;
    [overlay dismissWithCompletion:^{
        BOOL tornDown=overlay.tornDown;
        if(self.overlay==overlay)self.overlay=nil;
        self.overlayBusy=NO;self.activeSheet=nil;self.menuItems=nil;
        self.card.hidden=NO;
        if(!tornDown&&action)action();
    }];
}
- (void)removeOverlayImmediately {
    WDGOverlayView *overlay=self.overlay;
    self.overlay=nil;self.overlayBusy=NO;self.activeSheet=nil;self.menuItems=nil;
    self.card.hidden=NO;
    [self.datePicker removeFromSuperview];
    [overlay removeImmediately];
}
- (void)chooseCartTarget {
    NSArray *rows=[[NSArray alloc] initWithArray:WDGCartCandidates() copyItems:YES];
    if(!rows.count){[self alert:@"先刷新一下购物车" message:@"助手会自动读取商品。未开售的条目也能在这里选择。 "];return;}
    BOOL explicit=[WDGCartDiagnostics()[@"selectionSource"] isEqual:@"assistant_explicit"];
    NSMutableArray<WDGMenuItem *> *items=[NSMutableArray array];
    [items addObject:[WDGMenuItem itemWithTitle:@"跟随购物车勾选项（默认）" checked:!explicit destructive:NO action:^{if(![rows isEqual:WDGCartCandidates()]){[self alert:@"购物车有更新" message:@"请重新选择目标。 "];return;}WDGCartChooseLine(nil);[self refresh];}]];
    for(NSDictionary *row in rows){NSString *key=[row[@"lineKey"] copy];NSDictionary *raw=[WDGCartRawLine(key) copy];NSString *title=[NSString stringWithFormat:@"%@ · %@ × %@",row[@"title"]?:@"商品",row[@"skuTitle"]?:@"未选规格",row[@"quantity"]?:@"?"];[items addObject:[WDGMenuItem itemWithTitle:title checked:NO destructive:NO action:^{if(!raw||![raw isEqual:WDGCartRawLine(key)]||!WDGCartChooseLine(key)){[self alert:@"商品已更新" message:@"请重新核对规格和数量。 "];return;}[self refresh];}]];}
    NSString *subtitle=explicit?@"当前来源：手动指定\n只选择目标，不修改购物车、不下单。":@"当前来源：购物车勾选（默认）\n只选择目标，不修改购物车、不下单。";
    [self presentMenuWithTitle:@"要抢哪件" subtitle:subtitle items:items];
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
- (void)schedule {
    NSDecimalNumber *maximum=[self maximumValue];if(!maximum)return;[self endEditing];
    NSArray *items=[[NSArray alloc] initWithArray:WDGCartSelectedLines() copyItems:YES];NSString *key=[WDGCartSnapshotKey() copy];NSArray *keys=[[items valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];
    if(!items.count||!key.length){[self alert:@"先选好商品" message:@"刷新购物车或点商品卡选择目标。 "];return;}
    NSDate *date=[self selectedMinute];NSDictionary *clock=nil;
    if(![self localDeadlineForDate:date clockSnapshot:&clock])return;
    NSUInteger lanes=self.concurrentLanes;
    NSDecimalNumber *total=[maximum decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithMantissa:lanes exponent:0 isNegative:NO]];
    NSDictionary *first=items.firstObject;
    NSMutableDictionary *productRow=[WDGSheetRow(@"商品",[NSString stringWithFormat:@"%@ · %@ × %@%@",first[@"title"]?:@"商品",first[@"skuTitle"]?:@"未选规格",first[@"quantity"]?:@"?",items.count>1?[NSString stringWithFormat:@" · 共 %lu 条",(unsigned long)items.count]:@""],NO) mutableCopy];
    productRow[@"middle"]=@YES;
    NSString *footnote=lanes>1?[NSString stringWithFormat:@"可能重复下单：同商品最多 %lu 单，总扣款上限 ¥%@；单笔实付超过最高实付即停止提交。首个成功不会撤销其余已发请求",(unsigned long)lanes,[self formattedAmount:total]]:@"到点创建 1 次真实订单，实付超过最高实付即停止提交，不打开支付链接";
    NSNumber *retryAttempts=WDGCore.shared.status[@"task"][@"retryAttempts"];
    if([WDGCore.shared.status[@"retryEnabled"] boolValue]) footnote=[footnote stringByAppendingFormat:@"；明确未建单时最多重发 %lu 次，结果未知则不再重发",(unsigned long)(retryAttempts.unsignedIntegerValue?:3)];
    NSString *sheetTitle=lanes>1?[NSString stringWithFormat:@"确认 %lu 路竞速任务",(unsigned long)lanes]:@"确认这笔任务";
    NSString *primaryTitle=lanes>1?[NSString stringWithFormat:@"确认 %lu 路 · 接受最多%lu单",(unsigned long)lanes,(unsigned long)lanes]:@"确认单路 · 最多1单";
    WDGSheetController *sheet=[WDGSheetController sheetWithTitle:sheetTitle
        rows:@[productRow,WDGSheetRow(@"开抢",self.timeValue.text?:@"",NO),WDGSheetRow(@"最高实付",[NSString stringWithFormat:@"¥%@",[self formattedAmount:maximum]],YES),WDGSheetRow(@"并发",[NSString stringWithFormat:@"最多 %lu 单",(unsigned long)lanes],NO),WDGSheetRow(@"时钟",[self clockSummary:clock],NO)]
        footnote:footnote warning:lanes>1
        primaryTitle:primaryTitle
        primaryAction:^{NSArray *nowKeys=[[WDGCartSelectedLines() valueForKey:@"lineKey"] sortedArrayUsingSelector:@selector(compare:)];if(![key isEqual:WDGCartSnapshotKey()]||![keys isEqual:nowKeys]){[self alert:@"购物车目标已变化" message:@"请重新核对商品和规格。 "];return;}NSError *error=nil;if(![WDGCore.shared armCartAt:date maximumTotal:maximum concurrentLanes:lanes clockSnapshot:clock error:&error])[self alert:@"任务未设置" message:error.localizedDescription];}
        secondaryTitle:@"再看看"];
    [self presentSheet:sheet];
}
- (void)cancel {[WDGCore.shared cancelTask:@"用户取消任务"];}
- (void)export {
    NSError *error=nil;NSString *file=[WDGCore.shared exportReport:&error];if(!file){[self alert:@"导出失败" message:error.localizedDescription?:@"请稍后重试"];return;}
    UIActivityViewController *a=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:file]] applicationActivities:nil];a.popoverPresentationController.sourceView=self.card;a.popoverPresentationController.sourceRect=self.card.bounds;[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)chooseConcurrentLanes {
    NSMutableArray<WDGMenuItem *> *items=[NSMutableArray array];
    NSArray<NSString *> *titles=@[@"单路（默认）",@"双路 · 可能重复下单",@"四路 · 最多 4 单"];
    NSArray<NSNumber *> *values=@[@1,@2,@4];
    for(NSUInteger index=0;index<titles.count;index++){
        NSUInteger lanes=values[index].unsignedIntegerValue;
        [items addObject:[WDGMenuItem itemWithTitle:titles[index] checked:self.concurrentLanes==lanes destructive:NO action:^{self.concurrentLanes=lanes;[self refresh];}]];
    }
    [self presentMenuWithTitle:@"下单并发" subtitle:@"多路会对同一订单目标同时发出多个请求，可能分别成功并重复下单。最终确认会列出最多订单数及总扣款上限。" items:items];
}
- (void)showMore {
    [self endEditing];
    NSMutableArray<WDGMenuItem *> *items=[NSMutableArray array];
    NSString *lanesValue=self.concurrentLanes>1?[NSString stringWithFormat:@"%lu 路",(unsigned long)self.concurrentLanes]:@"单路";
    WDGMenuItem *lanes=[WDGMenuItem itemWithTitle:[NSString stringWithFormat:@"并发 · %@",lanesValue] checked:NO destructive:NO action:^{[self chooseConcurrentLanes];}];
    lanes.enabled=self.primaryButton.enabled;lanes.showsChevron=YES;[items addObject:lanes];
    BOOL retryOn=[WDGCore.shared.status[@"retryEnabled"] boolValue];
    [items addObject:[WDGMenuItem switchItemWithTitle:@"循环重发（最多 3 次）" on:retryOn handler:^(BOOL on){[WDGCore.shared setRetryEnabled:on attempts:3];[self refresh];}]];
    BOOL adsOn=[WDGCore.shared.status[@"ads"][@"enabled"] boolValue];
    [items addObject:[WDGMenuItem switchItemWithTitle:@"去广告" on:adsOn handler:^(BOOL on){[WDGCore.shared setAdsEnabled:on];}]];
    [self presentMenuWithTitle:@"更多" subtitle:nil items:items];
}
@end
void WDGShowOverlay(void) {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WDGShowOverlay();});return;}
    [[WDGPanel shared] ensureWindow];
}
