#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class YTAFFormatPair;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAFPostDownloadAction) {
    YTAFPostDownloadActionAsk          = 0,  // present UIAlertController with Save to Photos / Share / Dismiss
    YTAFPostDownloadActionSaveToPhotos = 1,
    YTAFPostDownloadActionShare        = 2,  // UIActivityViewController
};

typedef void (^YTAFDownloadCompletion)(NSURL * _Nullable outputFileURL, NSError * _Nullable error);

@interface YTAFDownloadRequest : NSObject
@property (nonatomic, copy)   NSString *videoID;
@property (nonatomic, copy, nullable) NSString *titleOverride; // if nil, pulled from extraction result
@property (nonatomic, strong, nullable) YTAFFormatPair *pair;
@property (nonatomic, assign) YTAFPostDownloadAction postAction;
@end

@interface YTAFDownloadManager : NSObject

+ (instancetype)sharedManager;

/// Start a download. Presents YTAFDownloadProgressViewController modally from `presentingVC`.
/// Completion fires on main queue with the final mp4 URL (already handled per postAction) or error.
/// Returns an opaque token for cancellation.
- (id<NSObject>)startDownload:(YTAFDownloadRequest *)request
              presentingFrom:(UIViewController *)presentingVC
                   completion:(YTAFDownloadCompletion)completion;

/// Cancel an in-flight download by token. No-op if already finished.
- (void)cancelDownloadWithToken:(id<NSObject>)token;

@end

NS_ASSUME_NONNULL_END
