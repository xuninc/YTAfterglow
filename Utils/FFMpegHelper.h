// FFMpegHelper — reconstructed from YTLite raw decompilation.
//
// Reconstruction source: /mnt/c/Users/Corey/source/repos/xuninc/YTLite-decompiled/C File/YTLite.dylib.c
//
// This header declares the full class surface as it appears in the raw. Only
// -muxVideo:audio:captions:duration:completion: (== raw -mergeVideo:withAudio:...) is
// reconstructed in FFMpegHelper.m; the rest are stubbed with TODO pointers to the raw `.c`
// line ranges so follow-up turns can reconstruct each from the same source without ambiguity.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Completion signature matches the raw: success case yields outputURL, failure yields NSError
/// in domain "ErrDomain" with localized description. Always invoked on the main queue.
typedef void (^FFMpegHelperCompletion)(NSURL * _Nullable outputURL, NSError * _Nullable error);

@interface FFMpegHelper : NSObject

/// Serial dispatch queue used for every ffmpeg invocation. Matches raw `_ffmpegQueue` ivar.
@property (nonatomic, readonly) dispatch_queue_t ffmpegQueue;

/// YES while a mux is in flight. Set inside the queued work block and cleared in the
/// completion-on-main block. Matches raw `_isProcessing` ivar.
@property (nonatomic, readonly) BOOL isProcessing;

/// Expected duration (seconds) of the current mux, so the statistics callback can compute
/// a progress fraction. Matches raw `_duration` ivar.
@property (nonatomic, readonly) NSInteger duration;

+ (instancetype)sharedManager;

/// Public entry. Muxes `videoURL` + `audioURL` + optional `captionsURL` into `video.URLByDeletingLastPathComponent/output.mp4`.
///
/// Thumbnail handling is automatic: if `thumbnail.webp` exists in the same directory, it is
/// transcoded to `thumbnail.jpg` via ffmpeg before the main mux, then embedded as cover art.
/// Old `thumbnail.jpg` and `output.mp4` in that directory are deleted first.
///
/// `durationSeconds` is passed as `-to` to ffmpeg so output stops at the expected end.
///
/// If another mux is already running, a "WaitsForConversion" toast is shown and the request
/// is serialized behind the current one (the internal queue is serial).
///
/// Completion runs on the main queue. On success `outputURL` is the written file; on failure
/// `error` is an NSError in domain "ErrDomain" with localized description — either "Cancelled"
/// (ffmpeg return code 255) or "Error.Clipboard" (any other non-zero return code).
///
/// Reconstruction: raw `.c` line 381630 (aka address `0x00054BE0`).
- (void)muxVideo:(NSURL *)videoURL
           audio:(NSURL *)audioURL
        captions:(nullable NSURL *)captionsURL
        duration:(NSInteger)durationSeconds
      completion:(FFMpegHelperCompletion)completion;

#pragma mark - Siblings (declared only; implementations TODO)

/// Build the ffmpeg command string from the four optional inputs. Four variants selected by
/// which of captions/thumbnail exist on disk.
/// TODO: reconstruct from raw `.c` line 382007.
- (NSString *)getCommandWithVideoURL:(NSURL *)videoURL
                            audioURL:(NSURL *)audioURL
                         captionsURL:(nullable NSURL *)captionsURL
                        thumbnailURL:(nullable NSURL *)thumbnailURL
                            duration:(NSInteger)durationSeconds
                           outputURL:(NSURL *)outputURL;

/// Audio-only cut/transcode variant. TODO: reconstruct from raw `.c` line 382128.
- (void)cutAudio:(NSURL *)audioURL
        duration:(NSInteger)durationSeconds
      completion:(FFMpegHelperCompletion)completion;

/// Scrub / format the last ffmpeg log output before surfacing to user. TODO: reconstruct from raw `.c` line 382410.
- (void)getCleanLog:(NSString *)lastOutput;

/// Called to mark the mux as active (lifecycle signal). TODO: reconstruct from raw `.c` line 382520.
- (void)setActive;

/// Update the progress toast with current statistics. TODO: reconstruct from raw `.c` line 382528.
- (void)updateProgressDialog;

/// Language-code lookup from captions filename (dict mapping + filename fallback).
/// TODO: reconstruct from raw `.c` line 382569.
- (nullable NSString *)codeForCaps:(nullable NSURL *)captionsURL;

@end

NS_ASSUME_NONNULL_END
