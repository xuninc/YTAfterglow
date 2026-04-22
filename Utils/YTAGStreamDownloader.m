#import "YTAGStreamDownloader.h"
#import "YTAGLog.h"

static NSString *const kYTAGStreamDownloaderErrorDomain = @"YTAGStreamDownloader";

@interface YTAGStreamDownloader () <NSURLSessionDownloadDelegate>

@property (nonatomic, strong) NSURL *remoteURL;
@property (nonatomic, strong, nullable) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDownloadTask *currentTask;

@property (nonatomic, copy, nullable) YTAGStreamProgress progressBlock;
@property (nonatomic, copy, nullable) YTAGStreamCompletion completionBlock;

@property (nonatomic, assign) int64_t expectedContentLength;
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, assign) BOOL didFireCompletion;
@property (nonatomic, assign) double lastReportedFraction;

@property (nonatomic, strong) dispatch_queue_t stateQueue;

@end

@implementation YTAGStreamDownloader

- (instancetype)initWithURL:(NSURL *)remoteURL {
    if ((self = [super init])) {
        _remoteURL = remoteURL;
        _expectedContentLength = 0;
        _isDownloading = NO;
        _didFireCompletion = NO;
        _lastReportedFraction = -1.0;
        _stateQueue = dispatch_queue_create("com.ytafterglow.streamdownloader.state", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    // Belt-and-suspenders: make sure we don't leak a session that still retains us.
    [_session invalidateAndCancel];
}

#pragma mark - Public

- (void)startWithProgress:(nullable YTAGStreamProgress)progress
               completion:(YTAGStreamCompletion)completion {
    if (!self.remoteURL) {
        NSError *err = [NSError errorWithDomain:kYTAGStreamDownloaderErrorDomain
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: @"No remote URL"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, err);
        });
        return;
    }

    __block BOOL hadPrevious = NO;
    dispatch_sync(self.stateQueue, ^{
        if (self.isDownloading) {
            hadPrevious = YES;
        }
    });

    if (hadPrevious) {
        YTAGLog(@"downloader", @"start called while already downloading; cancelling previous task");
        [self cancel];
    }

    dispatch_sync(self.stateQueue, ^{
        self.progressBlock = progress;
        self.completionBlock = completion;
        self.didFireCompletion = NO;
        self.lastReportedFraction = -1.0;
        self.expectedContentLength = 0;
        self.isDownloading = YES;

        // Default destination: NSTemporaryDirectory() + UUID.tmp
        if (!self.destinationURL) {
            NSString *name = [NSString stringWithFormat:@"%@.tmp", [[NSUUID UUID] UUIDString]];
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
            self.destinationURL = [NSURL fileURLWithPath:path];
        }

        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.HTTPMaximumConnectionsPerHost = 4;
        cfg.timeoutIntervalForRequest = 60;
        self.session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];

        self.currentTask = [self.session downloadTaskWithURL:self.remoteURL];
    });

    YTAGLog(@"downloader", @"start %@ -> %@", self.remoteURL.absoluteString, self.destinationURL.path);
    [self.currentTask resume];
}

- (void)cancel {
    __block NSURLSessionDownloadTask *task = nil;
    dispatch_sync(self.stateQueue, ^{
        task = self.currentTask;
    });
    if (task) {
        YTAGLog(@"downloader", @"cancel requested");
        [task cancel];
    }
}

#pragma mark - Helpers

- (void)fireCompletionWithURL:(nullable NSURL *)url error:(nullable NSError *)error {
    __block YTAGStreamCompletion block = nil;
    dispatch_sync(self.stateQueue, ^{
        if (self.didFireCompletion) {
            return;
        }
        self.didFireCompletion = YES;
        self.isDownloading = NO;
        block = self.completionBlock;
        self.completionBlock = nil;
        self.progressBlock = nil;
        self.currentTask = nil;
    });

    // Tear down the session so it releases its strong reference to us (delegate retain).
    NSURLSession *sessionToInvalidate = self.session;
    self.session = nil;
    [sessionToInvalidate finishTasksAndInvalidate];

    if (!block) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        block(url, error);
    });
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {

    __block YTAGStreamProgress block = nil;
    __block BOOL shouldFire = NO;

    double fraction = 0.0;
    if (totalBytesExpectedToWrite > 0) {
        fraction = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
    }

    dispatch_sync(self.stateQueue, ^{
        self.expectedContentLength = totalBytesExpectedToWrite;
        // Throttle: fire on >=1% change, or exactly at completion (fraction >= 1.0).
        BOOL atEnd = (totalBytesExpectedToWrite > 0) && (totalBytesWritten >= totalBytesExpectedToWrite);
        if (atEnd || self.lastReportedFraction < 0.0 || (fraction - self.lastReportedFraction) >= 0.01) {
            self.lastReportedFraction = fraction;
            shouldFire = YES;
            block = self.progressBlock;
        }
    });

    if (shouldFire && block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(totalBytesWritten, totalBytesExpectedToWrite, fraction);
        });
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {

    NSURL *destination = self.destinationURL;
    NSError *moveError = nil;

    NSFileManager *fm = [NSFileManager defaultManager];

    // Ensure parent directory exists.
    NSURL *parent = [destination URLByDeletingLastPathComponent];
    if (parent) {
        [fm createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    // Remove any existing file at destination.
    if ([fm fileExistsAtPath:destination.path]) {
        [fm removeItemAtURL:destination error:NULL];
    }

    if (![fm moveItemAtURL:location toURL:destination error:&moveError]) {
        YTAGLog(@"downloader", @"move failed: %@", moveError.localizedDescription ?: @"(unknown)");
        [self fireCompletionWithURL:nil error:moveError];
        return;
    }

    YTAGLog(@"downloader", @"finished -> %@", destination.path);
    [self fireCompletionWithURL:destination error:nil];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {

    if (!error) {
        // Successful path already handled by didFinishDownloadingToURL.
        return;
    }

    // Already fired (e.g., completed successfully, then a stray didComplete arrives)? Ignore.
    __block BOOL alreadyDone = NO;
    dispatch_sync(self.stateQueue, ^{
        alreadyDone = self.didFireCompletion;
    });
    if (alreadyDone) return;

    NSError *reportError = error;
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        reportError = [NSError errorWithDomain:kYTAGStreamDownloaderErrorDomain
                                          code:-999
                                      userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}];
        YTAGLog(@"downloader", @"cancelled");
    } else {
        YTAGLog(@"downloader", @"error: %@", error.localizedDescription ?: @"(unknown)");
    }

    [self fireCompletionWithURL:nil error:reportError];
}

@end
