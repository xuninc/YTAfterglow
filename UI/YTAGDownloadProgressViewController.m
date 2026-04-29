#import "YTAGDownloadProgressViewController.h"
#import "../Utils/YTAGLog.h"

@interface YTAGDownloadProgressViewController () <UIAdaptivePresentationControllerDelegate>

@property (nonatomic, strong) UIImageView    *thumbnailView;
@property (nonatomic, strong) NSLayoutConstraint *thumbnailHeightConstraint;
@property (nonatomic, strong) UILabel         *titleLabel;
@property (nonatomic, strong) UILabel         *phaseLabel;
@property (nonatomic, strong) UILabel         *subtitleLabel;
@property (nonatomic, strong) UIProgressView  *progressView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView     *checkmarkView;
@property (nonatomic, strong) UIButton        *cancelButton;

@property (nonatomic, assign) BOOL viewReady;
@property (nonatomic, assign) BOOL cancelInFlight;

@end

@implementation YTAGDownloadProgressViewController

#pragma mark - Lifecycle

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _phase = YTAGDownloadPhaseDownloadingVideo;
        _progressFraction = 0.0;
        self.modalPresentationStyle = UIModalPresentationPageSheet;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.modalPresentationStyle = UIModalPresentationPageSheet;
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.preferredContentSize = CGSizeMake(390.0, 520.0);

    if (self.presentationController) {
        self.presentationController.delegate = self;
    }
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        sheet.detents = @[
            UISheetPresentationControllerDetent.mediumDetent,
            UISheetPresentationControllerDetent.largeDetent
        ];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 18.0;
    }

    [self buildHierarchy];
    [self installConstraints];

    self.viewReady = YES;
    [self refreshAllUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Re-assert delegate; presentationController can be nil at viewDidLoad in some flows.
    if (self.presentationController && self.presentationController.delegate == nil) {
        self.presentationController.delegate = self;
    }
    [self updateInteractiveDismissal];
}

#pragma mark - View construction

- (void)buildHierarchy {
    _thumbnailView = [[UIImageView alloc] init];
    _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
    _thumbnailView.contentMode = UIViewContentModeScaleAspectFit;
    _thumbnailView.clipsToBounds = YES;
    _thumbnailView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_thumbnailView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 2;
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.minimumScaleFactor = 0.75;
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _titleLabel.textColor = [UIColor labelColor];
    [self.view addSubview:_titleLabel];

    _phaseLabel = [[UILabel alloc] init];
    _phaseLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _phaseLabel.textAlignment = NSTextAlignmentCenter;
    _phaseLabel.numberOfLines = 1;
    _phaseLabel.adjustsFontSizeToFitWidth = YES;
    _phaseLabel.minimumScaleFactor = 0.75;
    _phaseLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _phaseLabel.textColor = [UIColor labelColor];
    [self.view addSubview:_phaseLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    _subtitleLabel.numberOfLines = 2;
    _subtitleLabel.adjustsFontSizeToFitWidth = YES;
    _subtitleLabel.minimumScaleFactor = 0.75;
    _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _subtitleLabel.textColor = [UIColor secondaryLabelColor];
    [self.view addSubview:_subtitleLabel];

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_progressView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    UIImage *check = [UIImage systemImageNamed:@"checkmark.circle.fill"];
    _checkmarkView = [[UIImageView alloc] initWithImage:check];
    _checkmarkView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkmarkView.tintColor = [UIColor systemGreenColor];
    _checkmarkView.contentMode = UIViewContentModeScaleAspectFit;
    _checkmarkView.hidden = YES;
    _checkmarkView.alpha = 0.0;
    [self.view addSubview:_checkmarkView];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [_cancelButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [_cancelButton setTitleColor:[[UIColor systemRedColor] colorWithAlphaComponent:0.4] forState:UIControlStateDisabled];
    _cancelButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [_cancelButton addTarget:self action:@selector(handleCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelButton];
}

- (void)installConstraints {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    const CGFloat hInset = 16.0;

    _thumbnailHeightConstraint = [_thumbnailView.heightAnchor constraintEqualToConstant:300.0];
    _thumbnailHeightConstraint.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [_thumbnailView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12.0],
        [_thumbnailView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_thumbnailView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        _thumbnailHeightConstraint,

        [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailView.bottomAnchor constant:16.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:hInset],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-hInset],

        [_phaseLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:16.0],
        [_phaseLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:hInset],
        [_phaseLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-hInset],

        [_subtitleLabel.topAnchor constraintEqualToAnchor:_phaseLabel.bottomAnchor constant:4.0],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:hInset],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-hInset],

        [_progressView.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:16.0],
        [_progressView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:hInset],
        [_progressView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-hInset],

        [_spinner.centerXAnchor constraintEqualToAnchor:_progressView.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_progressView.centerYAnchor],

        [_checkmarkView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_checkmarkView.topAnchor constraintEqualToAnchor:_phaseLabel.bottomAnchor constant:12.0],
        [_checkmarkView.widthAnchor constraintEqualToConstant:64.0],
        [_checkmarkView.heightAnchor constraintEqualToConstant:64.0],

        [_cancelButton.topAnchor constraintEqualToAnchor:_progressView.bottomAnchor constant:20.0],
        [_cancelButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_cancelButton.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-12.0],
    ]];
}

#pragma mark - Setters (override synthesized)

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy];
    [self dispatchMain:^{ [self refreshTitle]; }];
}

- (void)setThumbnailImage:(UIImage *)thumbnailImage {
    _thumbnailImage = thumbnailImage;
    [self dispatchMain:^{ [self refreshThumbnail]; }];
}

- (void)setPhase:(YTAGDownloadPhase)phase {
    YTAGDownloadPhase previous = _phase;
    _phase = phase;
    if (previous != phase) {
        YTAGLog(@"dl-ui", @"phase %ld -> %ld", (long)previous, (long)phase);
    }
    [self dispatchMain:^{ [self refreshForPhaseChange]; }];
}

- (void)setProgressFraction:(double)progressFraction {
    if (progressFraction < 0.0) progressFraction = 0.0;
    if (progressFraction > 1.0) progressFraction = 1.0;
    _progressFraction = progressFraction;
    [self dispatchMain:^{ [self refreshProgress]; }];
}

- (void)setSubtitleText:(NSString *)subtitleText {
    _subtitleText = [subtitleText copy];
    [self dispatchMain:^{ [self refreshSubtitle]; }];
}

- (void)setOnCancel:(void (^)(void))onCancel {
    _onCancel = [onCancel copy];
    [self dispatchMain:^{ [self refreshCancelButtonVisibility]; }];
}

#pragma mark - Refresh

- (void)refreshAllUI {
    [self refreshTitle];
    [self refreshThumbnail];
    [self refreshSubtitle];
    [self refreshForPhaseChange];
    [self refreshCancelButtonVisibility];
}

- (void)refreshTitle {
    if (!self.viewReady) return;
    self.titleLabel.text = self.titleText ?: @"";
}

- (void)refreshThumbnail {
    if (!self.viewReady) return;
    self.thumbnailView.image = self.thumbnailImage;
    self.thumbnailHeightConstraint.constant = (self.thumbnailImage == nil) ? 0.0 : 300.0;
    [self.view setNeedsLayout];
}

- (void)refreshSubtitle {
    if (!self.viewReady) return;
    NSString *text = self.subtitleText ?: @"";
    self.subtitleLabel.text = text;
}

- (void)refreshProgress {
    if (!self.viewReady) return;
    // Progress bar only animates for determinate download phases (and Muxing when fraction > 0).
    if (self.phase == YTAGDownloadPhaseDownloadingVideo ||
        self.phase == YTAGDownloadPhaseDownloadingAudio ||
        (self.phase == YTAGDownloadPhaseMuxing && self.progressFraction > 0.0)) {
        [self.progressView setProgress:(float)self.progressFraction animated:YES];
    }
    [self refreshPhaseLabelText];
}

- (void)refreshPhaseLabelText {
    if (!self.viewReady) return;
    NSInteger pct = (NSInteger)round(self.progressFraction * 100.0);
    switch (self.phase) {
        case YTAGDownloadPhaseDownloadingVideo:
            self.phaseLabel.text = [NSString stringWithFormat:@"Downloading video — %ld%%", (long)pct];
            self.phaseLabel.textColor = [UIColor labelColor];
            break;
        case YTAGDownloadPhaseDownloadingAudio:
            self.phaseLabel.text = [NSString stringWithFormat:@"Downloading audio — %ld%%", (long)pct];
            self.phaseLabel.textColor = [UIColor labelColor];
            break;
        case YTAGDownloadPhaseMuxing:
            if (self.progressFraction > 0.0) {
                self.phaseLabel.text = [NSString stringWithFormat:@"Processing — %ld%%", (long)pct];
            } else {
                self.phaseLabel.text = @"Processing…";
            }
            self.phaseLabel.textColor = [UIColor labelColor];
            break;
        case YTAGDownloadPhaseFinished:
            self.phaseLabel.text = @"Done";
            self.phaseLabel.textColor = [UIColor labelColor];
            break;
        case YTAGDownloadPhaseFinalizing:
            self.phaseLabel.text = @"Finalizing…";
            self.phaseLabel.textColor = [UIColor labelColor];
            break;
        case YTAGDownloadPhaseError:
            self.phaseLabel.text = @"Error";
            self.phaseLabel.textColor = [UIColor systemRedColor];
            break;
        case YTAGDownloadPhaseCancelled:
            self.phaseLabel.text = @"Cancelled";
            self.phaseLabel.textColor = [UIColor labelColor];
            break;
    }
}

- (void)refreshForPhaseChange {
    if (!self.viewReady) return;

    [self refreshPhaseLabelText];

    BOOL showProgressBar = NO;
    BOOL showSpinner = NO;
    BOOL showCheckmark = NO;

    switch (self.phase) {
        case YTAGDownloadPhaseDownloadingVideo:
        case YTAGDownloadPhaseDownloadingAudio:
            showProgressBar = YES;
            [self.progressView setProgress:(float)self.progressFraction animated:NO];
            break;
        case YTAGDownloadPhaseMuxing:
            if (self.progressFraction > 0.0) {
                showProgressBar = YES;
                [self.progressView setProgress:(float)self.progressFraction animated:NO];
            } else {
                showSpinner = YES;
            }
            break;
        case YTAGDownloadPhaseFinalizing:
            showSpinner = YES;
            break;
        case YTAGDownloadPhaseFinished:
            showCheckmark = YES;
            break;
        case YTAGDownloadPhaseError:
        case YTAGDownloadPhaseCancelled:
        default:
            break;
    }

    self.progressView.hidden = !showProgressBar;
    if (showSpinner) {
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
    }

    if (showCheckmark) {
        self.checkmarkView.hidden = NO;
        [UIView animateWithDuration:0.25 animations:^{
            self.checkmarkView.alpha = 1.0;
        }];
    } else {
        self.checkmarkView.alpha = 0.0;
        self.checkmarkView.hidden = YES;
    }

    // Cancel button behaviour per phase
    if (self.phase == YTAGDownloadPhaseError) {
        [self.cancelButton setTitle:@"Close" forState:UIControlStateNormal];
        self.cancelButton.enabled = YES;
        self.cancelButton.hidden = NO;
    } else if (self.phase == YTAGDownloadPhaseFinished ||
               self.phase == YTAGDownloadPhaseCancelled) {
        // Button irrelevant — hide it while we auto-dismiss.
        self.cancelButton.hidden = YES;
    } else if (self.phase == YTAGDownloadPhaseFinalizing) {
        self.cancelButton.hidden = YES;
    } else {
        // Active phase — respect onCancel presence.
        if (!self.cancelInFlight) {
            [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
            self.cancelButton.enabled = YES;
        }
        [self refreshCancelButtonVisibility];
    }

    [self updateInteractiveDismissal];

    // Terminal transitions fire onReadyToDismiss.
    if (self.phase == YTAGDownloadPhaseFinished) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf.onReadyToDismiss) strongSelf.onReadyToDismiss();
        });
    } else if (self.phase == YTAGDownloadPhaseCancelled) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf.onReadyToDismiss) strongSelf.onReadyToDismiss();
        });
    }
    // Error waits for the Close tap, handled in handleCancelTapped.
}

- (void)refreshCancelButtonVisibility {
    if (!self.viewReady) return;
    // Error phase always shows Close regardless of onCancel.
    if (self.phase == YTAGDownloadPhaseError) {
        self.cancelButton.hidden = NO;
        return;
    }
    if (self.phase == YTAGDownloadPhaseFinished ||
        self.phase == YTAGDownloadPhaseCancelled ||
        self.phase == YTAGDownloadPhaseFinalizing) {
        self.cancelButton.hidden = YES;
        return;
    }
    self.cancelButton.hidden = (self.onCancel == nil);
}

#pragma mark - Cancel

- (void)handleCancelTapped {
    if (self.phase == YTAGDownloadPhaseError) {
        // "Close" tap — fire dismiss. The onReadyToDismiss block captures weak
        // refs to the session; if failSession cleared the manager's activeSession
        // (releasing the session object) before the user tapped Close, those
        // weak refs nil out and the block early-returns without dismissing —
        // that's what left Corey stuck on the error screen 2026-04-24.
        // Self-dismiss ALWAYS works because `self` isn't weak-captured anywhere.
        YTAGLog(@"dl-ui", @"close tapped (error terminal)");
        if (self.onReadyToDismiss) self.onReadyToDismiss();
        if (self.presentingViewController != nil) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
        return;
    }

    if (self.cancelInFlight) return;
    self.cancelInFlight = YES;

    self.cancelButton.enabled = NO;
    [self.cancelButton setTitle:@"Cancelling…" forState:UIControlStateNormal];

    YTAGLog(@"dl-ui", @"cancel tapped");

    void (^cb)(void) = self.onCancel;
    if (cb) {
        dispatch_async(dispatch_get_main_queue(), cb);
    }
}

#pragma mark - Interactive dismissal

- (BOOL)isTerminalPhase {
    return self.phase == YTAGDownloadPhaseFinished ||
           self.phase == YTAGDownloadPhaseError ||
           self.phase == YTAGDownloadPhaseCancelled;
}

- (void)updateInteractiveDismissal {
    if (@available(iOS 13.0, *)) {
        self.modalInPresentation = ![self isTerminalPhase];
    }
}

- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController {
    return [self isTerminalPhase];
}

#pragma mark - Helpers

- (void)dispatchMain:(dispatch_block_t)block {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

@end
