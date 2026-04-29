// YTAGDownloadActionSheetViewController.m
//
// 2×3 tile grid bottom sheet. iOS 13+. On iOS 15+ uses
// UISheetPresentationController with an undimmed medium detent so the
// video stays fully visible above the sheet.

#import "YTAGDownloadActionSheetViewController.h"
#import "../Utils/YTAGLog.h"

#pragma mark - Tile (single action square)

@interface YTAGActionTile : UIControl
@property (nonatomic, assign) YTAGDownloadAction action;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *chipLabel;   // small secondary text, e.g. "2.4 MB"
- (instancetype)initWithAction:(YTAGDownloadAction)action
                         title:(NSString *)title
                    symbolName:(NSString *)symbolName
                          chip:(nullable NSString *)chip;
@end

@implementation YTAGActionTile

- (instancetype)initWithAction:(YTAGDownloadAction)action
                         title:(NSString *)title
                    symbolName:(NSString *)symbolName
                          chip:(NSString *)chip
{
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _action = action;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.layer.cornerRadius = 14;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    _iconView = [UIImageView new];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = [UIColor labelColor];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.userInteractionEnabled = NO;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular];
        UIImage *img = [UIImage systemImageNamed:symbolName];
        _iconView.image = [img imageByApplyingSymbolConfiguration:cfg] ?: img;
    }

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 2;
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.minimumScaleFactor = 0.8;
    _titleLabel.text = title;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.userInteractionEnabled = NO;

    _chipLabel = [UILabel new];
    _chipLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _chipLabel.textColor = [UIColor secondaryLabelColor];
    _chipLabel.textAlignment = NSTextAlignmentCenter;
    _chipLabel.text = chip;
    _chipLabel.hidden = (chip.length == 0);
    _chipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _chipLabel.userInteractionEnabled = NO;

    [self addSubview:_iconView];
    [self addSubview:_titleLabel];
    [self addSubview:_chipLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:32],
        [_iconView.heightAnchor constraintEqualToConstant:32],

        [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:8],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],

        [_chipLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        [_chipLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
        [_chipLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],

        [self.heightAnchor constraintEqualToConstant:100],
    ]];

    // Press-state visual feedback (dim on highlight).
    [self addTarget:self action:@selector(highlightOn) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(highlightOff) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchDragExit | UIControlEventTouchCancel];

    return self;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.38;
    self.iconView.tintColor = enabled ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
    self.titleLabel.textColor = enabled ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
    self.chipLabel.textColor = enabled ? [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor];
}

- (void)highlightOn {
    if (!self.enabled) return;
    [UIView animateWithDuration:0.1 animations:^{
        self.alpha = 0.6;
        self.transform = CGAffineTransformMakeScale(0.97, 0.97);
    }];
}

- (void)highlightOff {
    [UIView animateWithDuration:0.15 animations:^{
        self.alpha = self.enabled ? 1.0 : 0.38;
        self.transform = CGAffineTransformIdentity;
    }];
}

@end

#pragma mark - Compact list picker

@implementation YTAGDownloadPickerEntry

+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                    symbolName:(NSString *)symbolName
              representedObject:(id)representedObject
{
    YTAGDownloadPickerEntry *entry = [YTAGDownloadPickerEntry new];
    entry.title = title ?: @"";
    entry.subtitle = subtitle;
    entry.symbolName = symbolName.length > 0 ? symbolName : @"doc";
    entry.representedObject = representedObject;
    return entry;
}

@end

@interface YTAGDownloadListPickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UITableView *tableView;
@end

static UIImage *YTAGPickerImageNamed(NSString *symbolName, NSString *fallbackName, UIImageSymbolConfiguration *configuration) {
    UIImage *image = [UIImage systemImageNamed:symbolName];
    if (!image && fallbackName.length > 0) image = [UIImage systemImageNamed:fallbackName];
    if (!image) image = [UIImage systemImageNamed:@"doc"];
    UIImage *configured = [image imageByApplyingSymbolConfiguration:configuration];
    return configured ?: image;
}

@implementation YTAGDownloadListPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.entries = self.entries ?: @[];
    NSUInteger cappedCount = MIN(MAX(self.entries.count, 1), 7);
    self.preferredContentSize = CGSizeMake(390.0, 96.0 + cappedCount * 58.0);
    [self configureSheetPresentation];
    [self buildListLayout];
}

- (void)configureSheetPresentation {
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 20;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
        sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
    }
    self.view.backgroundColor = [UIColor clearColor];
}

- (CGFloat)fontScale {
    switch (self.fontScaleMode) {
        case 2: return 1.10;
        case 1: return 1.00;
        case 0:
        default:
            return 0.88;
    }
}

- (UIFont *)fontWithSize:(CGFloat)size weight:(UIFontWeight)weight {
    CGFloat scaledSize = size * [self fontScale];
    if (@available(iOS 13.0, *)) {
        UIFontDescriptorSystemDesign design = UIFontDescriptorSystemDesignDefault;
        switch (self.fontFaceMode) {
            case 1: design = UIFontDescriptorSystemDesignRounded; break;
            case 2: design = UIFontDescriptorSystemDesignSerif; break;
            case 3: design = UIFontDescriptorSystemDesignMonospaced; break;
            case 0:
            default:
                design = UIFontDescriptorSystemDesignDefault;
                break;
        }
        UIFont *base = [UIFont systemFontOfSize:scaledSize weight:weight];
        UIFontDescriptor *descriptor = [base.fontDescriptor fontDescriptorWithDesign:design];
        if (descriptor) return [UIFont fontWithDescriptor:descriptor size:scaledSize];
    }
    return [UIFont systemFontOfSize:scaledSize weight:weight];
}

- (void)buildListLayout {
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    self.blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.blurView];
    [NSLayoutConstraint activateConstraints:@[
        [self.blurView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.blurView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.blurView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.blurView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIView *content = self.blurView.contentView;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = self.titleText ?: @"Choose";
    title.textColor = [UIColor labelColor];
    title.font = [self fontWithSize:18.0 weight:UIFontWeightSemibold];
    title.numberOfLines = 2;
    [content addSubview:title];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 58.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 58.0, 0, 16.0);
    [content addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:content.safeAreaLayoutGuide.topAnchor constant:14],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [self.tableView.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"YTAGDownloadPickerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
        cell.selectedBackgroundView = [UIView new];
        cell.selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    }

    YTAGDownloadPickerEntry *entry = self.entries[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry.title;
    cell.textLabel.font = [self fontWithSize:15.0 weight:UIFontWeightSemibold];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = entry.subtitle;
    cell.detailTextLabel.font = [self fontWithSize:12.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 1;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
        UIImage *img = YTAGPickerImageNamed(entry.symbolName, @"play.rectangle", cfg);
        cell.imageView.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        cell.imageView.tintColor = [UIColor labelColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    YTAGDownloadPickerEntry *entry = self.entries[(NSUInteger)indexPath.row];
    void (^cb)(YTAGDownloadPickerEntry *) = self.onSelectEntry;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(entry);
    }];
}

@end

#pragma mark - View controller

@interface YTAGDownloadActionSheetViewController ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *channelLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSArray<YTAGActionTile *> *tiles;
@end

@implementation YTAGDownloadActionSheetViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.preferredContentSize = CGSizeMake(390.0, 380.0);
    [self configureSheetPresentation];
    [self buildLayout];
}

- (void)configureSheetPresentation {
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 20;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
        // Keep video fully visible above the sheet at medium — no background dim.
        // At large (user drags up) the dim returns naturally.
        sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
    }
    self.view.backgroundColor = [UIColor clearColor];
}

- (void)buildLayout {
    // Blur background for modern glass look.
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    self.blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.blurView];
    [NSLayoutConstraint activateConstraints:@[
        [self.blurView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.blurView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.blurView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.blurView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIView *content = self.blurView.contentView;

    // Header
    self.channelLabel = [UILabel new];
    self.channelLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.channelLabel.textColor = [UIColor secondaryLabelColor];
    self.channelLabel.text = self.channelName ?: @"";
    self.channelLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.titleLabel = [UILabel new];
    self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.text = self.videoTitle ?: @"";
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:self.channelLabel];
    [content addSubview:self.titleLabel];

    // Tiles: 2 rows × 3 columns.
    YTAGActionTile *t1 = [[YTAGActionTile alloc] initWithAction:YTAGDownloadActionDownloadVideo
                                                          title:@"Video"
                                                     symbolName:@"arrow.down.to.line"
                                                           chip:nil];
    YTAGActionTile *t2 = [[YTAGActionTile alloc] initWithAction:YTAGDownloadActionDownloadAudio
                                                          title:@"Audio"
                                                     symbolName:@"music.note"
                                                           chip:self.audioSizeChip];
    YTAGActionTile *t3 = [[YTAGActionTile alloc] initWithAction:YTAGDownloadActionDownloadCaptions
                                                          title:@"Captions"
                                                     symbolName:@"captions.bubble"
                                                           chip:nil];
    YTAGActionTile *t4 = [[YTAGActionTile alloc] initWithAction:YTAGDownloadActionSaveImage
                                                          title:@"Thumbnail"
                                                     symbolName:@"photo"
                                                           chip:nil];
    YTAGActionTile *t5 = [[YTAGActionTile alloc] initWithAction:YTAGDownloadActionCopyInformation
                                                          title:@"Details"
                                                     symbolName:@"doc.on.doc"
                                                           chip:nil];
    YTAGActionTile *t6 = [[YTAGActionTile alloc] initWithAction:YTAGDownloadActionPlayInExternalPlayer
                                                          title:@"Open In…"
                                                     symbolName:@"arrow.up.forward.app"
                                                           chip:nil];
    t1.enabled = self.videoAvailable;
    t2.enabled = self.audioAvailable;
    t3.enabled = self.captionsAvailable;
    t4.enabled = self.thumbnailAvailable;
    t6.enabled = self.externalPlaybackAvailable;

    self.tiles = @[t1, t2, t3, t4, t5, t6];
    for (YTAGActionTile *tile in self.tiles) {
        [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
    }

    UIStackView *row1 = [[UIStackView alloc] initWithArrangedSubviews:@[t1, t2, t3]];
    row1.axis = UILayoutConstraintAxisHorizontal;
    row1.distribution = UIStackViewDistributionFillEqually;
    row1.spacing = 10;
    row1.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *row2 = [[UIStackView alloc] initWithArrangedSubviews:@[t4, t5, t6]];
    row2.axis = UILayoutConstraintAxisHorizontal;
    row2.distribution = UIStackViewDistributionFillEqually;
    row2.spacing = 10;
    row2.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *grid = [[UIStackView alloc] initWithArrangedSubviews:@[row1, row2]];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 10;
    grid.translatesAutoresizingMaskIntoConstraints = NO;

    [content addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [self.channelLabel.topAnchor constraintEqualToAnchor:content.safeAreaLayoutGuide.topAnchor constant:16],
        [self.channelLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.channelLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.channelLabel.bottomAnchor constant:2],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],

        [grid.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [grid.bottomAnchor constraintLessThanOrEqualToAnchor:content.safeAreaLayoutGuide.bottomAnchor constant:-16],
    ]];
}

- (void)tileTapped:(YTAGActionTile *)sender {
    if (!sender.enabled) return;
    YTAGLog(@"action-sheet", @"tile action=%ld", (long)sender.action);
    void (^cb)(YTAGDownloadAction) = self.onAction;
    YTAGDownloadAction action = sender.action;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(action);
    }];
}

@end
