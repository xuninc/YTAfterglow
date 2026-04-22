#import <Foundation/Foundation.h>

@class YTAFFormat;
@class YTAFExtractionResult;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAFQualityPreference) {
    YTAFQualityPreferenceHighest = 0,      // best available
    YTAFQualityPreference2160p   = 2160,   // 4K
    YTAFQualityPreference1440p   = 1440,
    YTAFQualityPreference1080p   = 1080,
    YTAFQualityPreference720p    = 720,
    YTAFQualityPreference480p    = 480,
    YTAFQualityPreference360p    = 360,
    YTAFQualityPreference240p    = 240,
    YTAFQualityPreference144p    = 144,
};

typedef NS_ENUM(NSInteger, YTAFCodecPreference) {
    YTAFCodecPreferenceH264   = 0,  // widest compat (avc1.*)
    YTAFCodecPreferenceAV1    = 1,  // av01.* — smaller files, Premium tier
    YTAFCodecPreferenceVP9    = 2,  // vp9 — needed for 2160p/1440p
    YTAFCodecPreferenceAny    = 3,  // no filter, pick best per-resolution
};

typedef NS_ENUM(NSInteger, YTAFAudioQualityPreference) {
    YTAFAudioQualityStandard = 0,  // itag 140 AAC 128k (universal)
    YTAFAudioQualityHigh     = 1,  // itag 141 AAC 256k (Premium Music) — falls back to 140 if absent
};

/// Pairs a video format with an audio format, both chosen from a single extraction result.
/// For audio-only downloads, videoFormat is nil.
@interface YTAFFormatPair : NSObject
@property (nonatomic, strong, nullable) YTAFFormat *videoFormat;
@property (nonatomic, strong, nullable) YTAFFormat *audioFormat;
/// Estimated final muxed file size in bytes (video.contentLength + audio.contentLength + ~1% overhead).
@property (nonatomic, readonly) long long estimatedSize;
/// Human-readable descriptor, e.g. "1080p60 · H.264 · 43 MB"
@property (nonatomic, readonly) NSString *descriptorString;
@end

@interface YTAFFormatSelector : NSObject

/// Pick best video + audio for a preference, returns nil if no suitable video is found.
+ (nullable YTAFFormatPair *)selectVideoPairFromResult:(YTAFExtractionResult *)result
                                               quality:(YTAFQualityPreference)quality
                                                 codec:(YTAFCodecPreference)codec
                                          audioQuality:(YTAFAudioQualityPreference)audioQuality;

/// Audio-only pair (videoFormat == nil).
+ (nullable YTAFFormatPair *)selectAudioPairFromResult:(YTAFExtractionResult *)result
                                          audioQuality:(YTAFAudioQualityPreference)audioQuality;

/// Returns one pair per distinct quality-label in the result, suitable for a UIAlertController picker.
/// Includes audio-only as the last entry (with a nil videoFormat).
+ (NSArray<YTAFFormatPair *> *)allOfferablePairsFromResult:(YTAFExtractionResult *)result
                                              audioQuality:(YTAFAudioQualityPreference)audioQuality;

@end

NS_ASSUME_NONNULL_END
