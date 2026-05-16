#import "YTAGAfterglowFeedViewController.h"
#import "YTAGAfterglowFeedStore.h"
#import "../Utils/NSBundle+YTAfterglow.h"
#import "../Utils/YTAGLiteMode.h"
#import "../Utils/YTAGUserDefaults.h"

#define LOC(key) [NSBundle.ytag_defaultBundle localizedStringForKey:key value:nil table:nil]

extern UIColor *themeColor(NSString *key);
extern void YTAGRequestLoadOfSource(NSString *source);

typedef struct {
    __unsafe_unretained NSString *source;
    __unsafe_unretained NSString *title;
    __unsafe_unretained NSString *shortName; // used in placeholder copy ("Load Subscriptions")
} YTAGAfterglowPlannedSection;

static NSArray<NSDictionary *> *YTAGAfterglowPlannedSections(void) {
    static NSArray *sections = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sections = @[
            @{@"source": @"home",          @"title": @"Recommended",   @"short": @"Recommended"},
            @{@"source": @"subscriptions", @"title": @"Subscriptions", @"short": @"Subscriptions"},
            @{@"source": @"shorts",        @"title": @"Shorts",        @"short": @"Shorts"},
            @{@"source": @"history",       @"title": @"Watch History", @"short": @"Watch History"},
        ];
    });
    return sections;
}

static UIColor *YTAGFeedColor(NSString *key, UIColor *fallback) {
    UIColor *color = themeColor(key);
    return color ?: fallback;
}

static UIFont *YTAGFeedFont(CGFloat size, UIFontWeight weight) {
    return YTAGLiteModeFont(size, weight);
}

static CGSize YTAGFeedTileSize(YTAGAfterglowFeedDensity density,
                               YTAGAfterglowFeedSectionKind sectionKind,
                               YTAGAfterglowFeedContentKind contentKind) {
    BOOL mini = density == YTAGAfterglowFeedDensityMini;
    if (contentKind == YTAGAfterglowFeedContentKindShort ||
        sectionKind == YTAGAfterglowFeedSectionKindShorts) {
        return mini ? CGSizeMake(72.0, 132.0) : CGSizeMake(88.0, 156.0);
    }
    return mini ? CGSizeMake(118.0, 116.0) : CGSizeMake(144.0, 132.0);
}

static UIViewController *YTAGFeedViewControllerForResponder(UIResponder *responder) {
    UIResponder *current = responder;
    while (current) {
        if ([current isKindOfClass:[UIViewController class]]) return (UIViewController *)current;
        current = current.nextResponder;
    }
    return nil;
}

static UIWindow *YTAGFeedKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    @try {
        id delegate = (id)UIApplication.sharedApplication.delegate;
        id window = [delegate valueForKey:@"window"];
        return [window isKindOfClass:[UIWindow class]] ? window : nil;
    } @catch (__unused id exception) {
        return nil;
    }
}

static UIViewController *YTAGFeedTopPresenter(UIView *sourceView) {
    UIViewController *presenter = YTAGFeedViewControllerForResponder(sourceView);
    if (!presenter) presenter = sourceView.window.rootViewController;
    if (!presenter) presenter = YTAGFeedKeyWindow().rootViewController;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
        presenter = presenter.presentedViewController;
    }
    return presenter;
}

@interface YTAGAfterglowFeedTileView : UIControl
@property (nonatomic, strong) YTAGAfterglowFeedItem *item;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metadataLabel;
- (instancetype)initWithItem:(YTAGAfterglowFeedItem *)item
                     density:(YTAGAfterglowFeedDensity)density
                 sectionKind:(YTAGAfterglowFeedSectionKind)sectionKind;
@end

@implementation YTAGAfterglowFeedTileView

- (instancetype)initWithItem:(YTAGAfterglowFeedItem *)item
                     density:(YTAGAfterglowFeedDensity)density
                 sectionKind:(YTAGAfterglowFeedSectionKind)sectionKind {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _item = item;
    CGSize tileSize = YTAGFeedTileSize(density, sectionKind, item.contentKind);
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;

    UIColor *cardColor = YTAGFeedColor(@"theme_navBar", UIColor.secondarySystemBackgroundColor);
    UIColor *textColor = YTAGFeedColor(@"theme_textPrimary", UIColor.labelColor);
    UIColor *secondaryText = YTAGFeedColor(@"theme_textSecondary", UIColor.secondaryLabelColor);

    UIView *thumbShell = [UIView new];
    thumbShell.translatesAutoresizingMaskIntoConstraints = NO;
    thumbShell.backgroundColor = [cardColor colorWithAlphaComponent:0.92];
    thumbShell.layer.cornerRadius = 8.0;
    thumbShell.layer.cornerCurve = kCACornerCurveContinuous;
    thumbShell.clipsToBounds = YES;
    thumbShell.userInteractionEnabled = NO;
    [self addSubview:thumbShell];

    _imageView = [UIImageView new];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    _imageView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    _imageView.clipsToBounds = YES;
    _imageView.userInteractionEnabled = NO;
    [thumbShell addSubview:_imageView];

    UILabel *duration = [UILabel new];
    duration.translatesAutoresizingMaskIntoConstraints = NO;
    duration.text = item.duration;
    duration.textColor = UIColor.whiteColor;
    duration.font = YTAGFeedFont(9.0, UIFontWeightSemibold);
    duration.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.62];
    duration.textAlignment = NSTextAlignmentCenter;
    duration.layer.cornerRadius = 4.0;
    duration.clipsToBounds = YES;
    duration.hidden = item.duration.length == 0;
    duration.userInteractionEnabled = NO;
    [thumbShell addSubview:duration];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = item.title;
    _titleLabel.textColor = textColor;
    _titleLabel.font = YTAGFeedFont(density == YTAGAfterglowFeedDensityMini ? 10.0 : 11.0, UIFontWeightSemibold);
    _titleLabel.numberOfLines = 2;
    _titleLabel.minimumScaleFactor = 0.82;
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.userInteractionEnabled = NO;
    [self addSubview:_titleLabel];

    _metadataLabel = [UILabel new];
    _metadataLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _metadataLabel.text = item.metadata.length > 0 ? item.metadata : item.subtitle;
    _metadataLabel.textColor = secondaryText;
    _metadataLabel.font = YTAGFeedFont(9.0, UIFontWeightRegular);
    _metadataLabel.numberOfLines = 1;
    _metadataLabel.minimumScaleFactor = 0.78;
    _metadataLabel.adjustsFontSizeToFitWidth = YES;
    _metadataLabel.userInteractionEnabled = NO;
    [self addSubview:_metadataLabel];

    CGFloat thumbHeight = (item.contentKind == YTAGAfterglowFeedContentKindShort ||
                           sectionKind == YTAGAfterglowFeedSectionKindShorts)
        ? tileSize.height - 32.0
        : floor(tileSize.width * 9.0 / 16.0);

    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:tileSize.width],
        [self.heightAnchor constraintEqualToConstant:tileSize.height],
        [thumbShell.topAnchor constraintEqualToAnchor:self.topAnchor],
        [thumbShell.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [thumbShell.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [thumbShell.heightAnchor constraintEqualToConstant:thumbHeight],
        [_imageView.topAnchor constraintEqualToAnchor:thumbShell.topAnchor],
        [_imageView.leadingAnchor constraintEqualToAnchor:thumbShell.leadingAnchor],
        [_imageView.trailingAnchor constraintEqualToAnchor:thumbShell.trailingAnchor],
        [_imageView.bottomAnchor constraintEqualToAnchor:thumbShell.bottomAnchor],
        [duration.trailingAnchor constraintEqualToAnchor:thumbShell.trailingAnchor constant:-4.0],
        [duration.bottomAnchor constraintEqualToAnchor:thumbShell.bottomAnchor constant:-4.0],
        [duration.widthAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [duration.heightAnchor constraintEqualToConstant:16.0],
        [_titleLabel.topAnchor constraintEqualToAnchor:thumbShell.bottomAnchor constant:5.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_metadataLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
        [_metadataLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_metadataLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    [self loadThumbnailURLString:item.thumbnailURLString];
    [self addTarget:self action:@selector(pressIn) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(pressOut) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return self;
}

- (void)loadThumbnailURLString:(NSString *)urlString {
    if (urlString.length == 0) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:28.0 weight:UIImageSymbolWeightSemibold];
        self.imageView.image = [UIImage systemImageNamed:@"play.rectangle.fill" withConfiguration:config];
        self.imageView.tintColor = YTAGFeedColor(@"theme_accent", UIColor.whiteColor);
        self.imageView.contentMode = UIViewContentModeCenter;
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data.length == 0 || error) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.imageView.contentMode = UIViewContentModeScaleAspectFill;
            weakSelf.imageView.image = image;
        });
    }] resume];
}

- (void)pressIn {
    [UIView animateWithDuration:0.10 animations:^{
        self.alpha = 0.72;
        self.transform = CGAffineTransformMakeScale(0.98, 0.98);
    }];
}

- (void)pressOut {
    [UIView animateWithDuration:0.14 animations:^{
        self.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
    }];
}

@end

@interface YTAGAfterglowPlaceholderTileView : UIControl
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong) UILabel *primaryLabel;
@property (nonatomic, strong) UILabel *secondaryLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (instancetype)initWithSource:(NSString *)source title:(NSString *)title state:(YTAGAfterglowSourceLoadState)state elapsedSeconds:(NSTimeInterval)elapsed;
@end

@implementation YTAGAfterglowPlaceholderTileView

- (instancetype)initWithSource:(NSString *)source title:(NSString *)title state:(YTAGAfterglowSourceLoadState)state elapsedSeconds:(NSTimeInterval)elapsed {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _source = [source copy];
    self.translatesAutoresizingMaskIntoConstraints = NO;

    UIColor *card = YTAGFeedColor(@"theme_navBar", UIColor.secondarySystemBackgroundColor);
    UIColor *textPrimary = YTAGFeedColor(@"theme_textPrimary", UIColor.labelColor);
    UIColor *textSecondary = YTAGFeedColor(@"theme_textSecondary", UIColor.secondaryLabelColor);
    UIColor *accent = YTAGFeedColor(@"theme_accent", UIColor.systemBlueColor);

    self.backgroundColor = [card colorWithAlphaComponent:0.92];
    self.layer.cornerRadius = 10.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [accent colorWithAlphaComponent:0.35].CGColor;
    self.clipsToBounds = YES;

    _primaryLabel = [UILabel new];
    _primaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _primaryLabel.font = YTAGFeedFont(13.0, UIFontWeightSemibold);
    _primaryLabel.textColor = textPrimary;
    _primaryLabel.textAlignment = NSTextAlignmentCenter;
    _primaryLabel.numberOfLines = 1;
    [self addSubview:_primaryLabel];

    _secondaryLabel = [UILabel new];
    _secondaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _secondaryLabel.font = YTAGFeedFont(10.0, UIFontWeightRegular);
    _secondaryLabel.textColor = textSecondary;
    _secondaryLabel.textAlignment = NSTextAlignmentCenter;
    _secondaryLabel.numberOfLines = 2;
    [self addSubview:_secondaryLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.color = accent;
    _spinner.hidesWhenStopped = YES;
    [self addSubview:_spinner];

    [self applyState:state title:title elapsedSeconds:elapsed];

    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:116.0],
        [self.widthAnchor constraintEqualToConstant:220.0],
        [_spinner.topAnchor constraintEqualToAnchor:self.topAnchor constant:18.0],
        [_spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_primaryLabel.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:8.0],
        [_primaryLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_primaryLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
        [_secondaryLabel.topAnchor constraintEqualToAnchor:_primaryLabel.bottomAnchor constant:4.0],
        [_secondaryLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
        [_secondaryLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
    ]];
    return self;
}

- (void)applyState:(YTAGAfterglowSourceLoadState)state title:(NSString *)title elapsedSeconds:(NSTimeInterval)elapsed {
    switch (state) {
        case YTAGAfterglowSourceLoadStateLoading:
            [self.spinner startAnimating];
            self.primaryLabel.text = [NSString stringWithFormat:@"Loading %@…", title];
            self.secondaryLabel.text = [NSString stringWithFormat:@"%.1fs · briefly switches tabs", MAX(elapsed, 0.0)];
            self.userInteractionEnabled = NO;
            break;
        case YTAGAfterglowSourceLoadStateFailed:
            [self.spinner stopAnimating];
            self.primaryLabel.text = [NSString stringWithFormat:@"Couldn't load %@", title];
            self.secondaryLabel.text = @"Tap to retry";
            self.userInteractionEnabled = YES;
            break;
        case YTAGAfterglowSourceLoadStateLoaded:
        case YTAGAfterglowSourceLoadStateIdle:
        default:
            [self.spinner stopAnimating];
            self.primaryLabel.text = [NSString stringWithFormat:@"Load %@", title];
            self.secondaryLabel.text = @"Briefly switches to that tab";
            self.userInteractionEnabled = YES;
            break;
    }
}

@end

@interface YTAGAfterglowFeedViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, copy) NSArray<YTAGAfterglowFeedSection *> *sections;
@property (nonatomic, assign) YTAGAfterglowFeedDensity density;
@property (nonatomic, strong) NSMutableDictionary<NSString *, YTAGAfterglowPlaceholderTileView *> *placeholders;
@property (nonatomic, strong) NSTimer *spinnerTimer;
@end

@implementation YTAGAfterglowFeedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LOC(@"FEafterglow");
    self.density = [[YTAGUserDefaults standardUserDefaults] currentAfterglowFeedDensity];
    self.view.backgroundColor = YTAGFeedColor(@"theme_background", UIColor.systemBackgroundColor);
    self.placeholders = [NSMutableDictionary dictionary];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                           target:self
                                                                                           action:@selector(closeFeed)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(feedStoreDidUpdate:)
                                                 name:YTAGAfterglowFeedStoreDidUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(feedStoreDidUpdate:)
                                                 name:YTAGAfterglowFeedStoreLoadStateDidChangeNotification
                                               object:nil];
    [self reloadSections];
    [self buildLayout];
    [self startSpinnerTimerIfNeeded];
}

- (void)dealloc {
    [self.spinnerTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)feedStoreDidUpdate:(NSNotification *)notification {
    [self reloadSections];
    [self rebuildStack];
    [self startSpinnerTimerIfNeeded];
}

- (void)reloadSections {
    self.sections = [[YTAGAfterglowFeedStore sharedStore] currentSections];
}

- (void)startSpinnerTimerIfNeeded {
    BOOL anyLoading = NO;
    for (NSDictionary *planned in YTAGAfterglowPlannedSections()) {
        if ([[YTAGAfterglowFeedStore sharedStore] loadStateForSource:planned[@"source"]] == YTAGAfterglowSourceLoadStateLoading) {
            anyLoading = YES;
            break;
        }
    }
    if (anyLoading && !self.spinnerTimer) {
        self.spinnerTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(tickSpinners) userInfo:nil repeats:YES];
    } else if (!anyLoading && self.spinnerTimer) {
        [self.spinnerTimer invalidate];
        self.spinnerTimer = nil;
    }
}

- (void)tickSpinners {
    YTAGAfterglowFeedStore *store = [YTAGAfterglowFeedStore sharedStore];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    for (NSDictionary *planned in YTAGAfterglowPlannedSections()) {
        NSString *source = planned[@"source"];
        if ([store loadStateForSource:source] != YTAGAfterglowSourceLoadStateLoading) continue;
        YTAGAfterglowPlaceholderTileView *tile = self.placeholders[source];
        if (!tile) continue;
        NSTimeInterval start = [store loadStartTimeForSource:source];
        NSTimeInterval elapsed = start > 0 ? (now - start) : 0;
        [tile applyState:YTAGAfterglowSourceLoadStateLoading title:planned[@"short"] elapsedSeconds:elapsed];
    }
}

- (void)buildLayout {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.scrollView];

    self.stackView = [UIStackView new];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 18.0;
    [self.scrollView addSubview:self.stackView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:14.0],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:14.0],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-14.0],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-24.0],
    ]];

    [self rebuildStack];
}

- (void)rebuildStack {
    if (!self.stackView) return;
    for (UIView *view in self.stackView.arrangedSubviews) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [self.placeholders removeAllObjects];

    YTAGAfterglowFeedStore *store = [YTAGAfterglowFeedStore sharedStore];
    NSDictionary<NSString *, YTAGAfterglowFeedSection *> *byKind = [self sectionsByKindMap];

    for (NSDictionary *planned in YTAGAfterglowPlannedSections()) {
        NSString *source = planned[@"source"];
        NSString *title = planned[@"title"];

        YTAGAfterglowFeedSection *section = byKind[[self sectionKindKeyForSource:source]];
        if (section.items.count > 0) {
            [self.stackView addArrangedSubview:[self viewForSection:section]];
            continue;
        }

        // Recommended populates naturally from Home browsing — show only a
        // hint rather than a load button.
        if ([source isEqualToString:@"home"]) {
            [self.stackView addArrangedSubview:[self hintRowForTitle:title hint:@"Browse Home once to populate this rail."]];
            continue;
        }

        YTAGAfterglowSourceLoadState state = [store loadStateForSource:source];
        NSTimeInterval elapsed = 0;
        if (state == YTAGAfterglowSourceLoadStateLoading) {
            NSTimeInterval start = [store loadStartTimeForSource:source];
            elapsed = start > 0 ? ([NSDate timeIntervalSinceReferenceDate] - start) : 0;
        }
        [self.stackView addArrangedSubview:[self placeholderRowForTitle:title source:source state:state elapsed:elapsed]];
    }
}

- (NSDictionary<NSString *, YTAGAfterglowFeedSection *> *)sectionsByKindMap {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (YTAGAfterglowFeedSection *section in self.sections) {
        map[[self sectionKindKeyForKind:section.kind]] = section;
    }
    return map;
}

- (NSString *)sectionKindKeyForKind:(YTAGAfterglowFeedSectionKind)kind {
    switch (kind) {
        case YTAGAfterglowFeedSectionKindRecommended:   return @"home";
        case YTAGAfterglowFeedSectionKindSubscriptions: return @"subscriptions";
        case YTAGAfterglowFeedSectionKindShorts:        return @"shorts";
        case YTAGAfterglowFeedSectionKindHype:          return @"history";
    }
    return @"";
}

- (NSString *)sectionKindKeyForSource:(NSString *)source {
    return source ?: @"";
}

- (UIView *)placeholderRowForTitle:(NSString *)title source:(NSString *)source state:(YTAGAfterglowSourceLoadState)state elapsed:(NSTimeInterval)elapsed {
    UIStackView *container = [UIStackView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.axis = UILayoutConstraintAxisVertical;
    container.spacing = 8.0;

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.textColor = YTAGFeedColor(@"theme_textPrimary", UIColor.labelColor);
    titleLabel.font = YTAGFeedFont(17.0, UIFontWeightBold);
    [container addArrangedSubview:titleLabel];

    NSDictionary *planned = nil;
    for (NSDictionary *p in YTAGAfterglowPlannedSections()) {
        if ([p[@"source"] isEqualToString:source]) { planned = p; break; }
    }

    YTAGAfterglowPlaceholderTileView *tile = [[YTAGAfterglowPlaceholderTileView alloc] initWithSource:source
                                                                                                title:planned[@"short"] ?: title
                                                                                                state:state
                                                                                       elapsedSeconds:elapsed];
    [tile addTarget:self action:@selector(didTapPlaceholder:) forControlEvents:UIControlEventTouchUpInside];
    self.placeholders[source] = tile;
    [container addArrangedSubview:tile];
    return container;
}

- (UIView *)hintRowForTitle:(NSString *)title hint:(NSString *)hint {
    UIStackView *container = [UIStackView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.axis = UILayoutConstraintAxisVertical;
    container.spacing = 4.0;

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.textColor = YTAGFeedColor(@"theme_textPrimary", UIColor.labelColor);
    titleLabel.font = YTAGFeedFont(17.0, UIFontWeightBold);
    [container addArrangedSubview:titleLabel];

    UILabel *hintLabel = [UILabel new];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.text = hint;
    hintLabel.textColor = YTAGFeedColor(@"theme_textSecondary", UIColor.secondaryLabelColor);
    hintLabel.font = YTAGFeedFont(12.0, UIFontWeightRegular);
    hintLabel.numberOfLines = 0;
    [container addArrangedSubview:hintLabel];

    return container;
}

- (void)didTapPlaceholder:(YTAGAfterglowPlaceholderTileView *)tile {
    if (!tile.source) return;
    YTAGRequestLoadOfSource(tile.source);
}

- (UIView *)viewForSection:(YTAGAfterglowFeedSection *)section {
    UIStackView *container = [UIStackView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.axis = UILayoutConstraintAxisVertical;
    container.spacing = 8.0;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = section.title;
    title.textColor = YTAGFeedColor(@"theme_textPrimary", UIColor.labelColor);
    title.font = YTAGFeedFont(17.0, UIFontWeightBold);
    [container addArrangedSubview:title];

    UIScrollView *rail = [UIScrollView new];
    rail.translatesAutoresizingMaskIntoConstraints = NO;
    rail.showsHorizontalScrollIndicator = NO;
    rail.alwaysBounceHorizontal = YES;
    [container addArrangedSubview:rail];

    UIStackView *row = [UIStackView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = self.density == YTAGAfterglowFeedDensityMini ? 8.0 : 10.0;
    [rail addSubview:row];

    CGFloat maxHeight = 1.0;
    for (YTAGAfterglowFeedItem *item in section.items) {
        YTAGAfterglowFeedTileView *tile = [[YTAGAfterglowFeedTileView alloc] initWithItem:item density:self.density sectionKind:section.kind];
        [tile addTarget:self action:@selector(didTapTile:) forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:tile];
        maxHeight = MAX(maxHeight, YTAGFeedTileSize(self.density, section.kind, item.contentKind).height);
    }

    [NSLayoutConstraint activateConstraints:@[
        [rail.heightAnchor constraintEqualToConstant:maxHeight],
        [row.topAnchor constraintEqualToAnchor:rail.contentLayoutGuide.topAnchor],
        [row.leadingAnchor constraintEqualToAnchor:rail.contentLayoutGuide.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:rail.contentLayoutGuide.trailingAnchor],
        [row.bottomAnchor constraintEqualToAnchor:rail.contentLayoutGuide.bottomAnchor],
        [row.heightAnchor constraintEqualToAnchor:rail.frameLayoutGuide.heightAnchor],
    ]];

    return container;
}

- (void)didTapTile:(YTAGAfterglowFeedTileView *)tile {
    [[YTAGAfterglowFeedStore sharedStore] openItem:tile.item fromView:tile firstResponder:self];
}

- (void)closeFeed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

void YTAGOpenAfterglowFeedFromView(UIView *sourceView) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = YTAGFeedTopPresenter(sourceView);
        if (!presenter) return;
        if ([presenter isKindOfClass:[YTAGAfterglowFeedViewController class]]) return;
        if ([presenter isKindOfClass:[UINavigationController class]] &&
            [((UINavigationController *)presenter).topViewController isKindOfClass:[YTAGAfterglowFeedViewController class]]) {
            return;
        }

        YTAGAfterglowFeedViewController *feed = [YTAGAfterglowFeedViewController new];
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:feed];
        navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
        navigationController.view.tintColor = YTAGFeedColor(@"theme_accent", UIColor.systemBlueColor);

        if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheet = navigationController.sheetPresentationController;
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 18.0;
        }

        [presenter presentViewController:navigationController animated:YES completion:nil];
    });
}
