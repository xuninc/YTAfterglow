#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^YTAFStreamProgress)(int64_t bytesWritten, int64_t totalBytesExpected, double fraction);
typedef void (^YTAFStreamCompletion)(NSURL * _Nullable localFileURL, NSError * _Nullable error);

/// Downloads a single URL (typically a googlevideo.com videoplayback URL) to a temp file.
/// Progress and completion both fire on the main queue.
/// Cancel via -cancel. Completion with error domain "YTAFStreamDownloader" code -999 on cancel.
@interface YTAFStreamDownloader : NSObject

/// Optional: destination file URL. If nil, writes to NSTemporaryDirectory() with an auto-generated name.
@property (nonatomic, strong, nullable) NSURL *destinationURL;

/// Total bytes expected once headers arrive (populated during download).
@property (nonatomic, readonly) int64_t expectedContentLength;

/// Is the download still running?
@property (nonatomic, readonly) BOOL isDownloading;

/// Initialize with a remote URL.
- (instancetype)initWithURL:(NSURL *)remoteURL;

/// Start the download. Callbacks fire on main queue.
- (void)startWithProgress:(nullable YTAFStreamProgress)progress
               completion:(YTAFStreamCompletion)completion;

/// Cancel the running download (completes with cancel error).
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
