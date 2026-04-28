// YTAGDownloadActionSheetViewController.h
//
// The first-level menu shown when the player overlay's Download button is tapped.
// Offers six entries across two semantic groups (Save & Download / Share & Open).
// Each entry is a plain callback; wiring lives in YTAGDownload.x.
//
// Visually differentiated from YTLite's flat sheet by grouped sections, rounded
// material background, and inline size chips for the "download" actions.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAGDownloadAction) {
    YTAGDownloadActionDownloadVideo = 0,
    YTAGDownloadActionDownloadAudio,
    YTAGDownloadActionDownloadCaptions,
    YTAGDownloadActionSaveImage,
    YTAGDownloadActionCopyInformation,
    YTAGDownloadActionPlayInExternalPlayer,
};

@interface YTAGDownloadActionSheetViewController : UIViewController

/// Channel / author name (top header).
@property (nonatomic, copy, nullable) NSString *channelName;
/// Video title (subhead).
@property (nonatomic, copy, nullable) NSString *videoTitle;

/// Optional inline size chip for the "Download audio" row. nil hides the chip.
/// Caller computes this from the already-extracted audio format's contentLength.
@property (nonatomic, copy, nullable) NSString *audioSizeChip;   // e.g. "2.4 MB"

@property (nonatomic, assign) BOOL videoAvailable;
@property (nonatomic, assign) BOOL audioAvailable;
@property (nonatomic, assign) BOOL captionsAvailable;
@property (nonatomic, assign) BOOL thumbnailAvailable;
@property (nonatomic, assign) BOOL externalPlaybackAvailable;

/// Tapped-row callback. Fires on main queue after the sheet dismisses.
/// The sheet dismisses itself before invoking; the caller doesn't need to dismiss manually.
@property (nonatomic, copy, nullable) void (^onAction)(YTAGDownloadAction action);

@end

NS_ASSUME_NONNULL_END
