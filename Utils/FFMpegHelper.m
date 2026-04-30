// FFMpegHelper.m — FFmpegKit-backed muxing for Afterglow downloads.
//
// The conversion flow is split into small, named helpers so the download manager
// can validate inputs, prepare thumbnails, execute FFmpeg, and surface useful
// failure logs without letting long-running work overlap.
//
// ffmpeg backend: we target arthenica/ffmpeg-kit. Forward declarations keep this
// file buildable before the framework is linked; the mux itself still requires
// the framework at runtime.

#import "FFMpegHelper.h"
#import "YTAGLog.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - ffmpeg-kit import / forward declarations

// When the ffmpeg-kit xcframework is present in Frameworks/ (see Frameworks/README.md),
// use the real headers. Otherwise fall back to the forward decls below so this file still
// compiles — the mux won't actually work without the framework, but the build passes.
#if __has_include(<ffmpegkit/FFmpegKit.h>)
#  import <ffmpegkit/FFmpegKit.h>
#  import <ffmpegkit/FFmpegKitConfig.h>
#  import <ffmpegkit/FFmpegSession.h>
#else
@class FFmpegSession;
@interface FFmpegKitConfig : NSObject
+ (void)enableStatisticsCallback:(nullable void (^)(id statistics))callback;
+ (void)enableLogCallback:(nullable void (^)(id log))callback;
@end
@interface FFmpegKit : NSObject
+ (FFmpegSession *)execute:(NSString *)command;
+ (void)cancel;
+ (NSString *)getLastCommandOutput;
@end
@interface FFmpegSession : NSObject
- (long)getReturnCode;
@end
#endif

// ffmpeg-kit return-code handling: rc 0 = success, rc 255 = user-cancelled.
static const long kFFReturnOK = 0;
static const long kFFReturnCancelled = 255;

static BOOL FFMpegFileExistsAndHasBytes(NSURL *url, unsigned long long *outBytes) {
    if (!url.path.length) return NO;
    NSError *attrErr = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:&attrErr];
    unsigned long long bytes = attrs ? [attrs fileSize] : 0;
    if (outBytes) *outBytes = bytes;
    return attrs != nil && bytes > 0;
}

#pragma mark - ToastView placeholder

// UI progress is intentionally abstracted for now. These no-op shims let the
// conversion pipeline expose useful diagnostics while we iterate on the final
// in-app progress surface.
@protocol FFMpegToastSurface <NSObject>
- (void)showToast:(NSString *)text;
- (void)showProgressWithText:(NSString *)text progress:(double)progress withStop:(void (^)(void))stop stopCompletion:(double)stopCompletion;
- (void)hide;
@end

@interface FFMpegToastStub : NSObject <FFMpegToastSurface>
@end
@implementation FFMpegToastStub
- (void)showToast:(NSString *)text { YTAGLog(@"ffmpeg", @"toast: %@", text); }
- (void)showProgressWithText:(NSString *)text progress:(double)progress withStop:(void (^)(void))stop stopCompletion:(double)stopCompletion { YTAGLog(@"ffmpeg", @"toast progress: %@", text); }
- (void)hide { }
@end

static NSString *FFLocalizedString(NSString *key) {
    // English fallbacks for conversion status and failure states.
    NSDictionary *fallback = @{
        @"WaitsForConversion": @"Waiting for the current conversion to finish…",
        @"Converting":         @"Converting…",
        @"Cancelled":          @"Cancelled",
        @"Error.Clipboard":    @"Conversion failed. Details copied to the clipboard.",
    };
    return fallback[key] ?: key;
}

static NSError *FFMpegNSError(NSString *message) {
    return [NSError errorWithDomain:@"ErrDomain"
                               code:0
                           userInfo:@{NSLocalizedDescriptionKey: message ?: FFLocalizedString(@"Error.Clipboard")}];
}

static NSString *FFMpegSessionLogs(FFmpegSession *session) {
    NSString *lastOut = nil;
    @try {
        if ([session respondsToSelector:@selector(getAllLogsAsString)]) {
            lastOut = ((NSString *(*)(id, SEL))objc_msgSend)(session, @selector(getAllLogsAsString));
        } else if ([session respondsToSelector:@selector(getOutput)]) {
            lastOut = ((NSString *(*)(id, SEL))objc_msgSend)(session, @selector(getOutput));
        }
    } @catch (id ex) {
        YTAGLog(@"ffmpeg", @"getAllLogsAsString threw: %@", ex);
    }
    return lastOut;
}

#pragma mark - FFMpegHelper

@interface FFMpegHelper ()
@property (nonatomic, strong, nullable) id<FFMpegToastSurface> activeToast;
@property (nonatomic, strong, nullable) id<FFMpegToastSurface> progressToast;
@property (nonatomic, strong, nullable) id statistics; // ivar cleared at mux start
@end

@implementation FFMpegHelper {
    dispatch_queue_t _ffmpegQueue;
    BOOL _isProcessing;
    NSInteger _duration;
}

+ (instancetype)sharedManager {
    static FFMpegHelper *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FFMpegHelper new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ffmpegQueue = dispatch_queue_create("i.am.kain.afterglow.ffmpeg", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (dispatch_queue_t)ffmpegQueue { return _ffmpegQueue; }
- (BOOL)isProcessing { return _isProcessing; }
- (NSInteger)duration { return _duration; }

#pragma mark - Public entry

- (void)muxVideo:(NSURL *)videoURL
           audio:(NSURL *)audioURL
        captions:(NSURL *)captionsURL
        duration:(NSInteger)durationSeconds
      completion:(FFMpegHelperCompletion)completion
{
    YTAGLog(@"ffmpeg", @"[bc] muxVideo: ENTER video=%@ audio=%@ caps=%@ dur=%lds",
            videoURL.lastPathComponent, audioURL.lastPathComponent,
            captionsURL.lastPathComponent ?: @"<none>", (long)durationSeconds);
    if (!completion) return;
    if (!videoURL || !audioURL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, FFMpegNSError(@"Mux could not start because a video or audio file was missing."));
        });
        return;
    }

    unsigned long long videoBytes = 0;
    unsigned long long audioBytes = 0;
    if (!FFMpegFileExistsAndHasBytes(videoURL, &videoBytes)) {
        NSString *message = [NSString stringWithFormat:@"Mux could not start because the video stream file was empty or missing (%@).", videoURL.lastPathComponent ?: @"video"];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, FFMpegNSError(message));
        });
        return;
    }
    if (!FFMpegFileExistsAndHasBytes(audioURL, &audioBytes)) {
        NSString *message = [NSString stringWithFormat:@"Mux could not start because the audio stream file was empty or missing (%@).", audioURL.lastPathComponent ?: @"audio"];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, FFMpegNSError(message));
        });
        return;
    }
    YTAGLog(@"ffmpeg", @"[bc] mux inputs: video=%llu bytes audio=%llu bytes", videoBytes, audioBytes);

    // Fresh toast for the in-progress state. This may be replaced by the
    // conversion progress toast once the queued work starts.
    id<FFMpegToastSurface> toast = [FFMpegToastStub new];

    // If a mux is already running, surface a "please wait" toast on main. The
    // serial queue still preserves request order.
    if (_isProcessing) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [toast showToast:FFLocalizedString(@"WaitsForConversion")];
        });
    }

    // Enqueue the full mux pipeline on the serial ffmpeg queue.
    dispatch_async(_ffmpegQueue, ^{
        [self runMuxPipelineWithVideo:videoURL
                                audio:audioURL
                             captions:captionsURL
                             duration:durationSeconds
                           waitToast:toast
                          completion:completion];
    });
}

#pragma mark - Private mux pipeline

/// Runs on _ffmpegQueue and owns the full mux pipeline.
- (void)runMuxPipelineWithVideo:(NSURL *)videoURL
                          audio:(NSURL *)audioURL
                       captions:(NSURL *)captionsURL
                       duration:(NSInteger)durationSeconds
                      waitToast:(id<FFMpegToastSurface>)waitToast
                     completion:(FFMpegHelperCompletion)completion
{
    // Flip processing state, stash duration, and clear previous statistics.
    _isProcessing = YES;
    _duration = durationSeconds;
    self.statistics = nil;
    // MobileFFmpeg: +[MobileFFmpegConfig resetStatistics]. ffmpeg-kit equivalent is
    // [FFmpegKitConfig resetStatistics] (class method, same semantics).
    // For draft, the reset is a no-op if we haven't run anything yet, so we skip it and
    // rely on the per-session statistics from ffmpeg-kit's callback.

    // UI prep on main: mark active, hide wait-toast, create fresh progress toast,
    // and wire the stop action to FFmpegKit cancellation.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setActive];
        [waitToast hide];
        id<FFMpegToastSurface> progress = [FFMpegToastStub new];
        self.progressToast = progress;
        [progress showProgressWithText:FFLocalizedString(@"Converting")
                              progress:1.0
                              withStop:^{ [FFmpegKit cancel]; }
                        stopCompletion:0.0];
    });

    // Paths live beside the downloaded video stream file.
    NSURL *dir        = [videoURL URLByDeletingLastPathComponent];
    NSURL *outputURL  = [dir URLByAppendingPathComponent:@"output.mp4"];
    NSURL *webpThumb  = [dir URLByAppendingPathComponent:@"thumbnail.webp"];
    NSURL *jpgThumb   = [dir URLByAppendingPathComponent:@"thumbnail.jpg"];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:jpgThumb error:nil];
    [fm removeItemAtURL:outputURL error:nil];

    // If a webp thumbnail is sitting alongside the video, transcode it to jpg
    // synchronously so getCommand can embed it as cover art.
    NSURL *thumbnailForCommand = nil;
    if ([fm fileExistsAtPath:webpThumb.path]) {
        NSString *thumbCmd = [NSString stringWithFormat:
            @"-hide_banner -loglevel error -i \"%@\" -q:v 1 \"%@\"",
            webpThumb.path, jpgThumb.path];
        (void)[FFmpegKit execute:thumbCmd];
        thumbnailForCommand = jpgThumb;
    }

    // Build the mux command via the sibling method. The variant is selected by
    // which optional assets exist.
    NSString *command = [self getCommandWithVideoURL:videoURL
                                            audioURL:audioURL
                                         captionsURL:captionsURL
                                        thumbnailURL:thumbnailForCommand
                                            duration:durationSeconds
                                           outputURL:outputURL];

    // Failure logs are pulled from the completed session below. That keeps the
    // pipeline simple and avoids global FFmpeg log delegate state.

    YTAGLog(@"ffmpeg", @"[bc] muxVideo: command=%@", command);

    // Execute synchronously on our serial ffmpeg queue, then dispatch completion
    // to main. Keeping execution on this queue prevents overlapping mux jobs.
    YTAGLog(@"ffmpeg", @"[bc] muxVideo: calling FFmpegKit execute:");
    FFmpegSession *session = [FFmpegKit execute:command];
    YTAGLog(@"ffmpeg", @"[bc] muxVideo: execute: returned session=%@", session);

    // ffmpeg-kit's real -[FFmpegSession getReturnCode] returns a ReturnCode *
    // object, not a primitive. Our forward-decl in the no-xcframework branch
    // claims it returns `long`, so `long rc = [session getReturnCode]` silently
    // cast the pointer to an integer. Dispatch dynamically and unwrap via
    // -[ReturnCode getValue] so we get the real int regardless of header shape.
    long rc = -1;
    @try {
        id rcObj = ((id (*)(id, SEL))objc_msgSend)(session, @selector(getReturnCode));
        if (rcObj == nil) {
            rc = -1;
        } else if ([rcObj respondsToSelector:@selector(getValue)]) {
            rc = (long)((int (*)(id, SEL))objc_msgSend)(rcObj, @selector(getValue));
        } else if ([rcObj isKindOfClass:[NSNumber class]]) {
            rc = [(NSNumber *)rcObj longValue];
        } else {
            // Unknown shape — treat as failure rather than crashing on downstream
            // format specifiers. Log the class so we can see what we missed.
            YTAGLog(@"ffmpeg", @"unexpected getReturnCode shape: %@", NSStringFromClass([rcObj class]));
            rc = -1;
        }
    } @catch (id ex) {
        YTAGLog(@"ffmpeg", @"getReturnCode threw: %@", ex);
        rc = -1;
    }
    YTAGLog(@"ffmpeg", @"mux rc=%ld", rc);

    // Completion handler on main.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressToast hide];
        self->_isProcessing = NO;

        if (rc == kFFReturnOK) {
            unsigned long long outBytes = 0;
            if (FFMpegFileExistsAndHasBytes(outputURL, &outBytes)) {
                YTAGLog(@"ffmpeg", @"mux output ok: %@ (%llu bytes)", outputURL.lastPathComponent, outBytes);
                completion(outputURL, nil);
                return;
            }

            NSString *lastOut = FFMpegSessionLogs(session);
            [self getCleanLog:lastOut];
            completion(nil, FFMpegNSError(@"Mux finished but did not produce a usable output file."));
            return;
        }

        NSString *descKey;
        if (rc == kFFReturnCancelled) {
            descKey = @"Cancelled";
        } else {
            // ffmpeg-kit stores output per session, not class-wide. Pull the
            // output off the session object we already have.
            NSString *lastOut = FFMpegSessionLogs(session);
            [self getCleanLog:lastOut];
            descKey = @"Error.Clipboard";
        }

        completion(nil, FFMpegNSError(FFLocalizedString(descKey)));
    });
}

#pragma mark - getCommandWithVideoURL: — 4-variant mux string

// Command shape depends on which of captions/thumbnail exist on disk at build
// time. Paths are quote-wrapped for resilience, and NSURL inputs are converted
// to plain filesystem paths before being passed to ffmpeg.
- (NSString *)getCommandWithVideoURL:(NSURL *)videoURL
                            audioURL:(NSURL *)audioURL
                         captionsURL:(NSURL *)captionsURL
                        thumbnailURL:(NSURL *)thumbnailURL
                            duration:(NSInteger)durationSeconds
                           outputURL:(NSURL *)outputURL
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL hasCaps  = captionsURL  ? [fm fileExistsAtPath:captionsURL.path]  : NO;
    BOOL hasThumb = thumbnailURL ? [fm fileExistsAtPath:thumbnailURL.path] : NO;

    // Caption language metadata currently falls back to the filename stem. The
    // downstream effect is cosmetic: "English" instead of ISO "eng", while
    // players still recognize and list the track.
    NSString *langCode = hasCaps ? [self codeForCaps:captionsURL] : nil;
    NSString *durationArg = durationSeconds > 0
        ? [NSString stringWithFormat:@"-to %ld ", (long)durationSeconds]
        : @"";

    // Captions + thumbnail.
    if (hasCaps && hasThumb) {
        return [NSString stringWithFormat:
            @"-hide_banner -y -loglevel error -i \"%@\" -i \"%@\" -i \"%@\" -i \"%@\" %@"
            @"-map 0:v:0 -map 1:a:0 -map 2:0 -map 3:v:0 "
            @"-c:v copy -c:a copy -c:s mov_text "
            @"-metadata:s:s:0 language=%@ "
            @"-movflags +faststart "
            @"-disposition:3 attached_pic \"%@\"",
            videoURL.path, audioURL.path, captionsURL.path, thumbnailURL.path,
            durationArg, langCode, outputURL.path];
    }

    // Captions only.
    if (hasCaps && !hasThumb) {
        return [NSString stringWithFormat:
            @"-hide_banner -y -loglevel error -i \"%@\" -i \"%@\" -i \"%@\" %@"
            @"-map 0:v:0 -map 1:a:0 -map 2:0 "
            @"-c:v copy -c:a copy -c:s mov_text "
            @"-movflags +faststart "
            @"-metadata:s:s:0 language=%@ \"%@\"",
            videoURL.path, audioURL.path, captionsURL.path,
            durationArg, langCode, outputURL.path];
    }

    // Thumbnail only.
    if (!hasCaps && hasThumb) {
        return [NSString stringWithFormat:
            @"-hide_banner -y -loglevel error -i \"%@\" -i \"%@\" -i \"%@\" %@"
            @"-map 0:v:0 -map 1:a:0 -map 2:v:0 "
            @"-c:v copy -c:a copy "
            @"-movflags +faststart "
            @"-disposition:2 attached_pic \"%@\"",
            videoURL.path, audioURL.path, thumbnailURL.path,
            durationArg, outputURL.path];
    }

    // Minimal: video + audio only.
    return [NSString stringWithFormat:
        @"-hide_banner -y -loglevel error -i \"%@\" -i \"%@\" %@"
        @"-map 0:v:0 -map 1:a:0 "
        @"-c:v copy -c:a copy -movflags +faststart \"%@\"",
        videoURL.path, audioURL.path,
        durationArg, outputURL.path];
}

- (void)cutAudio:(NSURL *)audioURL
        duration:(NSInteger)durationSeconds
      completion:(FFMpegHelperCompletion)completion
{
    // Not on the hot path for MP4 downloads; only invoked for audio-only
    // extraction after the main mux.
    NSError *err = [NSError errorWithDomain:@"ErrDomain" code:-1
                                   userInfo:@{NSLocalizedDescriptionKey: @"cutAudio not yet implemented"}];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
}

#pragma mark - getCleanLog: — ffmpeg error-log distillation

// Takes ffmpeg's verbose stderr dump, dedupes consecutive duplicate lines,
// trims leading/trailing whitespace, strips trailing "." characters, and
// copies the result to the pasteboard. Used when a mux fails so the user
// can paste the real error into a bug report.
- (void)getCleanLog:(NSString *)lastOutput {
    if (lastOutput.length == 0) return;

    NSArray<NSString *> *rawLines = [lastOutput
        componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *> *deduped = [NSMutableArray array];
    NSString *lastLine = nil;
    for (NSString *line in rawLines) {
        if (line.length == 0) continue;
        if (lastLine && [line isEqualToString:lastLine]) continue;
        [deduped addObject:line];
        lastLine = line;
    }

    NSString *joined = [deduped componentsJoinedByString:@"\n"];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trimmed = [joined stringByTrimmingCharactersInSet:ws];

    // Strip trailing "." characters — ffmpeg sometimes tacks on ellipsis-style dots
    // for progress/status lines that bleed into the error trail.
    while ([trimmed hasSuffix:@"."]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
        trimmed = [trimmed stringByTrimmingCharactersInSet:ws];
    }

    if (trimmed.length == 0) return;

    // Log via YTAGLog first so the output survives even if pasteboard write fails,
    // then stash on the clipboard for the user's next paste.
    YTAGLog(@"ffmpeg", @"clean log:\n%@", trimmed);
    [[UIPasteboard generalPasteboard] setString:trimmed];
}

- (void)setActive {
    // TODO: wire FFmpegKit log/statistics callbacks for live progress-toast
    // updates. The current mux pipeline works without these callbacks.
}

- (void)updateProgressDialog {
    // TODO: update the progress toast from FFmpegKit statistics callbacks.
    // Cosmetic only; no effect on mux correctness.
}

- (NSString *)codeForCaps:(NSURL *)captionsURL {
    // Caption filenames come from YTAGCaptionTrack display names, so the stem is
    // already human-readable. A future mapping can normalize these to ISO codes.
    if (!captionsURL) return nil;
    return [[captionsURL.path lastPathComponent] stringByDeletingPathExtension];
}

@end
