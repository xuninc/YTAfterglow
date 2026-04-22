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

- (void)highlightOn {
    [UIView animateWithDuration:0.1 animations:^{
        self.alpha = 0.6;
        self.transform = CGAffineTransformMakeScale(0.97, 0.97);
    }];
}

- (void)highlightOff {
    [UIView animateWithDuration:0.15 animations:^{
        self.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
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
                                                          title:@"Copy Info"
                                                     symbolName:@"doc.on.doc"
                                                           chip:nil];
    YTAGActionTile *t6 = [[YTAGActionTile alloc] initWithAction:YTAGDownloadActionPlayInExternalPlayer
                                                          title:@"Ext. Player"
                                                     symbolName:@"arrow.up.forward.app"
                                                           chip:nil];

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
    ]];
}

- (void)tileTapped:(YTAGActionTile *)sender {
    YTAGLog(@"action-sheet", @"tile action=%ld", (long)sender.action);
    void (^cb)(YTAGDownloadAction) = self.onAction;
    YTAGDownloadAction action = sender.action;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(action);
    }];
}

@end
