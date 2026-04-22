#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAGDownloadPhase) {
    YTAGDownloadPhaseDownloadingVideo = 0,
    YTAGDownloadPhaseDownloadingAudio = 1,
    YTAGDownloadPhaseMuxing           = 2,
    YTAGDownloadPhaseFinished         = 3,
    YTAGDownloadPhaseError            = 4,
    YTAGDownloadPhaseCancelled        = 5,
};

/// Modal progress view shown during a download. Visually:
///   [artwork (thumbnail, 300pt tall)]
///   [title (2 lines, auto-shrink)]
///   [phase + percentage label]
///   [progress bar]
///   [Cancel button]
///
/// Caller is responsible for actually running the download/mux; this VC just displays state.
/// Caller updates state via the setters below; the VC animates changes.
@interface YTAGDownloadProgressViewController : UIViewController

/// Video title to show. Set before presenting.
@property (nonatomic, copy)   NSString *titleText;

/// Thumbnail image. Set before presenting. nil = no artwork shown (UI collapses).
@property (nonatomic, strong, nullable) UIImage *thumbnailImage;

/// Current phase. Update from the caller as the pipeline advances.
@property (nonatomic, assign) YTAGDownloadPhase phase;

/// Fractional progress for the current phase (0.0 - 1.0). Not cumulative across phases.
@property (nonatomic, assign) double progressFraction;

/// Optional status line shown below the phase label (e.g. "12.3 MB / 43.0 MB").
@property (nonatomic, copy, nullable) NSString *subtitleText;

/// Fires on main queue when the user taps Cancel. If nil, the Cancel button is hidden.
@property (nonatomic, copy, nullable) void (^onCancel)(void);

/// Fires after the VC finishes its own "Finished" or "Error" or "Cancelled" animation and is ready to dismiss.
/// Caller typically does `[vc dismissViewControllerAnimated:YES completion:nil]` inside.
@property (nonatomic, copy, nullable) void (^onReadyToDismiss)(void);

@end

NS_ASSUME_NONNULL_END
