#import "YTAGDebugHUD.h"
#import "YTAGLog.h"

static NSString *const kSuiteName = @"afterglow.tweak";
static NSString *const kHUDEnabledKey = @"debugHUDEnabled";

@interface YTAGDebugHUDView : UIView
@property (nonatomic, strong) UITextView *textView;
@end

@implementation YTAGDebugHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.15] CGColor];
        self.layer.borderWidth = 0.5;
        self.userInteractionEnabled = YES;

        _textView = [[UITextView alloc] initWithFrame:self.bounds];
        _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _textView.backgroundColor = [UIColor clearColor];
        _textView.textColor = [UIColor colorWithWhite:1.0 alpha:0.95];
        _textView.font = [UIFont fontWithName:@"Menlo-Regular" size:9] ?: [UIFont systemFontOfSize:9];
        _textView.editable = NO;
        _textView.selectable = NO;
        _textView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
        _textView.showsVerticalScrollIndicator = NO;
        [self addSubview:_textView];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [self addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
        tap.numberOfTapsRequired = 2;
        [self addGestureRecognizer:tap];
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
        longPress.minimumPressDuration = 0.6;
        [self addGestureRecognizer:longPress];
    }
    return self;
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    CGPoint c = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    CGRect b = self.superview.bounds;
    c.x = MAX(CGRectGetWidth(self.bounds) / 2 + 4, MIN(CGRectGetWidth(b) - CGRectGetWidth(self.bounds) / 2 - 4, c.x));
    c.y = MAX(CGRectGetHeight(self.bounds) / 2 + 4, MIN(CGRectGetHeight(b) - CGRectGetHeight(self.bounds) / 2 - 4, c.y));
    self.center = c;
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)onTap:(UITapGestureRecognizer *)g { YTAGLogClear(); }
- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        [[YTAGDebugHUD sharedHUD] hide];
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
        [d setBool:NO forKey:kHUDEnabledKey];
    }
}

@end


@interface YTAGPassthroughWindow : UIWindow
@property (nonatomic, weak) UIView *passthroughTarget;
@end

@implementation YTAGPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!self.passthroughTarget) return hit;
    UIView *v = hit;
    while (v) {
        if (v == self.passthroughTarget) return hit;
        v = v.superview;
    }
    return nil;
}
@end


@interface YTAGDebugHUD ()
@property (nonatomic, strong, nullable) YTAGPassthroughWindow *window;
@property (nonatomic, strong, nullable) YTAGDebugHUDView *hudView;
@end

@implementation YTAGDebugHUD

+ (instancetype)sharedHUD {
    static YTAGDebugHUD *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [YTAGDebugHUD new]; });
    return s;
}

- (BOOL)isVisible { return self.window != nil; }

- (void)show {
    if (self.window) return;
    dispatch_block_t work = ^{
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
            }
        }
        if (!scene) return;

        YTAGPassthroughWindow *w = [[YTAGPassthroughWindow alloc] initWithWindowScene:scene];
        w.windowLevel = UIWindowLevelStatusBar + 10;
        w.backgroundColor = [UIColor clearColor];
        w.hidden = NO;

        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = [UIColor clearColor];
        w.rootViewController = vc;

        CGFloat width = MIN(CGRectGetWidth(scene.coordinateSpace.bounds) - 24, 320);
        CGFloat height = 180;
        CGFloat x = 12;
        CGFloat y = w.safeAreaInsets.top + 8;
        if (y < 44) y = 52;

        YTAGDebugHUDView *hud = [[YTAGDebugHUDView alloc] initWithFrame:CGRectMake(x, y, width, height)];
        [vc.view addSubview:hud];
        w.passthroughTarget = hud;

        self.window = w;
        self.hudView = hud;
        [self refresh];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppend) name:YTAGLogDidAppendNotification object:nil];
    };
    if ([NSThread isMainThread]) work();
    else dispatch_async(dispatch_get_main_queue(), work);
}

- (void)hide {
    dispatch_block_t work = ^{
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        self.window.hidden = YES;
        self.hudView = nil;
        self.window = nil;
    };
    if ([NSThread isMainThread]) work();
    else dispatch_async(dispatch_get_main_queue(), work);
}

- (void)onAppend { [self refresh]; }

- (void)refresh {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.hudView) return;
        NSArray *entries = YTAGLogRecentEntries();
        NSInteger start = MAX((NSInteger)0, (NSInteger)entries.count - 25);
        NSArray *slice = [entries subarrayWithRange:NSMakeRange(start, entries.count - start)];
        NSString *text = [slice componentsJoinedByString:@"\n"];
        self.hudView.textView.text = text;
        NSRange end = NSMakeRange(text.length, 0);
        [self.hudView.textView scrollRangeToVisible:end];
    });
}

+ (void)applyPreferenceOnLaunch {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    if ([d boolForKey:kHUDEnabledKey]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[YTAGDebugHUD sharedHUD] show];
        });
    }
}

@end
