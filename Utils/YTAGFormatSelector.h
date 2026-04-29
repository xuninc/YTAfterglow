#import <Foundation/Foundation.h>

@class YTAGFormat;
@class YTAGExtractionResult;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAGQualityPreference) {
    YTAGQualityPreferenceHighest = 0,      // best available
    YTAGQualityPreference2160p   = 2160,   // 4K
    YTAGQualityPreference1440p   = 1440,
    YTAGQualityPreference1080p   = 1080,
    YTAGQualityPreference720p    = 720,
    YTAGQualityPreference480p    = 480,
    YTAGQualityPreference360p    = 360,
    YTAGQualityPreference240p    = 240,
    YTAGQualityPreference144p    = 144,
};

typedef NS_ENUM(NSInteger, YTAGCodecPreference) {
    YTAGCodecPreferenceH264   = 0,  // widest compat (avc1.*)
    YTAGCodecPreferenceAV1    = 1,  // av01.* — smaller files, Premium tier
    YTAGCodecPreferenceVP9    = 2,  // vp9 — needed for 2160p/1440p
    YTAGCodecPreferenceAny    = 3,  // no filter, pick best per-resolution
};

typedef NS_ENUM(NSInteger, YTAGAudioQualityPreference) {
    YTAGAudioQualityStandard = 0,  // itag 140 AAC 128k (universal)
    YTAGAudioQualityHigh     = 1,  // itag 141 AAC 256k (Premium Music) — falls back to 140 if absent
};

/// Pairs a video format with an audio format, both chosen from a single extraction result.
/// For audio-only downloads, videoFormat is nil.
@interface YTAGFormatPair : NSObject
@property (nonatomic, strong, nullable) YTAGFormat *videoFormat;
@property (nonatomic, strong, nullable) YTAGFormat *audioFormat;
/// Estimated final muxed file size in bytes (video.contentLength + audio.contentLength + ~1% overhead).
@property (nonatomic, readonly) long long estimatedSize;
/// Human-readable descriptor, e.g. "1080p60 · H.264 · 43 MB"
@property (nonatomic, readonly) NSString *descriptorString;
@end

@interface YTAGFormatSelector : NSObject

/// Pick best video + audio for a preference, returns nil if no suitable video is found.
+ (nullable YTAGFormatPair *)selectVideoPairFromResult:(YTAGExtractionResult *)result
                                               quality:(YTAGQualityPreference)quality
                                                 codec:(YTAGCodecPreference)codec
                                          audioQuality:(YTAGAudioQualityPreference)audioQuality;

/// Audio-only pair (videoFormat == nil).
+ (nullable YTAGFormatPair *)selectAudioPairFromResult:(YTAGExtractionResult *)result
                                          audioQuality:(YTAGAudioQualityPreference)audioQuality;

+ (nullable YTAGFormatPair *)selectAudioPairFromResult:(YTAGExtractionResult *)result
                                          audioQuality:(YTAGAudioQualityPreference)audioQuality
                                             preferDRC:(BOOL)preferDRC;

/// Returns one pair per distinct quality-label in the result, suitable for a UIAlertController picker.
/// Includes audio-only as the last entry (with a nil videoFormat).
+ (NSArray<YTAGFormatPair *> *)allOfferablePairsFromResult:(YTAGExtractionResult *)result
                                              audioQuality:(YTAGAudioQualityPreference)audioQuality;

+ (NSArray<YTAGFormatPair *> *)allOfferablePairsFromResult:(YTAGExtractionResult *)result
                                              audioQuality:(YTAGAudioQualityPreference)audioQuality
                                                 preferDRC:(BOOL)preferDRC;

/// Returns one audio-only row per distinct YouTube audio track/language.
+ (NSArray<YTAGFormatPair *> *)allAudioPairsFromResult:(YTAGExtractionResult *)result
                                          audioQuality:(YTAGAudioQualityPreference)audioQuality
                                             preferDRC:(BOOL)preferDRC;

@end

NS_ASSUME_NONNULL_END
