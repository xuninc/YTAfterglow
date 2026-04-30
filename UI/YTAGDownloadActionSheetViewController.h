// YTAGDownloadActionSheetViewController.h
//
// The first-level menu shown when the player overlay's Download button is tapped.
// Offers six entries across two semantic groups (Save & Download / Share & Open).
// Each entry is a plain callback; wiring lives in YTAGDownload.x.
//
// Grouped sections, rounded material background, and inline size chips keep the
// sheet readable without feeling like a plain action list.

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

@interface YTAGDownloadPickerEntry : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, strong, nullable) id representedObject;

+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(nullable NSString *)subtitle
                    symbolName:(NSString *)symbolName
              representedObject:(nullable id)representedObject;

@end

@interface YTAGDownloadListPickerViewController : UIViewController

@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSArray<YTAGDownloadPickerEntry *> *entries;
@property (nonatomic, weak, nullable) UIView *sourceView;
@property (nonatomic, assign) NSInteger fontScaleMode; // 0 compact, 1 standard, 2 large
@property (nonatomic, assign) NSInteger fontFaceMode;  // 0 system, 1 rounded, 2 serif, 3 mono
@property (nonatomic, copy, nullable) void (^onSelectEntry)(YTAGDownloadPickerEntry *entry);

@end

NS_ASSUME_NONNULL_END
