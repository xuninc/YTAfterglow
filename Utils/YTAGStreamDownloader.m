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
        // Googlevideo.com signs stream URLs against (IP, UA, session-context).
        // The v33 test showed NSURLSession's default UA inside YouTube.app doesn't
        // match what the iOS-client InnerTube request used to mint the URLs, so
        // the CDN returned text/plain errors that we saved as .mp4. Set the iOS
        // YouTube UA explicitly so the signature binding sees a consistent client.
        // Format matches the real iOS YouTube client's network requests and lines
        // up with our InnerTube spoof (clientName=IOS, clientVersion=21.16.2).
        cfg.HTTPAdditionalHeaders = @{
            @"User-Agent": @"com.google.ios.youtube/21.16.2 (iPhone17,3; U; CPU iOS 18_5 like Mac OS X)",
            @"X-YouTube-Client-Name": @"5",
            @"X-YouTube-Client-Version": @"21.16.2",
        };
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

    // `didFinishDownloadingToURL:` fires on ANY HTTP completion — success or error.
    // NSURLSession happily writes a 403 body to disk and calls this method. Without
    // an explicit status check, we'd hand a tiny error-body file downstream (the
    // v33 symptom: mux saw 200-byte "files" and returned rc=1 instantly). Validate
    // the status before claiming success.
    NSHTTPURLResponse *http = nil;
    if ([downloadTask.response isKindOfClass:[NSHTTPURLResponse class]]) {
        http = (NSHTTPURLResponse *)downloadTask.response;
    }
    NSInteger status = http.statusCode;

    // Measure the response body we just wrote. Useful for diagnosing tiny
    // error responses even when the status code alone doesn't scream "error".
    unsigned long long bodyBytes = 0;
    NSError *attrErr = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:location.path error:&attrErr];
    if (attrs) bodyBytes = [attrs fileSize];

    YTAGLog(@"downloader", @"response: status=%ld bytes=%llu ctype=%@",
            (long)status, bodyBytes,
            [http.allHeaderFields objectForKey:@"Content-Type"] ?: @"<none>");

    if (http && (status < 200 || status >= 300)) {
        // Read a preview of the error body so the user can see what the server said.
        NSData *preview = [NSData dataWithContentsOfURL:location options:NSDataReadingMappedIfSafe error:NULL];
        NSString *bodyStr = nil;
        if (preview.length > 0) {
            NSData *slice = preview.length > 512 ? [preview subdataWithRange:NSMakeRange(0, 512)] : preview;
            bodyStr = [[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding];
        }
        YTAGLog(@"downloader", @"HTTP error body preview: %@", bodyStr ?: @"<binary/empty>");

        NSError *err = [NSError errorWithDomain:kYTAGStreamDownloaderErrorDomain
                                            code:status
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"HTTP %ld from stream server", (long)status]}];
        [self fireCompletionWithURL:nil error:err];
        return;
    }

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

    YTAGLog(@"downloader", @"finished -> %@ (%llu bytes)", destination.path, bodyBytes);
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
