#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class YTAGFormatPair;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAGPostDownloadAction) {
    YTAGPostDownloadActionAsk          = 0,  // present UIAlertController with Save to Photos / Share / Dismiss
    YTAGPostDownloadActionSaveToPhotos = 1,
    YTAGPostDownloadActionShare        = 2,  // UIActivityViewController
};

typedef void (^YTAGDownloadCompletion)(NSURL * _Nullable outputFileURL, NSError * _Nullable error);

@interface YTAGDownloadRequest : NSObject
@property (nonatomic, copy)   NSString *videoID;
@property (nonatomic, copy, nullable) NSString *titleOverride; // if nil, pulled from extraction result
@property (nonatomic, strong, nullable) YTAGFormatPair *pair;
@property (nonatomic, assign) YTAGPostDownloadAction postAction;
@end

@interface YTAGDownloadManager : NSObject

+ (instancetype)sharedManager;

/// Start a download. Presents YTAGDownloadProgressViewController modally from `presentingVC`.
/// Completion fires on main queue with the final mp4 URL (already handled per postAction) or error.
/// Returns an opaque token for cancellation.
- (id<NSObject>)startDownload:(YTAGDownloadRequest *)request
              presentingFrom:(UIViewController *)presentingVC
                   completion:(YTAGDownloadCompletion)completion;

/// Cancel an in-flight download by token. No-op if already finished.
- (void)cancelDownloadWithToken:(id<NSObject>)token;

@end

NS_ASSUME_NONNULL_END
