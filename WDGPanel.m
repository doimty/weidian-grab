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

static UIColor *WDGSheetAccent(void) {return [UIColor colorWithRed:0.90 green:0.14 blue:0.30 alpha:1];}
static NSDictionary *WDGSheetRow(NSString *label,NSString *value,BOOL mono) {return @{@"label":label?:@"",@"value":value?:@"",@"mono":@(mono)};}

@interface WDGSheetController : UIViewController
@property(nonatomic,copy) NSString *sheetTitle;
@property(nonatomic,copy) NSArray<NSDictionary *> *sheetRows;
@property(nonatomic,copy) NSString *sheetFootnote;
@property(nonatomic,assign) BOOL footnoteWarning;
@property(nonatomic,copy) NSString *primaryTitle;
@property(nonatomic,copy) NSString *secondaryTitle;
@property(nonatomic,copy) WDGSheetBlock primaryAction;
@property(nonatomic,copy) WDGSheetBlock secondaryAction;
+ (instancetype)sheetWithTitle:(NSString *)title rows:(NSArray<NSDictionary *> *)rows footnote:(NSString *)footnote warning:(BOOL)warning primaryTitle:(NSString *)primaryTitle primaryAction:(WDGSheetBlock)primaryAction secondaryTitle:(NSString *)secondaryTitle;
@end

@implementation WDGSheetController
+ (instancetype)sheetWithTitle:(NSString *)title rows:(NSArray<NSDictionary *> *)rows footnote:(NSString *)footnote warning:(BOOL)warning primaryTitle:(NSString *)primaryTitle primaryAction:(WDGSheetBlock)primaryAction secondaryTitle:(NSString *)secondaryTitle {
    WDGSheetController *sheet=[self new];
    sheet.modalPresentationStyle=UIModalPresentationPageSheet;
    sheet.sheetTitle=title;sheet.sheetRows=rows;sheet.sheetFootnote=footnote;sheet.footnoteWarning=warning;
    sheet.primaryTitle=primaryTitle;sheet.primaryAction=primaryAction;sheet.secondaryTitle=secondaryTitle;
    return sheet;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;self.view.accessibilityIdentifier=@"WDG.Sheet";
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.showsVerticalScrollIndicator=NO;scroll.showsHorizontalScrollIndicator=NO;scroll.alwaysBounceVertical=NO;scroll.alwaysBounceHorizontal=NO;
    scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[self.view addSubview:scroll];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:kWDGPadding],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-kWDGPadding],
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor constant:kWDGPadding],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-kWDGPadding]]];
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
    if(!self.view.window)return;
    WDGSheetBlock action=[self.primaryAction copy];self.primaryAction=nil;self.view.userInteractionEnabled=NO;
    [self dismissViewControllerAnimated:YES completion:^{if(action)action();}];
}
- (void)tapSecondary {
    if(!self.view.window)return;
    WDGSheetBlock action=[self.secondaryAction copy];self.secondaryAction=nil;self.view.userInteractionEnabled=NO;
    [self dismissViewControllerAnimated:YES completion:^{if(action)action();}];
}
@end

static const CGFloat kWDGMenuRowHeight=48;
static const CGFloat kWDGMenuCheckSide=16;

@interface WDGMenuItem : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,assign) BOOL checked;
@property(nonatomic,assign) BOOL destructive;
@property(nonatomic,assign) BOOL enabled;
@property(nonatomic,copy) WDGSheetBlock action;
+ (instancetype)itemWithTitle:(NSString *)title checked:(BOOL)checked destructive:(BOOL)destructive action:(WDGSheetBlock)action;
@end

@implementation WDGMenuItem
- (instancetype)init {if((self=[super init]))_enabled=YES;return self;}
+ (instancetype)itemWithTitle:(NSString *)title checked:(BOOL)checked destructive:(BOOL)destructive action:(WDGSheetBlock)action {
    WDGMenuItem *item=[self new];item.title=title?:@"";item.checked=checked;item.destructive=destructive;item.action=action;return item;
}
@end

@interface WDGMenuSheetController : UIViewController
@property(nonatomic,copy) NSString *menuTitle;
@property(nonatomic,copy) NSString *menuSubtitle;
@property(nonatomic,copy) NSArray<WDGMenuItem *> *menuItems;
@property(nonatomic,assign) BOOL menuDismissed;
+ (instancetype)menuWithTitle:(NSString *)title subtitle:(NSString *)subtitle items:(NSArray<WDGMenuItem *> *)items;
@end

@implementation WDGMenuSheetController
+ (instancetype)menuWithTitle:(NSString *)title subtitle:(NSString *)subtitle items:(NSArray<WDGMenuItem *> *)items {
    WDGMenuSheetController *menu=[self new];
    menu.modalPresentationStyle=UIModalPresentationPageSheet;
    menu.menuTitle=title;menu.menuSubtitle=subtitle;menu.menuItems=[items copy];
    return menu;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;self.view.accessibilityIdentifier=@"WDG.Menu";
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    UIView *cancelBar=[UIView new];cancelBar.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:cancelBar];
    UIView *cancelLine=[UIView new];cancelLine.translatesAutoresizingMaskIntoConstraints=NO;cancelLine.userInteractionEnabled=NO;
    cancelLine.backgroundColor=[UIColor.separatorColor colorWithAlphaComponent:0.5];[cancelBar addSubview:cancelLine];
    UIControl *cancelRow=[self menuRow:@"取消" color:UIColor.secondaryLabelColor checked:NO tag:-1];[cancelBar addSubview:cancelRow];
    [NSLayoutConstraint activateConstraints:@[
        [cancelBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [cancelBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [cancelBar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [cancelLine.leadingAnchor constraintEqualToAnchor:cancelBar.leadingAnchor],
        [cancelLine.trailingAnchor constraintEqualToAnchor:cancelBar.trailingAnchor],
        [cancelLine.topAnchor constraintEqualToAnchor:cancelBar.topAnchor],
        [cancelLine.heightAnchor constraintEqualToConstant:kWDGHairlineHeight],
        [cancelRow.leadingAnchor constraintEqualToAnchor:cancelBar.leadingAnchor constant:kWDGPadding],
        [cancelRow.trailingAnchor constraintEqualToAnchor:cancelBar.trailingAnchor constant:-kWDGPadding],
        [cancelRow.topAnchor constraintEqualToAnchor:cancelLine.bottomAnchor],
        [cancelRow.bottomAnchor constraintEqualToAnchor:cancelBar.bottomAnchor]]];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.showsVerticalScrollIndicator=NO;scroll.showsHorizontalScrollIndicator=NO;scroll.alwaysBounceVertical=NO;scroll.alwaysBounceHorizontal=NO;
    scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:kWDGPadding],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-kWDGPadding],
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor constant:kWDGPadding],
        [scroll.bottomAnchor constraintEqualToAnchor:cancelBar.topAnchor constant:-kWDGSectionGap]]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=0;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *title=[UILabel new];title.translatesAutoresizingMaskIntoConstraints=NO;title.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];title.textColor=UIColor.labelColor;title.numberOfLines=0;title.text=self.menuTitle;
    [stack addArrangedSubview:title];[stack setCustomSpacing:self.menuSubtitle.length?6:14 afterView:title];
    if(self.menuSubtitle.length){
        UILabel *subtitle=[UILabel new];subtitle.translatesAutoresizingMaskIntoConstraints=NO;subtitle.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        subtitle.textColor=UIColor.secondaryLabelColor;subtitle.numberOfLines=0;subtitle.text=self.menuSubtitle;
        [stack addArrangedSubview:subtitle];[stack setCustomSpacing:12 afterView:subtitle];
    }
    if(self.menuItems.count){
        NSMutableArray<UIView *> *views=[NSMutableArray array];
        for(NSUInteger index=0;index<self.menuItems.count;index++){
            WDGMenuItem *item=self.menuItems[index];
            if(index>0)[views addObject:[self menuHairline]];
            UIControl *row=[self menuRow:item.title color:item.destructive?UIColor.systemRedColor:UIColor.labelColor checked:item.checked tag:(NSInteger)index];
            row.enabled=item.enabled;if(!item.enabled)row.alpha=0.4;
            [views addObject:row];
        }
        UIStackView *rows=[[UIStackView alloc] initWithArrangedSubviews:views];rows.axis=UILayoutConstraintAxisVertical;rows.spacing=0;rows.translatesAutoresizingMaskIntoConstraints=NO;
        [stack addArrangedSubview:rows];
    }
}
- (UIView *)menuHairline {
    UIView *line=[UIView new];line.translatesAutoresizingMaskIntoConstraints=NO;line.userInteractionEnabled=NO;
    line.backgroundColor=[UIColor.separatorColor colorWithAlphaComponent:0.5];
    [line.heightAnchor constraintEqualToConstant:kWDGHairlineHeight].active=YES;return line;
}
- (UIControl *)menuRow:(NSString *)title color:(UIColor *)color checked:(BOOL)checked tag:(NSInteger)tag {
    WDGRowControl *row=[WDGRowControl new];row.translatesAutoresizingMaskIntoConstraints=NO;row.tag=tag;
    row.layer.cornerRadius=10;row.layer.cornerCurve=kCACornerCurveContinuous;row.layer.masksToBounds=YES;
    row.accessibilityLabel=title;row.accessibilityIdentifier=tag<0?@"WDG.MenuCancel":[NSString stringWithFormat:@"WDG.MenuRow.%ld",(long)tag];
    UILabel *label=[UILabel new];label.translatesAutoresizingMaskIntoConstraints=NO;label.userInteractionEnabled=NO;
    label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightRegular];label.textColor=color;label.text=title;
    label.numberOfLines=2;label.lineBreakMode=NSLineBreakByTruncatingTail;[row addSubview:label];
    NSMutableArray<NSLayoutConstraint *> *rules=[NSMutableArray arrayWithObjects:
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:11],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-11],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:kWDGMenuRowHeight],nil];
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
    [row addTarget:self action:@selector(tapMenuRow:) forControlEvents:UIControlEventTouchUpInside];
    return row;
}
- (void)tapMenuRow:(WDGRowControl *)sender {
    if(self.menuDismissed||!self.view.window||!sender.enabled)return;
    NSInteger index=sender.tag;
    if(index>=0&&(NSUInteger)index>=self.menuItems.count)return;
    WDGMenuItem *item=index>=0?self.menuItems[(NSUInteger)index]:nil;
    if(item&&!item.enabled)return;
    WDGSheetBlock action=[item.action copy];
    self.menuDismissed=YES;self.view.userInteractionEnabled=NO;
    [self dismissViewControllerAnimated:YES completion:^{if(action)action();}];
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
@property(nonatomic,strong) UIButton *exportLink;
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
    UIStackView *statusRow=[[UIStackView alloc] initWithArrangedSubviews:@[self.statusDot,self.statusLabel]];statusRow.axis=UILayoutConstraintAxisHorizontal;statusRow.alignment=UIStackViewAlignmentCenter;statusRow.spacing=6;[stack addArrangedSubview:statusRow];
    self.statusDetail=[self label:12 weight:UIFontWeightRegular];self.statusDetail.textColor=UIColor.secondaryLabelColor;self.statusDetail.numberOfLines=0;self.statusDetail.lineBreakMode=NSLineBreakByWordWrapping;self.statusDetail.hidden=YES;
    [self.statusDetail setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];[self.statusDetail setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [stack addArrangedSubview:self.statusDetail];
    self.primaryButton=[UIButton buttonWithType:UIButtonTypeSystem];self.primaryButton.backgroundColor=[self accent];self.primaryButton.layer.cornerRadius=kWDGButtonRadius;self.primaryButton.layer.cornerCurve=kCACornerCurveContinuous;[self.primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];self.primaryButton.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];[self.primaryButton setTitle:@"准备抢购" forState:UIControlStateNormal];self.primaryButton.accessibilityIdentifier=@"WDG.ArmTask";[self.primaryButton.heightAnchor constraintEqualToConstant:kWDGButtonHeight].active=YES;[self.primaryButton addTarget:self action:@selector(schedule) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:self.primaryButton];
    self.cancelButton=[UIButton buttonWithType:UIButtonTypeSystem];self.cancelButton.tintColor=UIColor.secondaryLabelColor;self.cancelButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];[self.cancelButton setTitle:@"取消任务" forState:UIControlStateNormal];[self.cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];self.cancelButton.accessibilityIdentifier=@"WDG.CancelTask";self.cancelButton.hidden=YES;[stack addArrangedSubview:self.cancelButton];
    self.versionLabel=[self label:10 weight:UIFontWeightRegular];self.versionLabel.textColor=UIColor.tertiaryLabelColor;self.versionLabel.textAlignment=NSTextAlignmentRight;self.versionLabel.numberOfLines=1;self.versionLabel.userInteractionEnabled=NO;
    self.exportLink=[self textLink:@"导出诊断" action:@selector(export)];self.exportLink.accessibilityIdentifier=@"WDG.ExportDiagnostics";
    UIView *footerLeft=[UIView new],*footerRight=[UIView new];
    UIStackView *footer=[[UIStackView alloc] initWithArrangedSubviews:@[footerLeft,self.versionLabel,self.exportLink,footerRight]];
    footer.axis=UILayoutConstraintAxisHorizontal;footer.alignment=UIStackViewAlignmentCenter;footer.spacing=8;
    [footerLeft.widthAnchor constraintEqualToAnchor:footerRight.widthAnchor].active=YES;
    [footer.heightAnchor constraintEqualToConstant:kWDGFooterHitHeight].active=YES;[stack addArrangedSubview:footer];
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
    NSString *line=[[(message?:@"") stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:line preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[self.window.rootViewController presentViewController:a animated:YES completion:nil];
}
- (void)presentSheet:(WDGSheetController *)sheet {
    UISheetPresentationController *presentation=sheet.sheetPresentationController;
    presentation.detents=@[UISheetPresentationControllerDetent.mediumDetent];
    presentation.prefersGrabberVisible=YES;presentation.preferredCornerRadius=kWDGCardRadius;
    [self.window.rootViewController presentViewController:sheet animated:YES completion:nil];
}
- (void)presentMenu:(UIViewController *)menu {
    UISheetPresentationController *presentation=menu.sheetPresentationController;
    presentation.detents=@[UISheetPresentationControllerDetent.mediumDetent];
    presentation.prefersGrabberVisible=YES;presentation.preferredCornerRadius=kWDGCardRadius;
    [self.window.rootViewController presentViewController:menu animated:YES completion:nil];
}
- (void)chooseCartTarget {
    NSArray *rows=[[NSArray alloc] initWithArray:WDGCartCandidates() copyItems:YES];
    if(!rows.count){[self alert:@"先刷新一下购物车" message:@"助手会自动读取商品。未开售的条目也能在这里选择。 "];return;}
    BOOL explicit=[WDGCartDiagnostics()[@"selectionSource"] isEqual:@"assistant_explicit"];
    NSMutableArray<WDGMenuItem *> *items=[NSMutableArray array];
    [items addObject:[WDGMenuItem itemWithTitle:@"跟随购物车勾选项（默认）" checked:!explicit destructive:NO action:^{if(![rows isEqual:WDGCartCandidates()]){[self alert:@"购物车有更新" message:@"请重新选择目标。 "];return;}WDGCartChooseLine(nil);[self refresh];}]];
    for(NSDictionary *row in rows){NSString *key=[row[@"lineKey"] copy];NSDictionary *raw=[WDGCartRawLine(key) copy];NSString *title=[NSString stringWithFormat:@"%@ · %@ × %@",row[@"title"]?:@"商品",row[@"skuTitle"]?:@"未选规格",row[@"quantity"]?:@"?"];[items addObject:[WDGMenuItem itemWithTitle:title checked:NO destructive:NO action:^{if(!raw||![raw isEqual:WDGCartRawLine(key)]||!WDGCartChooseLine(key)){[self alert:@"商品已更新" message:@"请重新核对规格和数量。 "];return;}[self refresh];}]];}
    NSString *subtitle=explicit?@"当前来源：手动指定\n只选择目标，不修改购物车、不下单。":@"当前来源：购物车勾选（默认）\n只选择目标，不修改购物车、不下单。";
    [self presentMenu:[WDGMenuSheetController menuWithTitle:@"要抢哪件" subtitle:subtitle items:items]];
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
    [self presentMenu:[WDGMenuSheetController menuWithTitle:@"下单并发" subtitle:@"多路会对同一订单目标同时发出多个请求，可能分别成功并重复下单。最终确认会列出最多订单数及总扣款上限。" items:items]];
}
- (void)showMore {
    [self endEditing];
    NSMutableArray<WDGMenuItem *> *items=[NSMutableArray array];
    WDGMenuItem *lanes=[WDGMenuItem itemWithTitle:self.concurrentLanes>1?[NSString stringWithFormat:@"并发：%lu 路",(unsigned long)self.concurrentLanes]:@"并发：单路" checked:NO destructive:NO action:^{[self chooseConcurrentLanes];}];
    lanes.enabled=self.primaryButton.enabled;[items addObject:lanes];
    BOOL retryOn=[WDGCore.shared.status[@"retryEnabled"] boolValue];
    [items addObject:[WDGMenuItem itemWithTitle:retryOn?@"循环重发：已开启（最多 3 次）":@"循环重发：已关闭" checked:NO destructive:NO action:^{[WDGCore.shared setRetryEnabled:!retryOn attempts:3];[self refresh];}]];
    BOOL adsOn=[WDGCore.shared.status[@"ads"][@"enabled"] boolValue];
    [items addObject:[WDGMenuItem itemWithTitle:adsOn?@"去广告：已开启（点按关闭）":@"去广告：已关闭（点按开启）" checked:NO destructive:NO action:^{[WDGCore.shared setAdsEnabled:!adsOn];}]];
    [self presentMenu:[WDGMenuSheetController menuWithTitle:@"更多" subtitle:nil items:items]];
}
@end
void WDGShowOverlay(void) {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{WDGShowOverlay();});return;}
    [[WDGPanel shared] ensureWindow];
}
