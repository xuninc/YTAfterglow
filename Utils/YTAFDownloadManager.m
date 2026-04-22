#import "YTAFDownloadManager.h"

#import "YTAFURLExtractor.h"
#import "YTAFStreamDownloader.h"
#import "YTAFFormatSelector.h"
#import "FFMpegHelper.h"
#import "YTAGLog.h"
#import "../UI/YTAFDownloadProgressViewController.h"

#import <Photos/Photos.h>

static NSString *const kYTAFDownloadManagerErrorDomain = @"YTAFDownloadManager";

#pragma mark - YTAFDownloadRequest

@implementation YTAFDownloadRequest
@end

#pragma mark - Internal session state

typedef NS_ENUM(NSInteger, YTAFDLState) {
    YTAFDLStateIdle = 0,
    YTAFDLStateExtracting,
    YTAFDLStateDownloadingVideo,
    YTAFDLStateDownloadingAudio,
    YTAFDLStateMuxing,
    YTAFDLStateDelivering,
    YTAFDLStateFinished,
    YTAFDLStateError,
    YTAFDLStateCancelled,
};

@interface YTAFDLSession : NSObject
@property (nonatomic, strong) NSObject *token;
@property (nonatomic, strong) YTAFDownloadRequest *request;
@property (nonatomic, weak)   UIViewController *presentingVC;
@property (nonatomic, copy)   YTAFDownloadCompletion completion;

@property (nonatomic, strong) YTAFDownloadProgressViewController *progressVC;

@property (nonatomic, strong, nullable) YTAFExtractionResult *extractionResult;
@property (nonatomic, strong, nullable) YTAFFormatPair *pair;

@property (nonatomic, strong, nullable) YTAFStreamDownloader *videoDownloader;
@property (nonatomic, strong, nullable) YTAFStreamDownloader *audioDownloader;

@property (nonatomic, strong, nullable) NSURL *tmpDir;
@property (nonatomic, strong, nullable) NSURL *videoLocalURL;
@property (nonatomic, strong, nullable) NSURL *audioLocalURL;
@property (nonatomic, strong, nullable) NSURL *muxedOutputURL;   // output.mp4 before rename
@property (nonatomic, strong, nullable) NSURL *finalOutputURL;   // sanitized.mp4 after rename

@property (nonatomic, assign) BOOL videoDone;
@property (nonatomic, assign) BOOL audioDone;
@property (nonatomic, assign) double videoFraction;
@property (nonatomic, assign) double audioFraction;

@property (nonatomic, assign) YTAFDLState state;
@property (nonatomic, assign) BOOL completionFired;
@property (nonatomic, assign) BOOL cancelRequested;
@end

@implementation YTAFDLSession
@end

#pragma mark - YTAFDownloadManager

@interface YTAFDownloadManager ()
@property (nonatomic, strong) YTAFDLSession *activeSession; // MVP: one at a time
@end

@implementation YTAFDownloadManager

+ (instancetype)sharedManager {
    static YTAFDownloadManager *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[YTAFDownloadManager alloc] init];
    });
    return s_instance;
}

#pragma mark - Public

- (id<NSObject>)startDownload:(YTAFDownloadRequest *)request
              presentingFrom:(UIViewController *)presentingVC
                   completion:(YTAFDownloadCompletion)completion {
    NSParameterAssert(request != nil);
    NSParameterAssert(request.videoID.length > 0);
    NSParameterAssert(presentingVC != nil);

    // MVP: reject concurrent downloads.
    if (self.activeSession != nil) {
        NSError *err = [NSError errorWithDomain:kYTAFDownloadManagerErrorDomain
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Another download is in progress"}];
        YTAGLog(@"dl-mgr", @"[%@] rejected: another download in progress", request.videoID);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, err);
        });
        return [NSObject new];
    }

    YTAFDLSession *session = [[YTAFDLSession alloc] init];
    session.token = [NSObject new];
    session.request = request;
    session.presentingVC = presentingVC;
    session.completion = completion;
    session.state = YTAFDLStateIdle;
    self.activeSession = session;

    // Stage per-video temp directory: NSTemporaryDirectory()/<videoID>/
    NSURL *tmpRoot = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    session.tmpDir = [tmpRoot URLByAppendingPathComponent:request.videoID isDirectory:YES];
    NSError *mkdirErr = nil;
    [[NSFileManager defaultManager] removeItemAtURL:session.tmpDir error:NULL]; // start clean
    if (![[NSFileManager defaultManager] createDirectoryAtURL:session.tmpDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&mkdirErr]) {
        self.activeSession = nil;
        YTAGLog(@"dl-mgr", @"[%@] mkdir failed: %@", request.videoID, mkdirErr.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, mkdirErr);
        });
        return session.token;
    }

    NSString *vName = [NSString stringWithFormat:@"%@_v.mp4", request.videoID];
    NSString *aName = [NSString stringWithFormat:@"%@_a.m4a", request.videoID];
    session.videoLocalURL = [session.tmpDir URLByAppendingPathComponent:vName];
    session.audioLocalURL = [session.tmpDir URLByAppendingPathComponent:aName];
    session.muxedOutputURL = [session.tmpDir URLByAppendingPathComponent:@"output.mp4"];

    [self presentProgressForSession:session];

    // Decide whether extraction is needed.
    BOOL pairLooksValid = (request.pair != nil
                          && request.pair.videoFormat != nil
                          && request.pair.audioFormat != nil
                          && request.pair.videoFormat.url.length > 0
                          && request.pair.audioFormat.url.length > 0);
    if (pairLooksValid) {
        session.pair = request.pair;
        YTAGLog(@"dl-mgr", @"[%@] skip extract, pair provided", request.videoID);
        [self beginDownloadsForSession:session];
    } else {
        [self extractForSession:session];
    }

    return session.token;
}

- (void)cancelDownloadWithToken:(id<NSObject>)token {
    YTAFDLSession *session = self.activeSession;
    if (!session || session.token != token) return;
    [self userRequestedCancelForSession:session];
}

#pragma mark - UI presentation

- (void)presentProgressForSession:(YTAFDLSession *)session {
    YTAFDownloadProgressViewController *vc = [[YTAFDownloadProgressViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    vc.titleText = session.request.titleOverride.length > 0 ? session.request.titleOverride : @"Downloading…";
    vc.thumbnailImage = nil;
    vc.phase = YTAFDownloadPhaseDownloadingVideo;
    vc.progressFraction = 0.0;

    __weak typeof(self) weakSelf = self;
    __weak YTAFDLSession *weakSession = session;
    vc.onCancel = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAFDLSession *s = weakSession;
        if (!strongSelf || !s) return;
        [strongSelf userRequestedCancelForSession:s];
    };
    vc.onReadyToDismiss = ^{
        YTAFDLSession *s = weakSession;
        if (!s) return;
        UIViewController *pvc = s.progressVC.presentingViewController ?: s.presentingVC;
        [pvc dismissViewControllerAnimated:YES completion:nil];
    };

    session.progressVC = vc;
    [session.presentingVC presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Extraction

- (void)extractForSession:(YTAFDLSession *)session {
    session.state = YTAFDLStateExtracting;
    YTAGLog(@"dl-mgr", @"[%@] state → extracting", session.request.videoID);

    __weak typeof(self) weakSelf = self;
    [YTAFURLExtractor extractVideoID:session.request.videoID
                            clientID:YTAFClientIDiOS
                          completion:^(YTAFExtractionResult * _Nullable result, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (session.cancelRequested) return;

        if (error || !result) {
            YTAGLog(@"dl-mgr", @"[%@] extract failed: %@", session.request.videoID, error.localizedDescription);
            [strongSelf failSession:session withError:error ?: [NSError errorWithDomain:kYTAFDownloadManagerErrorDomain
                                                                                    code:-2
                                                                                userInfo:@{NSLocalizedDescriptionKey: @"Extraction failed"}]];
            return;
        }

        session.extractionResult = result;

        // Update title from result if caller didn't override.
        if (session.request.titleOverride.length == 0 && result.title.length > 0) {
            session.progressVC.titleText = result.title;
        }

        // Fetch thumbnail on a background task.
        if (result.thumbnailURL.length > 0) {
            NSURL *thumbURL = [NSURL URLWithString:result.thumbnailURL];
            if (thumbURL) {
                NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:thumbURL
                                                                          completionHandler:^(NSData * _Nullable data,
                                                                                              NSURLResponse * _Nullable response,
                                                                                              NSError * _Nullable tErr) {
                    if (!data || tErr) return;
                    UIImage *img = [UIImage imageWithData:data];
                    if (!img) return;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (session.cancelRequested) return;
                        session.progressVC.thumbnailImage = img;
                    });
                }];
                [task resume];
            }
        }

        // Pick a pair if the caller didn't supply one.
        YTAFFormatPair *pair = session.request.pair;
        if (!pair || !pair.videoFormat || !pair.audioFormat) {
            pair = [YTAFFormatSelector selectVideoPairFromResult:result
                                                         quality:YTAFQualityPreferenceHighest
                                                           codec:YTAFCodecPreferenceH264
                                                    audioQuality:YTAFAudioQualityStandard];
        }
        if (!pair || !pair.videoFormat || !pair.audioFormat) {
            NSError *err = [NSError errorWithDomain:kYTAFDownloadManagerErrorDomain
                                               code:-3
                                           userInfo:@{NSLocalizedDescriptionKey: @"No suitable video + audio formats found"}];
            YTAGLog(@"dl-mgr", @"[%@] no pair", session.request.videoID);
            [strongSelf failSession:session withError:err];
            return;
        }
        session.pair = pair;
        YTAGLog(@"dl-mgr", @"[%@] extract → video-dl (%@)", session.request.videoID, pair.descriptorString);
        [strongSelf beginDownloadsForSession:session];
    }];
}

#pragma mark - Downloads

- (void)beginDownloadsForSession:(YTAFDLSession *)session {
    if (session.cancelRequested) return;

    YTAFFormatPair *pair = session.pair;
    NSURL *vRemote = [NSURL URLWithString:pair.videoFormat.url];
    NSURL *aRemote = [NSURL URLWithString:pair.audioFormat.url];
    if (!vRemote || !aRemote) {
        NSError *err = [NSError errorWithDomain:kYTAFDownloadManagerErrorDomain
                                           code:-4
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid stream URLs"}];
        [self failSession:session withError:err];
        return;
    }

    session.state = YTAFDLStateDownloadingVideo;
    session.progressVC.phase = YTAFDownloadPhaseDownloadingVideo;
    session.progressVC.progressFraction = 0.0;
    session.progressVC.subtitleText = nil;

    session.videoDownloader = [[YTAFStreamDownloader alloc] initWithURL:vRemote];
    session.videoDownloader.destinationURL = session.videoLocalURL;

    session.audioDownloader = [[YTAFStreamDownloader alloc] initWithURL:aRemote];
    session.audioDownloader.destinationURL = session.audioLocalURL;

    __weak typeof(self) weakSelf = self;

    // Video progress: only drive the UI while video is still the "current" stream.
    YTAFStreamProgress videoProgress = ^(int64_t bytesWritten, int64_t totalBytesExpected, double fraction) {
        YTAFDLSession *s = session;
        if (!s || s.cancelRequested || s.completionFired) return;
        s.videoFraction = fraction;
        if (s.state == YTAFDLStateDownloadingVideo) {
            s.progressVC.progressFraction = fraction;
        }
    };

    YTAFStreamCompletion videoCompletion = ^(NSURL * _Nullable localFileURL, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        YTAFDLSession *s = session;
        if (!s || s.cancelRequested || s.completionFired) return;
        if (error) {
            YTAGLog(@"dl-mgr", @"[%@] video download failed: %@", s.request.videoID, error.localizedDescription);
            [strongSelf failSession:s withError:error];
            return;
        }
        s.videoFraction = 1.0;
        s.videoDone = YES;
        if (localFileURL && ![localFileURL isEqual:s.videoLocalURL]) {
            // The downloader may have written to its suggested path if destinationURL wasn't honored.
            s.videoLocalURL = localFileURL;
        }
        YTAGLog(@"dl-mgr", @"[%@] video-dl done", s.request.videoID);
        [strongSelf maybeSwitchToAudioPhaseForSession:s];
    };

    YTAFStreamProgress audioProgress = ^(int64_t bytesWritten, int64_t totalBytesExpected, double fraction) {
        YTAFDLSession *s = session;
        if (!s || s.cancelRequested || s.completionFired) return;
        s.audioFraction = fraction;
        if (s.state == YTAFDLStateDownloadingAudio) {
            s.progressVC.progressFraction = fraction;
        }
    };

    YTAFStreamCompletion audioCompletion = ^(NSURL * _Nullable localFileURL, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        YTAFDLSession *s = session;
        if (!s || s.cancelRequested || s.completionFired) return;
        if (error) {
            YTAGLog(@"dl-mgr", @"[%@] audio download failed: %@", s.request.videoID, error.localizedDescription);
            [strongSelf failSession:s withError:error];
            return;
        }
        s.audioFraction = 1.0;
        s.audioDone = YES;
        if (localFileURL && ![localFileURL isEqual:s.audioLocalURL]) {
            s.audioLocalURL = localFileURL;
        }
        YTAGLog(@"dl-mgr", @"[%@] audio-dl done", s.request.videoID);
        // If we're already in audio phase (video finished first), advance to mux.
        if (s.state == YTAFDLStateDownloadingAudio) {
            [strongSelf beginMuxForSession:s];
        }
        // If video hasn't finished yet, we'll pick this up in maybeSwitchToAudioPhase.
    };

    [session.videoDownloader startWithProgress:videoProgress completion:videoCompletion];
    [session.audioDownloader startWithProgress:audioProgress completion:audioCompletion];
}

- (void)maybeSwitchToAudioPhaseForSession:(YTAFDLSession *)session {
    if (session.cancelRequested || session.completionFired) return;
    session.state = YTAFDLStateDownloadingAudio;
    session.progressVC.phase = YTAFDownloadPhaseDownloadingAudio;

    if (session.audioDone) {
        // Audio finished during or before video finished. Show 100% and mux immediately.
        session.progressVC.progressFraction = 1.0;
        YTAGLog(@"dl-mgr", @"[%@] audio already done at video-dl end, → mux", session.request.videoID);
        [self beginMuxForSession:session];
    } else {
        // Resume audio progress driving the UI from wherever it is.
        session.progressVC.progressFraction = session.audioFraction;
        YTAGLog(@"dl-mgr", @"[%@] video-dl → audio-dl", session.request.videoID);
    }
}

#pragma mark - Mux

- (void)beginMuxForSession:(YTAFDLSession *)session {
    if (session.cancelRequested || session.completionFired) return;
    session.state = YTAFDLStateMuxing;
    session.progressVC.phase = YTAFDownloadPhaseMuxing;
    session.progressVC.progressFraction = 0.0;
    session.progressVC.subtitleText = nil;

    NSTimeInterval durationSeconds = session.extractionResult.duration;
    if (durationSeconds <= 0 && session.pair.videoFormat) {
        durationSeconds = session.pair.videoFormat.duration;
    }

    YTAGLog(@"dl-mgr", @"[%@] state → muxing (dur=%.1fs)", session.request.videoID, durationSeconds);

    __weak typeof(self) weakSelf = self;
    [[FFMpegHelper sharedManager] muxVideo:session.videoLocalURL
                                     audio:session.audioLocalURL
                                  captions:nil
                                  duration:(NSInteger)durationSeconds
                                completion:^(NSURL * _Nullable outputURL, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        YTAFDLSession *s = session;
        if (!s || s.completionFired) return;
        // If user cancelled but mux still completed, honor the cancel path.
        if (s.cancelRequested) {
            [strongSelf finalizeCancelForSession:s];
            return;
        }
        if (error || !outputURL) {
            YTAGLog(@"dl-mgr", @"[%@] mux failed: %@", s.request.videoID, error.localizedDescription);
            [strongSelf failSession:s withError:error ?: [NSError errorWithDomain:kYTAFDownloadManagerErrorDomain
                                                                              code:-5
                                                                          userInfo:@{NSLocalizedDescriptionKey: @"Mux failed"}]];
            return;
        }
        s.muxedOutputURL = outputURL;
        YTAGLog(@"dl-mgr", @"[%@] mux done → %@", s.request.videoID, outputURL.lastPathComponent);
        [strongSelf renameAndDeliverForSession:s];
    }];
}

#pragma mark - Rename + deliver

- (NSString *)sanitizedFilenameFromTitle:(NSString *)title fallback:(NSString *)fallback {
    NSString *base = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (base.length == 0) base = fallback;
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/:\\*?\"<>|"];
    NSMutableString *out = [NSMutableString stringWithCapacity:base.length];
    for (NSUInteger i = 0; i < base.length; i++) {
        unichar c = [base characterAtIndex:i];
        if ([bad characterIsMember:c]) {
            [out appendString:@"_"];
        } else {
            [out appendFormat:@"%C", c];
        }
    }
    NSString *trimmed = [out stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) trimmed = fallback;
    return trimmed;
}

- (void)renameAndDeliverForSession:(YTAFDLSession *)session {
    session.state = YTAFDLStateDelivering;

    NSString *title = session.request.titleOverride.length > 0
        ? session.request.titleOverride
        : (session.extractionResult.title ?: session.request.videoID);
    NSString *sanitized = [self sanitizedFilenameFromTitle:title fallback:session.request.videoID];

    // We only ship video+audio muxed mp4 in MVP (audio-only path is out of scope for this orchestrator).
    NSString *finalName = [sanitized stringByAppendingPathExtension:@"mp4"];
    NSURL *finalURL = [session.tmpDir URLByAppendingPathComponent:finalName];

    // If something with that name already exists, remove it.
    [[NSFileManager defaultManager] removeItemAtURL:finalURL error:NULL];

    NSError *mvErr = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:session.muxedOutputURL toURL:finalURL error:&mvErr]) {
        // Fall back to serving the un-renamed file rather than failing.
        YTAGLog(@"dl-mgr", @"[%@] rename failed (%@), serving output.mp4", session.request.videoID, mvErr.localizedDescription);
        finalURL = session.muxedOutputURL;
    }
    session.finalOutputURL = finalURL;

    // Clean up the intermediate stream files now; keep final + tmpDir until user acts.
    [self removeURLIfExists:session.videoLocalURL];
    [self removeURLIfExists:session.audioLocalURL];

    // Flip the progress VC to Finished before dismissing.
    session.progressVC.phase = YTAFDownloadPhaseFinished;
    session.progressVC.progressFraction = 1.0;

    YTAGLog(@"dl-mgr", @"[%@] delivering (post=%ld) → %@", session.request.videoID, (long)session.request.postAction, finalURL.lastPathComponent);

    switch (session.request.postAction) {
        case YTAFPostDownloadActionSaveToPhotos:
            [self saveToPhotosForSession:session presentPromptAfter:NO];
            break;
        case YTAFPostDownloadActionShare:
            [self shareForSession:session];
            break;
        case YTAFPostDownloadActionAsk:
        default:
            [self askPostActionForSession:session];
            break;
    }
}

- (void)askPostActionForSession:(YTAFDLSession *)session {
    __weak typeof(self) weakSelf = self;
    __weak YTAFDLSession *weakSession = session;
    [self dismissProgressForSession:session then:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAFDLSession *s = weakSession;
        if (!strongSelf || !s) return;

        UIViewController *host = s.presentingVC;
        if (!host) {
            // Host went away; just call completion and finish.
            [strongSelf finalizeSuccessForSession:s];
            return;
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                        message:nil
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save to Photos"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [strongSelf saveToPhotosForSession:s presentPromptAfter:NO];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Share"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [strongSelf shareForSession:s];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss"
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction * _Nonnull action) {
            [strongSelf finalizeSuccessForSession:s];
        }]];

        // iPad popover anchor.
        UIPopoverPresentationController *pop = alert.popoverPresentationController;
        if (pop) {
            pop.sourceView = host.view;
            pop.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds),
                                        CGRectGetMidY(host.view.bounds),
                                        0, 0);
            pop.permittedArrowDirections = 0;
        }

        [host presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)saveToPhotosForSession:(YTAFDLSession *)session presentPromptAfter:(BOOL)unusedFlag {
    NSURL *fileURL = session.finalOutputURL;
    __weak typeof(self) weakSelf = self;
    __weak YTAFDLSession *weakSession = session;

    void (^doSave)(void) = ^{
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
        } completionHandler:^(BOOL success, NSError * _Nullable err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                YTAFDLSession *s = weakSession;
                if (!strongSelf || !s) return;
                if (!success) {
                    YTAGLog(@"dl-mgr", @"[%@] save-to-photos failed: %@", s.request.videoID, err.localizedDescription);
                    [strongSelf failSession:s withError:err ?: [NSError errorWithDomain:kYTAFDownloadManagerErrorDomain
                                                                                    code:-6
                                                                                userInfo:@{NSLocalizedDescriptionKey: @"Save to Photos failed"}]];
                    return;
                }
                YTAGLog(@"dl-mgr", @"[%@] saved to photos", s.request.videoID);
                // If we came from Ask, the progressVC is already dismissed. For the direct
                // SaveToPhotos path it may still be up.
                if (s.progressVC.presentingViewController != nil) {
                    [strongSelf dismissProgressForSession:s then:^{
                        [strongSelf finalizeSuccessForSession:s];
                    }];
                } else {
                    [strongSelf finalizeSuccessForSession:s];
                }
            });
        }];
    };

    if ([PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly] == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                                   handler:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                doSave();
            });
        }];
    } else {
        doSave();
    }
}

- (void)shareForSession:(YTAFDLSession *)session {
    NSURL *fileURL = session.finalOutputURL;
    __weak typeof(self) weakSelf = self;
    __weak YTAFDLSession *weakSession = session;

    void (^presentShare)(UIViewController *) = ^(UIViewController *host) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAFDLSession *s = weakSession;
        if (!strongSelf || !s || !host) return;

        UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                         applicationActivities:nil];
        av.completionWithItemsHandler = ^(UIActivityType  _Nullable activityType, BOOL completed, NSArray * _Nullable returnedItems, NSError * _Nullable err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) innerSelf = weakSelf;
                YTAFDLSession *innerSession = weakSession;
                if (!innerSelf || !innerSession) return;
                [innerSelf finalizeSuccessForSession:innerSession];
            });
        };

        UIPopoverPresentationController *pop = av.popoverPresentationController;
        if (pop) {
            pop.sourceView = host.view;
            pop.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds),
                                        CGRectGetMidY(host.view.bounds),
                                        0, 0);
            pop.permittedArrowDirections = 0;
        }
        [host presentViewController:av animated:YES completion:nil];
    };

    // If the progressVC is still up, dismiss first so the share sheet has a clean host.
    if (session.progressVC.presentingViewController != nil) {
        [self dismissProgressForSession:session then:^{
            YTAFDLSession *s = weakSession;
            if (!s) return;
            presentShare(s.presentingVC);
        }];
    } else {
        presentShare(session.presentingVC);
    }
}

#pragma mark - Terminal states

- (void)finalizeSuccessForSession:(YTAFDLSession *)session {
    if (session.completionFired) return;
    session.completionFired = YES;
    session.state = YTAFDLStateFinished;
    NSURL *out = session.finalOutputURL;
    YTAFDownloadCompletion cb = session.completion;

    // After delivery, clean up the tmp dir entirely. The user's file either lives in the
    // Photos library (copied) or was shared/exported (UIActivityViewController typically
    // copies before dismissing).
    [self cleanupTempFilesForSession:session];

    if (self.activeSession == session) self.activeSession = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (cb) cb(out, nil);
    });
}

- (void)failSession:(YTAFDLSession *)session withError:(NSError *)error {
    if (session.completionFired) return;
    session.completionFired = YES;
    session.state = YTAFDLStateError;

    YTAGLog(@"dl-mgr", @"[%@] state → error: %@", session.request.videoID, error.localizedDescription);

    // Cancel any still-running downloaders.
    [session.videoDownloader cancel];
    [session.audioDownloader cancel];

    session.progressVC.phase = YTAFDownloadPhaseError;
    session.progressVC.subtitleText = error.localizedDescription;

    __weak typeof(self) weakSelf = self;
    __weak YTAFDLSession *weakSession = session;
    session.progressVC.onCancel = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAFDLSession *s = weakSession;
        if (!strongSelf || !s) return;
        [strongSelf dismissProgressForSession:s then:nil];
    };

    [self cleanupTempFilesForSession:session];

    YTAFDownloadCompletion cb = session.completion;
    if (self.activeSession == session) self.activeSession = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (cb) cb(nil, error);
    });
}

- (void)userRequestedCancelForSession:(YTAFDLSession *)session {
    if (session.cancelRequested || session.completionFired) return;
    session.cancelRequested = YES;
    YTAGLog(@"dl-mgr", @"[%@] cancel requested (state=%ld)", session.request.videoID, (long)session.state);

    // 1. Cancel downloaders (no-op if already done).
    [session.videoDownloader cancel];
    [session.audioDownloader cancel];

    // 2. Mux cancellation: FFMpegHelper doesn't expose a cancel entry point; if mux is in
    //    flight we let it run (it's <1s for copy-mux), then finalize cancel in its completion.
    if (session.state == YTAFDLStateMuxing) {
        YTAGLog(@"dl-mgr", @"[%@] cancel while muxing — waiting for ffmpeg to finish", session.request.videoID);
        return; // finalizeCancelForSession runs from the mux completion.
    }

    [self finalizeCancelForSession:session];
}

- (void)finalizeCancelForSession:(YTAFDLSession *)session {
    if (session.completionFired) return;
    session.completionFired = YES;
    session.state = YTAFDLStateCancelled;

    session.progressVC.phase = YTAFDownloadPhaseCancelled;

    NSError *err = [NSError errorWithDomain:kYTAFDownloadManagerErrorDomain
                                       code:-999
                                   userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}];

    [self cleanupTempFilesForSession:session];

    YTAFDownloadCompletion cb = session.completion;
    if (self.activeSession == session) self.activeSession = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (cb) cb(nil, err);
    });
}

#pragma mark - Helpers

- (void)dismissProgressForSession:(YTAFDLSession *)session then:(void (^ _Nullable)(void))then {
    UIViewController *pvc = session.progressVC.presentingViewController;
    if (!pvc) {
        if (then) then();
        return;
    }
    [pvc dismissViewControllerAnimated:YES completion:^{
        if (then) then();
    }];
}

- (void)removeURLIfExists:(nullable NSURL *)url {
    if (!url) return;
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

- (void)cleanupTempFilesForSession:(YTAFDLSession *)session {
    [self removeURLIfExists:session.videoLocalURL];
    [self removeURLIfExists:session.audioLocalURL];
    [self removeURLIfExists:session.muxedOutputURL];
    // Intentionally leave finalOutputURL + tmpDir until a later idle point; the share
    // sheet / Photos import need the file on disk briefly. The OS reaps NSTemporaryDirectory
    // on app restart regardless.
}

@end
