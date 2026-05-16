#import "YTAGDownloadManager.h"

#import "YTAGURLExtractor.h"
#import "YTAGStreamDownloader.h"
#import "YTAGFormatSelector.h"
#import "FFMpegHelper.h"
#import "YTAGLog.h"
#import "../UI/YTAGDownloadProgressViewController.h"

#import <Photos/Photos.h>

static NSString *const kYTAGDownloadManagerErrorDomain = @"YTAGDownloadManager";

static UIViewController *YTAGDownloadTopPresenter(UIViewController *preferred) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow) break;
    }

    UIViewController *top = keyWindow.rootViewController ?: preferred;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    return top ?: preferred;
}

static BOOL YTAGDownloadSameFileURL(NSURL *a, NSURL *b) {
    if (!a || !b) return NO;
    return [a.path isEqualToString:b.path];
}

#pragma mark - YTAGDownloadRequest

@implementation YTAGDownloadRequest
@end

#pragma mark - Internal session state

typedef NS_ENUM(NSInteger, YTAGDLState) {
    YTAGDLStateIdle = 0,
    YTAGDLStateExtracting,
    YTAGDLStateDownloadingVideo,
    YTAGDLStateDownloadingAudio,
    YTAGDLStateMuxing,
    YTAGDLStateTranscodingHEVC,
    YTAGDLStateDelivering,
    YTAGDLStateFinished,
    YTAGDLStateError,
    YTAGDLStateCancelled,
};

@interface YTAGDLSession : NSObject
@property (nonatomic, strong) NSObject *token;
@property (nonatomic, strong) YTAGDownloadRequest *request;
@property (nonatomic, weak)   UIViewController *presentingVC;
@property (nonatomic, copy)   YTAGDownloadCompletion completion;

@property (nonatomic, strong) YTAGDownloadProgressViewController *progressVC;

@property (nonatomic, strong, nullable) YTAGExtractionResult *extractionResult;
@property (nonatomic, strong, nullable) YTAGFormatPair *pair;

@property (nonatomic, strong, nullable) YTAGStreamDownloader *videoDownloader;
@property (nonatomic, strong, nullable) YTAGStreamDownloader *audioDownloader;

@property (nonatomic, strong, nullable) NSURL *tmpDir;
@property (nonatomic, strong, nullable) NSURL *videoLocalURL;
@property (nonatomic, strong, nullable) NSURL *audioLocalURL;
@property (nonatomic, strong, nullable) NSURL *muxedOutputURL;   // output.mp4 before rename
@property (nonatomic, strong, nullable) NSURL *finalOutputURL;   // sanitized.mp4 after rename

@property (nonatomic, assign) BOOL videoDone;
@property (nonatomic, assign) BOOL audioDone;
@property (nonatomic, assign) double videoFraction;
@property (nonatomic, assign) double audioFraction;

@property (nonatomic, assign) YTAGDLState state;
@property (nonatomic, assign) BOOL completionFired;
@property (nonatomic, assign) BOOL cancelRequested;
@property (nonatomic, assign) BOOL shareCompletionHandled;
@end

@implementation YTAGDLSession
@end

#pragma mark - YTAGDownloadManager

@interface YTAGDownloadManager ()
@property (nonatomic, strong) YTAGDLSession *activeSession; // MVP: one at a time
- (BOOL)needsHEVCTranscodeForSession:(YTAGDLSession *)session;
- (void)beginHEVCTranscodeForSession:(YTAGDLSession *)session;
- (void)presentPhotosSaveFailureForSession:(YTAGDLSession *)session error:(NSError *)error;
- (void)finalizeShareDeliveryForSession:(YTAGDLSession *)session reason:(NSString *)reason;
- (void)watchShareDismissalForSession:(YTAGDLSession *)session
               activityViewController:(UIActivityViewController *)activityViewController
                              attempt:(NSUInteger)attempt;
@end

@implementation YTAGDownloadManager

+ (instancetype)sharedManager {
    static YTAGDownloadManager *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[YTAGDownloadManager alloc] init];
    });
    return s_instance;
}

#pragma mark - Public

- (id<NSObject>)startDownload:(YTAGDownloadRequest *)request
              presentingFrom:(UIViewController *)presentingVC
                   completion:(YTAGDownloadCompletion)completion {
    YTAGLog(@"dl-mgr", @"[bc] startDownload: ENTER vid=%@ presenter=%@ pairProvided=%d",
            request.videoID ?: @"<nil>",
            NSStringFromClass([presentingVC class]) ?: @"<nil>",
            (request.pair != nil));
    if (!request || request.videoID.length == 0 || !presentingVC) {
        NSError *err = [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
                                           code:-100
                                       userInfo:@{NSLocalizedDescriptionKey: @"Download could not start because the current video or presenter was unavailable."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, err);
        });
        return [NSObject new];
    }

    // MVP: reject concurrent downloads.
    if (self.activeSession != nil) {
        YTAGDLSession *active = self.activeSession;
        NSError *err = [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Another download is in progress"}];
        YTAGLog(@"dl-mgr", @"[%@] rejected: another download in progress (active=%@ state=%ld completionFired=%d shareCompletionHandled=%d final=%@)",
                request.videoID,
                active.request.videoID ?: @"<nil>",
                (long)active.state,
                active.completionFired,
                active.shareCompletionHandled,
                active.finalOutputURL.lastPathComponent ?: @"<nil>");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, err);
        });
        return [NSObject new];
    }

    YTAGDLSession *session = [[YTAGDLSession alloc] init];
    session.token = [NSObject new];
    session.request = request;
    session.presentingVC = presentingVC;
    session.completion = completion;
    session.state = YTAGDLStateIdle;
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

    // Decide whether extraction is needed. Audio-only pairs (videoFormat nil,
    // audioFormat set) ARE valid — the Audio tile in the action sheet supplies
    // that shape. Without this branch we fell through to the extractor with no
    // reason to, and YT returned a playability error ("YouTube is no longer
    // supported in this application or device") that we showed as a fatal
    // Close-alert Corey couldn't dismiss (v35 regression).
    BOOL hasAudio = (request.pair.audioFormat.url.length > 0);
    BOOL hasVideo = (request.pair.videoFormat.url.length > 0);
    BOOL pairLooksValid = (request.pair != nil && (hasVideo || hasAudio));
    if (pairLooksValid) {
        session.pair = request.pair;
        YTAGLog(@"dl-mgr", @"[%@] skip extract, pair provided (video=%d audio=%d)",
                request.videoID, hasVideo, hasAudio);
        [self beginDownloadsForSession:session];
    } else {
        [self extractForSession:session];
    }

    return session.token;
}

- (void)cancelDownloadWithToken:(id<NSObject>)token {
    YTAGDLSession *session = self.activeSession;
    if (!session || session.token != token) return;
    [self userRequestedCancelForSession:session];
}

#pragma mark - UI presentation

- (void)presentProgressForSession:(YTAGDLSession *)session {
    YTAGLog(@"dl-mgr", @"[bc] presentProgressForSession: ENTER vid=%@", session.request.videoID);
    YTAGDownloadProgressViewController *vc = [[YTAGDownloadProgressViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    vc.titleText = session.request.titleOverride.length > 0 ? session.request.titleOverride : @"Downloading…";
    vc.thumbnailImage = nil;
    vc.phase = YTAGDownloadPhaseDownloadingVideo;
    vc.progressFraction = 0.0;

    __weak typeof(self) weakSelf = self;
    __weak YTAGDLSession *weakSession = session;
    vc.onCancel = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAGDLSession *s = weakSession;
        if (!strongSelf || !s) return;
        [strongSelf userRequestedCancelForSession:s];
    };
    vc.onReadyToDismiss = ^{
        YTAGDLSession *s = weakSession;
        if (!s) return;
        YTAGDownloadProgressViewController *progressVC = s.progressVC;
        // Dismiss through whichever ancestor is still alive. If the player chrome
        // tore down the presentingViewController (as observed in v35 when YT's
        // overlay was dismissed while the error VC was up), fall back to calling
        // dismiss on the progressVC itself — UIKit routes it up the chain.
        UIViewController *pvc = progressVC.presentingViewController ?: s.presentingVC;
        if (pvc) {
            [pvc dismissViewControllerAnimated:YES completion:nil];
        } else if (progressVC) {
            [progressVC dismissViewControllerAnimated:YES completion:nil];
        }
    };

    session.progressVC = vc;
    UIViewController *host = YTAGDownloadTopPresenter(session.presentingVC);
    session.presentingVC = host ?: session.presentingVC;
    YTAGLog(@"dl-mgr", @"[bc] presentProgressForSession: presenting progressVC on %@",
            NSStringFromClass([session.presentingVC class]));
    [session.presentingVC presentViewController:vc animated:YES completion:^{
        YTAGLog(@"dl-mgr", @"[bc] progressVC present completion fired");
    }];
}

#pragma mark - Extraction

- (void)extractForSession:(YTAGDLSession *)session {
    session.state = YTAGDLStateExtracting;
    YTAGLog(@"dl-mgr", @"[%@] state → extracting", session.request.videoID);

    __weak typeof(self) weakSelf = self;
    [YTAGURLExtractor extractVideoID:session.request.videoID
                            clientID:YTAGClientIDTVEmbed
                          completion:^(YTAGExtractionResult * _Nullable result, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (session.cancelRequested) return;

        if (error || !result) {
            YTAGLog(@"dl-mgr", @"[%@] extract failed: %@", session.request.videoID, error.localizedDescription);
            [strongSelf failSession:session withError:error ?: [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
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
        YTAGFormatPair *pair = session.request.pair;
        if (!pair || !pair.videoFormat || !pair.audioFormat) {
            pair = [YTAGFormatSelector selectVideoPairFromResult:result
                                                         quality:YTAGQualityPreferenceHighest
                                                           codec:YTAGCodecPreferenceH264
                                                    audioQuality:YTAGAudioQualityStandard];
        }
        if (!pair || !pair.videoFormat || !pair.audioFormat) {
            NSError *err = [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
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

- (void)beginDownloadsForSession:(YTAGDLSession *)session {
    YTAGLog(@"dl-mgr", @"[bc] beginDownloads: ENTER vid=%@", session.request.videoID);
    if (session.cancelRequested) {
        YTAGLog(@"dl-mgr", @"[bc] beginDownloads: cancelRequested — ABORT");
        return;
    }

    YTAGFormatPair *pair = session.pair;
    NSURL *vRemote = pair.videoFormat.url.length > 0 ? [NSURL URLWithString:pair.videoFormat.url] : nil;
    NSURL *aRemote = pair.audioFormat.url.length > 0 ? [NSURL URLWithString:pair.audioFormat.url] : nil;
    BOOL audioOnly = (vRemote == nil && aRemote != nil);
    YTAGLog(@"dl-mgr", @"[bc] beginDownloads: vRemote=%@ aRemote=%@ audioOnly=%d",
            vRemote ? @"ok" : @"<nil>", aRemote ? @"ok" : @"<nil>", audioOnly);
    // Must have a usable stream shape. Video-only is not enough for an MP4 download
    // because the result would be silent; keep that failure explicit and early.
    if (!aRemote && !vRemote) {
        NSError *err = [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
                                           code:-4
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid stream URLs"}];
        [self failSession:session withError:err];
        return;
    }
    if (vRemote && !aRemote) {
        NSError *err = [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
                                           code:-41
                                       userInfo:@{NSLocalizedDescriptionKey: @"No downloadable audio track was available for this video."}];
        [self failSession:session withError:err];
        return;
    }

    // Audio-only: download just the m4a, skip mux, deliver the raw file.
    // YT's adaptive audio is already a valid m4a container; no transcode needed.
    if (audioOnly) {
        session.state = YTAGDLStateDownloadingAudio;
        session.progressVC.phase = YTAGDownloadPhaseDownloadingAudio;
        session.progressVC.progressFraction = 0.0;
        session.progressVC.subtitleText = nil;

        session.audioDownloader = [[YTAGStreamDownloader alloc] initWithURL:aRemote];
        session.audioDownloader.destinationURL = session.audioLocalURL;

        __weak typeof(self) weakSelfAudio = self;
        __block BOOL audioOnlyFirstProgress = YES;
        YTAGStreamProgress audioOnlyProgress = ^(int64_t bytesWritten, int64_t totalBytesExpected, double fraction) {
            YTAGDLSession *s = session;
            if (!s || s.cancelRequested || s.completionFired) return;
            if (audioOnlyFirstProgress) {
                YTAGLog(@"dl-mgr", @"[bc] audio-only FIRST progress: %lld/%lld (%.1f%%)",
                        bytesWritten, totalBytesExpected, fraction * 100.0);
                audioOnlyFirstProgress = NO;
            }
            s.audioFraction = fraction;
            s.progressVC.progressFraction = fraction;
        };
        YTAGStreamCompletion audioOnlyCompletion = ^(NSURL * _Nullable localFileURL, NSError * _Nullable error) {
            __strong typeof(weakSelfAudio) strongSelfAudio = weakSelfAudio;
            if (!strongSelfAudio) return;
            YTAGDLSession *s = session;
            if (!s || s.cancelRequested || s.completionFired) return;
            if (error) {
                YTAGLog(@"dl-mgr", @"[%@] audio-only download failed: %@", s.request.videoID, error.localizedDescription);
                [strongSelfAudio failSession:s withError:error];
                return;
            }
            if (localFileURL && ![localFileURL isEqual:s.audioLocalURL]) {
                s.audioLocalURL = localFileURL;
            }
            YTAGLog(@"dl-mgr", @"[%@] audio-only download done — skipping mux, using raw m4a", s.request.videoID);
            // Treat the downloaded m4a as the final output. renameAndDeliver will
            // copy/move it to a friendly filename under tmpDir and hand it to the
            // post-action (SaveToPhotos for v35+ default).
            s.muxedOutputURL = s.audioLocalURL;
            [strongSelfAudio renameAndDeliverForSession:s];
        };
        YTAGLog(@"dl-mgr", @"[bc] beginDownloads: starting audio-only NSURLSession task");
        [session.audioDownloader startWithProgress:audioOnlyProgress completion:audioOnlyCompletion];
        YTAGLog(@"dl-mgr", @"[bc] beginDownloads: audio task resumed");
        return;
    }

    // Video + audio path (the normal case).
    session.state = YTAGDLStateDownloadingVideo;
    session.progressVC.phase = YTAGDownloadPhaseDownloadingVideo;
    session.progressVC.progressFraction = 0.0;
    session.progressVC.subtitleText = nil;

    session.videoDownloader = [[YTAGStreamDownloader alloc] initWithURL:vRemote];
    session.videoDownloader.destinationURL = session.videoLocalURL;

    session.audioDownloader = [[YTAGStreamDownloader alloc] initWithURL:aRemote];
    session.audioDownloader.destinationURL = session.audioLocalURL;

    __weak typeof(self) weakSelf = self;

    // Video progress: only drive the UI while video is still the "current" stream.
    __block BOOL videoFirstProgress = YES;
    YTAGStreamProgress videoProgress = ^(int64_t bytesWritten, int64_t totalBytesExpected, double fraction) {
        YTAGDLSession *s = session;
        if (!s || s.cancelRequested || s.completionFired) return;
        if (videoFirstProgress) {
            YTAGLog(@"dl-mgr", @"[bc] video-dl FIRST progress: %lld/%lld (%.1f%%)",
                    bytesWritten, totalBytesExpected, fraction * 100.0);
            videoFirstProgress = NO;
        }
        s.videoFraction = fraction;
        if (s.state == YTAGDLStateDownloadingVideo) {
            s.progressVC.progressFraction = fraction;
        }
    };

    YTAGStreamCompletion videoCompletion = ^(NSURL * _Nullable localFileURL, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        YTAGDLSession *s = session;
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

    __block BOOL audioFirstProgress = YES;
    YTAGStreamProgress audioProgress = ^(int64_t bytesWritten, int64_t totalBytesExpected, double fraction) {
        YTAGDLSession *s = session;
        if (!s || s.cancelRequested || s.completionFired) return;
        if (audioFirstProgress) {
            YTAGLog(@"dl-mgr", @"[bc] audio-dl FIRST progress: %lld/%lld (%.1f%%)",
                    bytesWritten, totalBytesExpected, fraction * 100.0);
            audioFirstProgress = NO;
        }
        s.audioFraction = fraction;
        if (s.state == YTAGDLStateDownloadingAudio) {
            s.progressVC.progressFraction = fraction;
        }
    };

    YTAGStreamCompletion audioCompletion = ^(NSURL * _Nullable localFileURL, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        YTAGDLSession *s = session;
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
        if (s.state == YTAGDLStateDownloadingAudio) {
            [strongSelf beginMuxForSession:s];
        }
        // If video hasn't finished yet, we'll pick this up in maybeSwitchToAudioPhase.
    };

    YTAGLog(@"dl-mgr", @"[bc] beginDownloads: starting video + audio NSURLSession tasks");
    [session.videoDownloader startWithProgress:videoProgress completion:videoCompletion];
    [session.audioDownloader startWithProgress:audioProgress completion:audioCompletion];
    YTAGLog(@"dl-mgr", @"[bc] beginDownloads: both tasks resumed");
}

- (void)maybeSwitchToAudioPhaseForSession:(YTAGDLSession *)session {
    if (session.cancelRequested || session.completionFired) return;
    session.state = YTAGDLStateDownloadingAudio;
    session.progressVC.phase = YTAGDownloadPhaseDownloadingAudio;

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

- (void)beginMuxForSession:(YTAGDLSession *)session {
    if (session.cancelRequested || session.completionFired) return;
    session.state = YTAGDLStateMuxing;
    session.progressVC.phase = YTAGDownloadPhaseMuxing;
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
        YTAGDLSession *s = session;
        if (!s || s.completionFired) return;
        // If user cancelled but mux still completed, honor the cancel path.
        if (s.cancelRequested) {
            [strongSelf finalizeCancelForSession:s];
            return;
        }
        if (error || !outputURL) {
            YTAGLog(@"dl-mgr", @"[%@] mux failed: %@", s.request.videoID, error.localizedDescription);
            [strongSelf failSession:s withError:error ?: [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
                                                                              code:-5
                                                                          userInfo:@{NSLocalizedDescriptionKey: @"Mux failed"}]];
            return;
        }
        s.muxedOutputURL = outputURL;
        YTAGLog(@"dl-mgr", @"[%@] mux done → %@", s.request.videoID, outputURL.lastPathComponent);
        if ([strongSelf needsHEVCTranscodeForSession:s]) {
            [strongSelf beginHEVCTranscodeForSession:s];
        } else {
            [strongSelf renameAndDeliverForSession:s];
        }
    }];
}

#pragma mark - HEVC conversion

- (BOOL)needsHEVCTranscodeForSession:(YTAGDLSession *)session {
    if (!session || !session.muxedOutputURL || session.completionFired || session.cancelRequested) return NO;

    YTAGFormat *video = session.pair.videoFormat;
    if (!video) return NO; // audio-only is already handled by the delivery path.

    NSString *codec = video.codec.lowercaseString ?: @"";
    NSString *container = video.container.lowercaseString ?: @"";
    NSString *mimeType = video.mimeType.lowercaseString ?: @"";

    if ([codec hasPrefix:@"avc1."] || [codec hasPrefix:@"hvc1"] || [codec hasPrefix:@"hev1"]) {
        return NO;
    }

    BOOL isVP9 = [codec isEqualToString:@"vp9"] || [codec hasPrefix:@"vp09."];
    BOOL isAV1 = [codec hasPrefix:@"av01."];
    BOOL isWebM = [container isEqualToString:@"webm"] || [mimeType containsString:@"video/webm"];
    BOOL shouldTranscode = isVP9 || isAV1 || isWebM;

    if (shouldTranscode) {
        YTAGLog(@"dl-mgr", @"[%@] HEVC needed for iOS delivery (codec=%@ container=%@ mime=%@)",
                session.request.videoID,
                codec.length > 0 ? codec : @"<nil>",
                container.length > 0 ? container : @"<nil>",
                mimeType.length > 0 ? mimeType : @"<nil>");
    }
    return shouldTranscode;
}

- (void)beginHEVCTranscodeForSession:(YTAGDLSession *)session {
    if (session.cancelRequested || session.completionFired) return;

    NSURL *sourceURL = session.muxedOutputURL;
    if (!sourceURL) {
        [self failSession:session withError:[NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
                                                                code:-8
                                                            userInfo:@{NSLocalizedDescriptionKey: @"HEVC conversion could not start because the muxed video was missing."}]];
        return;
    }

    session.state = YTAGDLStateTranscodingHEVC;
    session.progressVC.phase = YTAGDownloadPhaseMuxing;
    session.progressVC.progressFraction = 0.0;
    session.progressVC.subtitleText = @"Converting to HEVC…";

    YTAGFormat *video = session.pair.videoFormat;
    NSTimeInterval durationSeconds = session.extractionResult.duration;
    if (durationSeconds <= 0 && video.duration > 0) {
        durationSeconds = video.duration;
    }

    NSInteger videoBitrate = video.bitrate;
    if (videoBitrate <= 0 && video.contentLength > 0 && durationSeconds > 0) {
        videoBitrate = (NSInteger)((double)video.contentLength * 8.0 / durationSeconds);
    }

    NSURL *hevcURL = [session.tmpDir URLByAppendingPathComponent:@"output_hevc.mp4"];
    YTAGLog(@"dl-mgr", @"[%@] state → hevc (codec=%@ container=%@ mime=%@ bitrate=%ld)",
            session.request.videoID,
            video.codec ?: @"<nil>",
            video.container ?: @"<nil>",
            video.mimeType ?: @"<nil>",
            (long)videoBitrate);

    __weak typeof(self) weakSelf = self;
    [[FFMpegHelper sharedManager] transcodeVideoToHEVCForPhotos:sourceURL
                                                      outputURL:hevcURL
                                                       duration:(NSInteger)durationSeconds
                                                   videoBitrate:videoBitrate
                                                     completion:^(NSURL * _Nullable outputURL, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        YTAGDLSession *s = session;
        if (!s || s.completionFired) return;
        if (s.cancelRequested) {
            [strongSelf finalizeCancelForSession:s];
            return;
        }
        if (error || !outputURL) {
            YTAGLog(@"dl-mgr", @"[%@] HEVC transcode failed: %@", s.request.videoID, error.localizedDescription);
            [strongSelf failSession:s withError:error ?: [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
                                                                              code:-9
                                                                          userInfo:@{NSLocalizedDescriptionKey: @"HEVC conversion failed."}]];
            return;
        }

        s.muxedOutputURL = outputURL;
        if (!YTAGDownloadSameFileURL(sourceURL, outputURL)) {
            [strongSelf removeURLIfExists:sourceURL];
        }
        YTAGLog(@"dl-mgr", @"[%@] HEVC transcode done → %@", s.request.videoID, outputURL.lastPathComponent);
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

- (void)renameAndDeliverForSession:(YTAGDLSession *)session {
    session.state = YTAGDLStateDelivering;

    NSString *title = session.request.titleOverride.length > 0
        ? session.request.titleOverride
        : (session.extractionResult.title ?: session.request.videoID);
    NSString *sanitized = [self sanitizedFilenameFromTitle:title fallback:session.request.videoID];

    // Audio-only outputs an .m4a (Photos can't ingest audio-only files, so the
    // post-action also gets overridden below to Share). Video+audio mux outputs .mp4.
    BOOL isAudioOnly = (session.pair.videoFormat == nil && session.pair.audioFormat != nil);
    NSString *ext = isAudioOnly ? @"m4a" : @"mp4";
    NSString *finalName = [sanitized stringByAppendingPathExtension:ext];
    NSURL *finalURL = [session.tmpDir URLByAppendingPathComponent:finalName];

    // If something with that name already exists, remove it.
    [[NSFileManager defaultManager] removeItemAtURL:finalURL error:NULL];

    NSError *mvErr = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:session.muxedOutputURL toURL:finalURL error:&mvErr]) {
        // Fall back to serving the un-renamed file rather than failing.
        YTAGLog(@"dl-mgr", @"[%@] rename failed (%@), serving source file", session.request.videoID, mvErr.localizedDescription);
        finalURL = session.muxedOutputURL;
    }
    session.finalOutputURL = finalURL;

    // For audio-only, Photos can't import .m4a — force a Share sheet so the user
    // can send to Files / Voice Memos / AirDrop / etc.
    if (isAudioOnly && session.request.postAction == YTAGPostDownloadActionSaveToPhotos) {
        YTAGLog(@"dl-mgr", @"[%@] audio-only detected → overriding SaveToPhotos → Share", session.request.videoID);
        session.request.postAction = YTAGPostDownloadActionShare;
    }

    // Clean up the intermediate stream files now; keep final + tmpDir until user acts.
    // Skip cleanup of audioLocalURL if it IS the final (audio-only path moved it).
    if (!isAudioOnly) {
        [self removeURLIfExists:session.videoLocalURL];
        [self removeURLIfExists:session.audioLocalURL];
    } else {
        [self removeURLIfExists:session.videoLocalURL];
    }

    session.progressVC.progressFraction = 1.0;
    session.progressVC.phase = YTAGDownloadPhaseFinalizing;
    session.progressVC.subtitleText = @"Preparing file…";

    YTAGLog(@"dl-mgr", @"[%@] delivering (post=%ld) → %@", session.request.videoID, (long)session.request.postAction, finalURL.lastPathComponent);

    switch (session.request.postAction) {
        case YTAGPostDownloadActionSaveToPhotos:
            [self saveToPhotosForSession:session presentPromptAfter:NO];
            break;
        case YTAGPostDownloadActionShare:
            [self shareForSession:session];
            break;
        case YTAGPostDownloadActionAsk:
        default:
            [self askPostActionForSession:session];
            break;
    }
}

- (void)askPostActionForSession:(YTAGDLSession *)session {
    __weak typeof(self) weakSelf = self;
    __weak YTAGDLSession *weakSession = session;
    [self dismissProgressForSession:session then:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAGDLSession *s = weakSession;
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

- (void)saveToPhotosForSession:(YTAGDLSession *)session presentPromptAfter:(BOOL)unusedFlag {
    NSURL *fileURL = session.finalOutputURL;
    __weak typeof(self) weakSelf = self;
    __weak YTAGDLSession *weakSession = session;
    session.progressVC.phase = YTAGDownloadPhaseFinalizing;
    session.progressVC.subtitleText = @"Saving to Photos…";

    void (^doSave)(void) = ^{
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            // Create an empty asset, then attach the video file as a resource.
            // This bypasses the upfront codec compatibility check from
            // creationRequestForAssetFromVideoAtFileURL:, which can reject VP9/AV1
            // files even when Photos can store them as raw video resources.
            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
            [req addResourceWithType:PHAssetResourceTypeVideo
                             fileURL:fileURL
                             options:nil];
        } completionHandler:^(BOOL success, NSError * _Nullable err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                YTAGDLSession *s = weakSession;
                if (!strongSelf || !s) return;
                if (!success) {
                    YTAGLog(@"dl-mgr", @"[%@] save-to-photos failed: %@ — falling back to Share sheet",
                            s.request.videoID, err.localizedDescription);
                    // Common failure mode: Photos refuses non-H.264 video (VP9 in
                    // MP4 container gives PHPhotosErrorDomain error 3302). The
                    // file itself is on disk and valid, but users need to be told
                    // Photos rejected the format before we offer a Share fallback.
                    if (s.progressVC.presentingViewController != nil) {
                        [strongSelf dismissProgressForSession:s then:^{
                            [strongSelf presentPhotosSaveFailureForSession:s error:err];
                        }];
                    } else {
                        [strongSelf presentPhotosSaveFailureForSession:s error:err];
                    }
                    return;
                }
                YTAGLog(@"dl-mgr", @"[%@] saved to photos", s.request.videoID);
                // NOW flip to Finished — user can briefly see the checkmark.
                // Explicit dismiss follows immediately so the 0.75s auto-dismiss
                // timer (which still arms on phase=Finished) is racing against
                // our synchronous dismissal. Either wins — the progressVC goes
                // away and finalize fires via the dismiss completion.
                s.progressVC.phase = YTAGDownloadPhaseFinished;
                s.progressVC.progressFraction = 1.0;
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

    void (^fallbackToShare)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAGDLSession *s = weakSession;
        if (!strongSelf || !s) return;
        YTAGLog(@"dl-mgr", @"[%@] Photos access unavailable — falling back to Share sheet", s.request.videoID);
        [strongSelf shareForSession:s];
    };

    BOOL (^canSaveWithStatus)(PHAuthorizationStatus) = ^BOOL(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) return YES;
        if (@available(iOS 14, *)) {
            if (status == PHAuthorizationStatusLimited) return YES;
        }
        return NO;
    };

    if (@available(iOS 14, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                                       handler:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (canSaveWithStatus(status)) doSave();
                    else fallbackToShare();
                });
            }];
        } else if (canSaveWithStatus(status)) {
            doSave();
        } else {
            fallbackToShare();
        }
    } else {
        // iOS 13 fallback: older unscoped authorization request.
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (canSaveWithStatus(status)) doSave();
                    else fallbackToShare();
                });
            }];
        } else if (canSaveWithStatus(status)) {
            doSave();
        } else {
            fallbackToShare();
        }
    }
}

- (void)presentPhotosSaveFailureForSession:(YTAGDLSession *)session error:(NSError *)error {
    if (!session || session.completionFired || session.cancelRequested) return;

    UIViewController *host = YTAGDownloadTopPresenter(session.presentingVC);
    if (!host || !host.view) {
        YTAGLog(@"dl-mgr", @"[%@] Photos rejection alert had no host — opening Share sheet",
                session.request.videoID);
        [self shareForSession:session];
        return;
    }

    NSString *detail = error.localizedDescription.length > 0
        ? [NSString stringWithFormat:@"\n\nPhotos error: %@", error.localizedDescription]
        : @"";
    NSString *message = [NSString stringWithFormat:
        @"Photos couldn't save this video. If this was a VP9/AV1 source, Afterglow already tried converting it to HEVC. You can still share/export the file elsewhere.%@",
        detail];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save to Photos failed"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    __weak YTAGDLSession *weakSession = session;
    [alert addAction:[UIAlertAction actionWithTitle:@"Share File"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAGDLSession *s = weakSession;
        if (!strongSelf || !s) return;
        [strongSelf shareForSession:s];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss"
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAGDLSession *s = weakSession;
        if (!strongSelf || !s) return;
        [strongSelf finalizeSuccessForSession:s];
    }]];

    UIPopoverPresentationController *pop = alert.popoverPresentationController;
    if (pop) {
        pop.sourceView = host.view;
        pop.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds),
                                    CGRectGetMidY(host.view.bounds),
                                    0, 0);
        pop.permittedArrowDirections = 0;
    }

    YTAGLog(@"dl-mgr", @"[%@] presenting Photos save failure alert", session.request.videoID);
    [host presentViewController:alert animated:YES completion:nil];
}

- (void)shareForSession:(YTAGDLSession *)session {
    NSURL *fileURL = session.finalOutputURL;
    __weak typeof(self) weakSelf = self;
    __weak YTAGDLSession *weakSession = session;
    session.progressVC.phase = YTAGDownloadPhaseFinalizing;
    session.progressVC.subtitleText = @"Preparing share sheet…";

    YTAGLog(@"dl-mgr", @"[bc] shareForSession: ENTER file=%@", fileURL.lastPathComponent);

    void (^presentShare)(UIViewController *) = ^(UIViewController *host) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAGDLSession *s = weakSession;
        if (!strongSelf || !s) {
            YTAGLog(@"dl-mgr", @"[bc] shareForSession: strongSelf/session nil — ABORT");
            return;
        }
        if (!host) {
            YTAGLog(@"dl-mgr", @"[bc] shareForSession: host nil — finalizing anyway so session unlocks");
            [strongSelf finalizeSuccessForSession:s];
            return;
        }

        s.shareCompletionHandled = NO;
        UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                         applicationActivities:nil];
        av.completionWithItemsHandler = ^(UIActivityType  _Nullable activityType, BOOL completed, NSArray * _Nullable returnedItems, NSError * _Nullable err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) innerSelf = weakSelf;
                YTAGDLSession *innerSession = weakSession;
                if (!innerSelf || !innerSession) return;
                YTAGLog(@"dl-mgr", @"[bc] share completion: activity=%@ completed=%d error=%@",
                        activityType, completed, err.localizedDescription ?: @"<nil>");
                [innerSelf finalizeShareDeliveryForSession:innerSession reason:@"share completion"];
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
        YTAGLog(@"dl-mgr", @"[bc] shareForSession: presenting on %@", NSStringFromClass([host class]));
        [host presentViewController:av animated:YES completion:^{
            YTAGLog(@"dl-mgr", @"[bc] shareForSession: present completion fired");
        }];
        [strongSelf watchShareDismissalForSession:s activityViewController:av attempt:0];
    };

    // Find a stable host. session.presentingVC may be tied to player chrome and
    // can disappear mid-flow, so prefer the foreground key-window presenter.
    UIViewController *(^findStableHost)(void) = ^UIViewController *{
        return YTAGDownloadTopPresenter(session.presentingVC);
    };

    // If the progressVC is still up, dismiss first so the share sheet has a clean host.
    if (session.progressVC.presentingViewController != nil) {
        [self dismissProgressForSession:session then:^{
            YTAGDLSession *s = weakSession;
            if (!s) return;
            presentShare(findStableHost());
        }];
    } else {
        presentShare(findStableHost());
    }
}

- (void)finalizeShareDeliveryForSession:(YTAGDLSession *)session reason:(NSString *)reason {
    if (!session || session.completionFired || session.shareCompletionHandled) return;
    session.shareCompletionHandled = YES;
    YTAGLog(@"dl-mgr", @"[%@] share delivery finished: %@", session.request.videoID, reason ?: @"<nil>");
    [self finalizeSuccessForSession:session];
}

- (void)watchShareDismissalForSession:(YTAGDLSession *)session
               activityViewController:(UIActivityViewController *)activityViewController
                              attempt:(NSUInteger)attempt {
    if (!session || session.completionFired || session.shareCompletionHandled) return;

    __weak typeof(self) weakSelf = self;
    __weak YTAGDLSession *weakSession = session;
    __weak UIActivityViewController *weakActivityVC = activityViewController;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAGDLSession *s = weakSession;
        UIActivityViewController *av = weakActivityVC;
        if (!strongSelf || !s || s.completionFired || s.shareCompletionHandled) return;

        BOOL dismissed = (av == nil ||
                          (av.presentingViewController == nil &&
                           av.view.window == nil &&
                           !av.isBeingPresented));
        if (dismissed) {
            YTAGLog(@"dl-mgr", @"[%@] share dismissal observed without completion (attempt=%lu)",
                    s.request.videoID, (unsigned long)attempt);
            [strongSelf finalizeShareDeliveryForSession:s reason:@"share dismissal observed without completion"];
            return;
        }

        [strongSelf watchShareDismissalForSession:s
                          activityViewController:av
                                         attempt:attempt + 1];
    });
}

#pragma mark - Terminal states

- (void)finalizeSuccessForSession:(YTAGDLSession *)session {
    if (session.completionFired) return;
    session.completionFired = YES;
    session.state = YTAGDLStateFinished;
    NSURL *out = session.finalOutputURL;
    YTAGDownloadCompletion cb = session.completion;

    // After delivery, clean up the tmp dir entirely. The user's file either lives in the
    // Photos library (copied) or was shared/exported (UIActivityViewController typically
    // copies before dismissing).
    [self cleanupTempFilesForSession:session];

    if (self.activeSession == session) self.activeSession = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (cb) cb(out, nil);
    });
}

- (void)failSession:(YTAGDLSession *)session withError:(NSError *)error {
    if (session.completionFired) return;
    session.completionFired = YES;
    session.state = YTAGDLStateError;

    YTAGLog(@"dl-mgr", @"[%@] state → error: %@", session.request.videoID, error.localizedDescription);

    // Cancel any still-running downloaders.
    [session.videoDownloader cancel];
    [session.audioDownloader cancel];

    session.progressVC.phase = YTAGDownloadPhaseError;
    session.progressVC.subtitleText = error.localizedDescription;

    __weak typeof(self) weakSelf = self;
    __weak YTAGDLSession *weakSession = session;
    session.progressVC.onCancel = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        YTAGDLSession *s = weakSession;
        if (!strongSelf || !s) return;
        [strongSelf dismissProgressForSession:s then:nil];
    };

    [self cleanupTempFilesForSession:session];

    YTAGDownloadCompletion cb = session.completion;
    if (self.activeSession == session) self.activeSession = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (cb) cb(nil, error);
    });
}

- (void)userRequestedCancelForSession:(YTAGDLSession *)session {
    if (session.cancelRequested || session.completionFired) return;
    session.cancelRequested = YES;
    YTAGLog(@"dl-mgr", @"[%@] cancel requested (state=%ld)", session.request.videoID, (long)session.state);

    // 1. Cancel downloaders (no-op if already done).
    [session.videoDownloader cancel];
    [session.audioDownloader cancel];

    // 2. Mux cancellation: FFMpegHelper doesn't expose a cancel entry point; if mux is in
    //    flight we let it run (it's <1s for copy-mux), then finalize cancel in its completion.
    if (session.state == YTAGDLStateMuxing || session.state == YTAGDLStateTranscodingHEVC) {
        YTAGLog(@"dl-mgr", @"[%@] cancel while ffmpeg is active — waiting for ffmpeg to finish", session.request.videoID);
        return; // finalizeCancelForSession runs from the ffmpeg completion.
    }

    [self finalizeCancelForSession:session];
}

- (void)finalizeCancelForSession:(YTAGDLSession *)session {
    if (session.completionFired) return;
    session.completionFired = YES;
    session.state = YTAGDLStateCancelled;

    session.progressVC.phase = YTAGDownloadPhaseCancelled;

    NSError *err = [NSError errorWithDomain:kYTAGDownloadManagerErrorDomain
                                       code:-999
                                   userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}];

    [self cleanupTempFilesForSession:session];

    YTAGDownloadCompletion cb = session.completion;
    if (self.activeSession == session) self.activeSession = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (cb) cb(nil, err);
    });
}

#pragma mark - Helpers

- (void)dismissProgressForSession:(YTAGDLSession *)session then:(void (^ _Nullable)(void))then {
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

- (void)cleanupTempFilesForSession:(YTAGDLSession *)session {
    if (!YTAGDownloadSameFileURL(session.videoLocalURL, session.finalOutputURL)) {
        [self removeURLIfExists:session.videoLocalURL];
    }
    if (!YTAGDownloadSameFileURL(session.audioLocalURL, session.finalOutputURL)) {
        [self removeURLIfExists:session.audioLocalURL];
    }
    if (!YTAGDownloadSameFileURL(session.muxedOutputURL, session.finalOutputURL)) {
        [self removeURLIfExists:session.muxedOutputURL];
    }
    // Intentionally leave finalOutputURL + tmpDir until a later idle point; the share
    // sheet / Photos import need the file on disk briefly. The OS reaps NSTemporaryDirectory
    // on app restart regardless.
}

@end
