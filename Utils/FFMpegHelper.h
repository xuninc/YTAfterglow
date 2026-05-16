// FFMpegHelper — FFmpegKit-backed muxing helper for Afterglow downloads.
//
// This header declares the conversion surface used by the download manager.
// Only the MP4 mux path is implemented today; the remaining methods are kept
// as explicit extension points for future audio-only and progress UI work.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Success yields outputURL; failure yields NSError in domain "ErrDomain" with
/// localized description. Always invoked on the main queue.
typedef void (^FFMpegHelperCompletion)(NSURL * _Nullable outputURL, NSError * _Nullable error);

@interface FFMpegHelper : NSObject

/// Serial dispatch queue used for every ffmpeg invocation.
@property (nonatomic, readonly) dispatch_queue_t ffmpegQueue;

/// YES while a mux is in flight. Set inside the queued work block and cleared in the
/// completion-on-main block.
@property (nonatomic, readonly) BOOL isProcessing;

/// Expected duration (seconds) of the current mux, so the statistics callback can compute
/// a progress fraction.
@property (nonatomic, readonly) NSInteger duration;

+ (instancetype)sharedManager;

/// Public entry. Muxes `videoURL` + `audioURL` + optional `captionsURL` into `video.URLByDeletingLastPathComponent/output.mp4`.
///
/// Thumbnail handling is automatic: if `thumbnail.webp` exists in the same directory, it is
/// transcoded to `thumbnail.jpg` via ffmpeg before the main mux, then embedded as cover art.
/// Old `thumbnail.jpg` and `output.mp4` in that directory are deleted first.
///
/// Positive `durationSeconds` is passed as `-to` to ffmpeg so output stops at the expected end.
/// Zero/unknown duration is omitted instead of producing a zero-second mux.
///
/// If another mux is already running, a "WaitsForConversion" toast is shown and the request
/// is serialized behind the current one (the internal queue is serial).
///
/// Completion runs on the main queue. On success `outputURL` is the written file; on failure
/// `error` is an NSError in domain "ErrDomain" with localized description — either "Cancelled"
/// (ffmpeg return code 255) or "Error.Clipboard" (any other non-zero return code).
///
- (void)muxVideo:(NSURL *)videoURL
           audio:(NSURL *)audioURL
        captions:(nullable NSURL *)captionsURL
        duration:(NSInteger)durationSeconds
      completion:(FFMpegHelperCompletion)completion;

/// Transcodes an already-muxed video into a Photos-compatible HEVC/H.265 MP4.
/// Intended for VP9/AV1 files that download and mux correctly but are rejected
/// by `PHPhotoLibrary` with PHPhotosErrorDomain 3302.
- (void)transcodeVideoToHEVCForPhotos:(NSURL *)inputURL
                             outputURL:(NSURL *)outputURL
                              duration:(NSInteger)durationSeconds
                          videoBitrate:(NSInteger)videoBitrate
                            completion:(FFMpegHelperCompletion)completion;

#pragma mark - Siblings (declared only; implementations TODO)

/// Build the ffmpeg command string from the four optional inputs. Four variants selected by
/// which of captions/thumbnail exist on disk.
/// TODO: finish audio-only and progress-specific variants.
- (NSString *)getCommandWithVideoURL:(NSURL *)videoURL
                            audioURL:(NSURL *)audioURL
                         captionsURL:(nullable NSURL *)captionsURL
                        thumbnailURL:(nullable NSURL *)thumbnailURL
                            duration:(NSInteger)durationSeconds
                           outputURL:(NSURL *)outputURL;

/// Audio-only cut/transcode variant.
- (void)cutAudio:(NSURL *)audioURL
        duration:(NSInteger)durationSeconds
      completion:(FFMpegHelperCompletion)completion;

/// Scrub / format the last ffmpeg log output before surfacing to user.
- (void)getCleanLog:(NSString *)lastOutput;

/// Called to mark the mux as active (lifecycle signal).
- (void)setActive;

/// Update the progress toast with current statistics.
- (void)updateProgressDialog;

/// Language-code lookup from captions filename (dict mapping + filename fallback).
- (nullable NSString *)codeForCaps:(nullable NSURL *)captionsURL;

@end

NS_ASSUME_NONNULL_END
