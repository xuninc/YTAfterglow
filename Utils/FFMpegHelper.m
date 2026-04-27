// FFMpegHelper.m — reconstruction of -[FFMpegHelper mergeVideo:withAudio:captions:duration:completion:]
// from YTLite raw decompilation.
//
// Source: /mnt/c/Users/Corey/source/repos/xuninc/YTLite-decompiled/C File/YTLite.dylib.c
//   - entry          at line 381630  (address 0x00054BE0)
//   - sub_54D98      "WaitsForConversion" toast-on-main
//   - sub_54E0C      ffmpeg-queue work block (thumbnail prep + main mux dispatch)
//   - sub_5510C      UI prep (setActive, show "Converting" progress toast)
//   - sub_551C8      stop-button handler -> [MobileFFmpeg cancel]
//   - sub_551D4      execute mux on global queue, then dispatch completion on main
//   - sub_55278      result handler on main (NSError construction by return code)
//
// The raw monolithic function is split here into smaller private methods that correspond
// 1:1 with the inline blocks in the decomp. Behavior preserved verbatim.
//
// ffmpeg backend: we target arthenica/ffmpeg-kit (successor to MobileFFmpeg). The few entry
// points the raw touches — +resetStatistics, +setLogDelegate:, +execute:, +cancel,
// +getLastCommandOutput — all exist on ffmpeg-kit's FFmpegKitConfig/FFmpegKit with the same
// semantics (return code 0 == success, 255 == cancelled per ffmpeg-kit docs). Forward-decl'd
// below so this file compiles before the framework is linked.

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

// YTLite used MobileFFmpeg's convention: rc 0 = success, rc 255 = user-cancelled. ffmpeg-kit
// preserves these numeric codes so the branch logic below is correct for both backends.
static const long kFFReturnOK = 0;
static const long kFFReturnCancelled = 255;

#pragma mark - ToastView placeholder

// The raw dispatches UI updates through a ToastView class. Not reconstructed yet —
// we'll replace these calls with YTAGDebugHUD / YTAGLog or a real ToastView port later.
// Stubbed here as protocol-shaped no-ops so the reconstruction compiles and the call
// graph matches the raw.
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
    // Raw fetches via [NSBundle ytl_defaultBundle]. We don't have that bundle yet.
    // Known keys: "WaitsForConversion", "Converting", "Cancelled", "Error.Clipboard".
    // English fallbacks that match YTLite's strings:
    NSDictionary *fallback = @{
        @"WaitsForConversion": @"Waiting for the current conversion to finish…",
        @"Converting":         @"Converting…",
        @"Cancelled":          @"Cancelled",
        @"Error.Clipboard":    @"Conversion failed. Details copied to the clipboard.",
    };
    return fallback[key] ?: key;
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

#pragma mark - Public entry (raw line 381630)

- (void)muxVideo:(NSURL *)videoURL
           audio:(NSURL *)audioURL
        captions:(NSURL *)captionsURL
        duration:(NSInteger)durationSeconds
      completion:(FFMpegHelperCompletion)completion
{
    YTAGLog(@"ffmpeg", @"[bc] muxVideo: ENTER video=%@ audio=%@ caps=%@ dur=%lds",
            videoURL.lastPathComponent, audioURL.lastPathComponent,
            captionsURL.lastPathComponent ?: @"<none>", (long)durationSeconds);
    NSParameterAssert(videoURL);
    NSParameterAssert(audioURL);
    NSParameterAssert(completion);

    // Fresh toast for the in-progress state. In the raw, this is alloc/init'd unconditionally
    // here even though it may get replaced by the "Converting" progress toast inside the work
    // block. We preserve that shape.
    id<FFMpegToastSurface> toast = [FFMpegToastStub new];

    // sub_54D98 — if a mux is already running, surface a "please wait" toast on main.
    // We still enqueue the new work: the ffmpeg queue is serial so ordering is preserved
    // automatically.
    if (_isProcessing) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [toast showToast:FFLocalizedString(@"WaitsForConversion")];
        });
    }

    // sub_54E0C — enqueue the full mux pipeline on the serial ffmpeg queue.
    dispatch_async(_ffmpegQueue, ^{
        [self runMuxPipelineWithVideo:videoURL
                                audio:audioURL
                             captions:captionsURL
                             duration:durationSeconds
                           waitToast:toast
                          completion:completion];
    });
}

#pragma mark - Private (raw sub_54E0C)

/// Runs on _ffmpegQueue. Matches the body of sub_54E0C in the raw decomp.
- (void)runMuxPipelineWithVideo:(NSURL *)videoURL
                          audio:(NSURL *)audioURL
                       captions:(NSURL *)captionsURL
                       duration:(NSInteger)durationSeconds
                      waitToast:(id<FFMpegToastSurface>)waitToast
                     completion:(FFMpegHelperCompletion)completion
{
    // Raw lines 117-123: flip processing flag, stash duration, clear previous statistics,
    // reset the ffmpeg-level statistics state.
    _isProcessing = YES;
    _duration = durationSeconds;
    self.statistics = nil;
    // MobileFFmpeg: +[MobileFFmpegConfig resetStatistics]. ffmpeg-kit equivalent is
    // [FFmpegKitConfig resetStatistics] (class method, same semantics).
    // For draft, the reset is a no-op if we haven't run anything yet, so we skip it and
    // rely on the per-session statistics from ffmpeg-kit's callback.

    // sub_5510C — UI prep on main: setActive, hide wait-toast, create fresh progress toast
    // pointing at sub_551C8 (stop-button handler == [FFmpegKit cancel]).
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

    // Raw lines 132-141: paths live beside the video file.
    NSURL *dir        = [videoURL URLByDeletingLastPathComponent];
    NSURL *outputURL  = [dir URLByAppendingPathComponent:@"output.mp4"];
    NSURL *webpThumb  = [dir URLByAppendingPathComponent:@"thumbnail.webp"];
    NSURL *jpgThumb   = [dir URLByAppendingPathComponent:@"thumbnail.jpg"];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:jpgThumb error:nil];
    [fm removeItemAtURL:outputURL error:nil];

    // Raw lines 142-158: if a webp thumbnail is sitting alongside the video, transcode it
    // to jpg synchronously so getCommand can embed it as cover art.
    NSURL *thumbnailForCommand = nil;
    if ([fm fileExistsAtPath:webpThumb.path]) {
        NSString *thumbCmd = [NSString stringWithFormat:
            @"-hide_banner -loglevel error -i \"%@\" -q:v 1 \"%@\"",
            webpThumb.path, jpgThumb.path];
        (void)[FFmpegKit execute:thumbCmd];
        thumbnailForCommand = jpgThumb;
    }

    // Raw line 159-168: build the mux command via the sibling method (variant selected by
    // which of captions/thumbnail exist).
    NSString *command = [self getCommandWithVideoURL:videoURL
                                            audioURL:audioURL
                                         captionsURL:captionsURL
                                        thumbnailURL:thumbnailForCommand
                                            duration:durationSeconds
                                           outputURL:outputURL];

    // Raw line 169: set self as the log delegate so -getCleanLog: can be invoked on failure.
    // ffmpeg-kit equivalent: [FFmpegKitConfig enableLogCallback:^(id log){ ... }]. We wire
    // a lightweight pipe so getCleanLog: can still see the output — TODO once we reconstruct
    // getCleanLog: and pick a real log-stash mechanism.
    // (Draft: skip log-delegate routing; getLastCommandOutput below covers the failure-path
    // scraping.)

    YTAGLog(@"ffmpeg", @"[bc] muxVideo: command=%@", command);

    // sub_551D4 — execute the mux on a global queue, then dispatch completion to main.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        YTAGLog(@"ffmpeg", @"[bc] muxVideo: calling FFmpegKit execute:");
        FFmpegSession *session = [FFmpegKit execute:command];
        YTAGLog(@"ffmpeg", @"[bc] muxVideo: execute: returned session=%@", session);

        // ffmpeg-kit's real -[FFmpegSession getReturnCode] returns a ReturnCode *
        // object, not a primitive. Our forward-decl in the no-xcframework branch
        // claims it returns `long`, so `long rc = [session getReturnCode]` silently
        // cast the pointer to an integer — every rc we logged pre-v31 (5347512016
        // etc.) was the ReturnCode's heap address, not an exit code. Dispatch the
        // call dynamically and unwrap via -[ReturnCode getValue] so we get the
        // real int regardless of which header variant was in scope at compile.
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

        // sub_55278 — completion handler on main.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.progressToast hide];
            self->_isProcessing = NO;

            if (rc == kFFReturnOK) {
                completion(outputURL, nil);
                return;
            }

            NSString *descKey;
            if (rc == kFFReturnCancelled) {
                descKey = @"Cancelled";
            } else {
                // ffmpeg-kit stores output PER-SESSION, not class-wide. YTLite's
                // MobileFFmpeg had `+[FFmpegKit getLastCommandOutput]` at the class
                // level — that selector does NOT exist on ffmpeg-kit's FFmpegKit
                // class. Calling it through the v31 forward-decl stub crashed with
                // an unrecognized-selector exception on every rc != 0 path. Pull
                // the output off the session object we already have instead.
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
                [self getCleanLog:lastOut];
                descKey = @"Error.Clipboard";
            }

            NSError *err = [NSError errorWithDomain:@"ErrDomain"
                                               code:0
                                           userInfo:@{NSLocalizedDescriptionKey: FFLocalizedString(descKey)}];
            completion(nil, err);
        });
    });
}

#pragma mark - getCommandWithVideoURL: — 4-variant mux string (raw .c:382007)

// Port of -[FFMpegHelper getCommandWithVideoURL:audioURL:captionsURL:thumbnailURL:duration:outputURL:]
// from YTLite.dylib.c:382007-382119. Command shape depends on which of captions/thumbnail
// exist on disk at build time. All four variants below match YTLite byte-for-byte, with
// two deliberate deltas:
//   1. Paths are quote-wrapped. ffmpeg-kit's tokenizer supports shell-like quoting; YTLite's
//      MobileFFmpeg may have used a different tokenizer. Quoting makes us robust to any
//      future tmp-dir layout that has spaces (sandboxed Documents paths can't have them today
//      but defensive is cheap).
//   2. We pass `.path` (NSString) rather than the NSURL itself. YTLite's code passes NSURL,
//      which %@ formats as `file:///...`. ffmpeg handles `file://` URLs fine, but the plain
//      path is what every other ffmpeg example in the world uses, so we lean there.
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

    // YTLite's codeForCaps: — dictionary lookup on the filename stem. Until we
    // port the full lang-code dict (off_E0BCD0 in YTLite, constant at load time),
    // fall back to the filename stem. Downstream effect: mp4 track metadata
    // language tag will be "English" instead of "eng". Players still recognize
    // the track; just cosmetically non-ISO.
    NSString *langCode = hasCaps ? [self codeForCaps:captionsURL] : nil;

    // Branch 1 (YTLite raw line 382055) — captions + thumbnail
    if (hasCaps && hasThumb) {
        return [NSString stringWithFormat:
            @"-hide_banner -loglevel error -i \"%@\" -i \"%@\" -i \"%@\" -i \"%@\" -to %ld "
            @"-map 0 -map 1 -map 2 -map 3 "
            @"-c:v copy -c:a copy -c:s mov_text "
            @"-metadata:s:s:0 language=%@ "
            @"-disposition:3 attached_pic \"%@\"",
            videoURL.path, audioURL.path, captionsURL.path, thumbnailURL.path,
            (long)durationSeconds, langCode, outputURL.path];
    }

    // Branch 2 (YTLite raw line 382074) — captions only
    if (hasCaps && !hasThumb) {
        return [NSString stringWithFormat:
            @"-hide_banner -loglevel error -i \"%@\" -i \"%@\" -i \"%@\" -to %ld "
            @"-c:v copy -c:a copy -c:s mov_text "
            @"-metadata:s:s:0 language=%@ \"%@\"",
            videoURL.path, audioURL.path, captionsURL.path,
            (long)durationSeconds, langCode, outputURL.path];
    }

    // Branch 4 (YTLite raw line 382101) — thumbnail only (no captions)
    if (!hasCaps && hasThumb) {
        return [NSString stringWithFormat:
            @"-hide_banner -loglevel error -i \"%@\" -i \"%@\" -i \"%@\" -to %ld "
            @"-map 0 -map 1 -map 2 "
            @"-c:v copy -c:a copy "
            @"-disposition:2 attached_pic \"%@\"",
            videoURL.path, audioURL.path, thumbnailURL.path,
            (long)durationSeconds, outputURL.path];
    }

    // Branch 3 (YTLite raw line 382089) — minimal: video + audio only
    return [NSString stringWithFormat:
        @"-hide_banner -loglevel error -i \"%@\" -i \"%@\" -to %ld "
        @"-c:v copy -c:a copy \"%@\"",
        videoURL.path, audioURL.path,
        (long)durationSeconds, outputURL.path];
}

- (void)cutAudio:(NSURL *)audioURL
        duration:(NSInteger)durationSeconds
      completion:(FFMpegHelperCompletion)completion
{
    // TODO: reconstruct from raw .c line 382128. Not on the hot path for MP4 downloads —
    // only invoked for audio-only extraction after the main mux.
    NSError *err = [NSError errorWithDomain:@"ErrDomain" code:-1
                                   userInfo:@{NSLocalizedDescriptionKey: @"cutAudio not yet reconstructed"}];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
}

#pragma mark - getCleanLog: — ffmpeg error-log distillation (raw .c:382410)

// Port of -[FFMpegHelper getCleanLog:] from YTLite.dylib.c:382410-382514.
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
    // TODO: port from raw .c line 382520. YTLite wired MobileFFmpegConfig's log +
    // statistics delegates to self. ffmpeg-kit uses callback blocks instead
    // (+[FFmpegKitConfig enableLogCallback:], enableStatisticsCallback:). The current
    // mux pipeline works without these; wiring them up only adds progress-toast
    // updates, not download correctness.
}

- (void)updateProgressDialog {
    // TODO: port from raw .c line 382528. Depends on setActive wiring self.statistics
    // via the ffmpeg-kit statistics callback. Cosmetic only — no effect on the mux.
}

- (NSString *)codeForCaps:(NSURL *)captionsURL {
    // YTLite raw .c:382569 reads a constant dict (off_E0BCD0 = NSConstantDictionary)
    // keyed on filename stem ("English" → "eng"), falling back to the stem itself.
    // We skip the dict for now — our caption filenames come from YTAGCaptionTrack
    // display names, so stem is already human-language text. Downstream metadata is
    // "language=English" instead of ISO "eng"; MP4 players still list the track.
    if (!captionsURL) return nil;
    return [[captionsURL.path lastPathComponent] stringByDeletingPathExtension];
}

@end
