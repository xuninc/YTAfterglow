#import "YTAFFormatSelector.h"
#import "YTAFURLExtractor.h"
#import "YTAGLog.h"

#pragma mark - Helpers

static BOOL YTAFLabelIsPremium(NSString * _Nullable label) {
    if (label.length == 0) return NO;
    return [label rangeOfString:@"Premium" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL YTAFCodecMatchesH264(NSString * _Nullable codec) {
    return codec.length > 0 && [codec hasPrefix:@"avc1."];
}

static BOOL YTAFCodecMatchesAV1(NSString * _Nullable codec) {
    return codec.length > 0 && [codec hasPrefix:@"av01."];
}

static BOOL YTAFCodecMatchesVP9(NSString * _Nullable codec) {
    if (codec.length == 0) return NO;
    return [codec isEqualToString:@"vp9"] || [codec hasPrefix:@"vp09."];
}

static BOOL YTAFFormatPassesCodecFilter(YTAFFormat *f, YTAFCodecPreference codec) {
    switch (codec) {
        case YTAFCodecPreferenceH264: return YTAFCodecMatchesH264(f.codec);
        case YTAFCodecPreferenceAV1:  return YTAFCodecMatchesAV1(f.codec);
        case YTAFCodecPreferenceVP9:  return YTAFCodecMatchesVP9(f.codec);
        case YTAFCodecPreferenceAny:  return YES;
    }
    return YES;
}

/// Ordering index for codec, smaller = preferred in YTLite's picker ordering.
static NSInteger YTAFCodecSortRank(NSString * _Nullable codec) {
    if (YTAFCodecMatchesH264(codec)) return 0; // H.264 first
    if (YTAFCodecMatchesAV1(codec))  return 1;
    if (YTAFCodecMatchesVP9(codec))  return 2;
    return 3;
}

static NSString *YTAFCodecShortName(NSString * _Nullable codec, NSString * _Nullable container) {
    if (YTAFCodecMatchesH264(codec)) return @"H.264";
    if (YTAFCodecMatchesAV1(codec))  return @"AV1";
    if (YTAFCodecMatchesVP9(codec))  return @"VP9";
    if (container.length > 0)        return container;
    return @"Video";
}

static NSString *YTAFSizeString(long long bytes) {
    if (bytes <= 0) return @"— MB";
    double mb = (double)bytes / (1024.0 * 1024.0);
    if (mb < 1.0) {
        double kb = (double)bytes / 1024.0;
        return [NSString stringWithFormat:@"%.0f KB", kb];
    }
    return [NSString stringWithFormat:@"%.1f MB", mb];
}

/// Pick the best audio format from a set of candidates sharing an itag.
/// Prefers DRC variant when available (YTLite "Prefer stable volume" default-on).
static YTAFFormat * _Nullable YTAFPreferDRC(NSArray<YTAFFormat *> *candidates) {
    if (candidates.count == 0) return nil;
    YTAFFormat *drc = nil;
    YTAFFormat *nonDRC = nil;
    for (YTAFFormat *f in candidates) {
        if (f.isDRC && drc == nil) drc = f;
        else if (!f.isDRC && nonDRC == nil) nonDRC = f;
    }
    return drc ?: nonDRC ?: candidates.firstObject;
}

static NSArray<YTAFFormat *> *YTAFFormatsWithItag(NSArray<YTAFFormat *> *formats, NSInteger itag) {
    NSMutableArray<YTAFFormat *> *out = [NSMutableArray array];
    for (YTAFFormat *f in formats) {
        if (f.itag == itag) [out addObject:f];
    }
    return out;
}

static YTAFFormat * _Nullable YTAFSelectAudioFormat(YTAFExtractionResult *result,
                                                    YTAFAudioQualityPreference pref) {
    NSArray<YTAFFormat *> *audios = result.audioFormats;
    if (audios.count == 0) return nil;

    if (pref == YTAFAudioQualityHigh) {
        NSArray<YTAFFormat *> *i141 = YTAFFormatsWithItag(audios, 141);
        YTAFFormat *pick = YTAFPreferDRC(i141);
        if (pick) return pick;
        NSArray<YTAFFormat *> *i140 = YTAFFormatsWithItag(audios, 140);
        pick = YTAFPreferDRC(i140);
        if (pick) return pick;
        // fallback: highest-bitrate audio
        NSArray<YTAFFormat *> *sorted = [audios sortedArrayUsingComparator:^NSComparisonResult(YTAFFormat *a, YTAFFormat *b) {
            if (a.bitrate == b.bitrate) return NSOrderedSame;
            return a.bitrate > b.bitrate ? NSOrderedAscending : NSOrderedDescending;
        }];
        return sorted.firstObject;
    }

    // Standard
    NSArray<YTAFFormat *> *i140 = YTAFFormatsWithItag(audios, 140);
    YTAFFormat *pick = YTAFPreferDRC(i140);
    if (pick) return pick;
    return audios.firstObject;
}

/// Comparator for "best video" within a candidate set at a single resolution bucket:
/// Premium before non-Premium, then higher bitrate.
static NSComparisonResult YTAFCompareVideoBest(YTAFFormat *a, YTAFFormat *b) {
    BOOL ap = YTAFLabelIsPremium(a.qualityLabel);
    BOOL bp = YTAFLabelIsPremium(b.qualityLabel);
    if (ap != bp) return ap ? NSOrderedAscending : NSOrderedDescending;
    if (a.bitrate != b.bitrate) return a.bitrate > b.bitrate ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
}

#pragma mark - YTAFFormatPair

@implementation YTAFFormatPair

- (long long)estimatedSize {
    if (_videoFormat == nil) {
        return _audioFormat ? _audioFormat.contentLength : 0;
    }
    long long v = _videoFormat.contentLength;
    long long a = _audioFormat ? _audioFormat.contentLength : 0;
    long long overhead = (long long)(0.01 * (double)v);
    long long minOverhead = 100 * 1024; // 100 KB
    if (overhead < minOverhead) overhead = minOverhead;
    return v + a + overhead;
}

- (NSString *)descriptorString {
    long long size = self.estimatedSize;
    NSString *sizeStr = YTAFSizeString(size);
    if (_videoFormat == nil) {
        return [NSString stringWithFormat:@"Audio only · %@", sizeStr];
    }
    NSString *label = _videoFormat.qualityLabel.length > 0 ? _videoFormat.qualityLabel : @"Video";
    NSString *codecShort = YTAFCodecShortName(_videoFormat.codec, _videoFormat.container);
    return [NSString stringWithFormat:@"%@ · %@ · %@", label, codecShort, sizeStr];
}

@end

#pragma mark - YTAFFormatSelector

@implementation YTAFFormatSelector

+ (nullable YTAFFormat *)bestVideoForResult:(YTAFExtractionResult *)result
                                     quality:(YTAFQualityPreference)quality
                                       codec:(YTAFCodecPreference)codec {
    NSArray<YTAFFormat *> *videos = result.videoFormats;
    if (videos.count == 0) return nil;

    // Step 1: pick target-height bucket.
    NSInteger targetHeight = 0;
    NSArray<YTAFFormat *> *bucket = nil;

    if (quality == YTAFQualityPreferenceHighest) {
        NSArray<YTAFFormat *> *sorted = [videos sortedArrayUsingComparator:^NSComparisonResult(YTAFFormat *a, YTAFFormat *b) {
            if (a.height != b.height) return a.height > b.height ? NSOrderedAscending : NSOrderedDescending;
            if (a.bitrate != b.bitrate) return a.bitrate > b.bitrate ? NSOrderedAscending : NSOrderedDescending;
            return NSOrderedSame;
        }];
        targetHeight = sorted.firstObject.height;
    } else {
        targetHeight = (NSInteger)quality;
        // exact match first
        NSMutableArray<YTAFFormat *> *exact = [NSMutableArray array];
        for (YTAFFormat *f in videos) {
            if (f.height == targetHeight) [exact addObject:f];
        }
        if (exact.count == 0) {
            // next-tallest <= target
            NSInteger bestH = 0;
            for (YTAFFormat *f in videos) {
                if (f.height <= targetHeight && f.height > bestH) bestH = f.height;
            }
            if (bestH > 0) {
                targetHeight = bestH;
            } else {
                // no format <= target; pick the smallest available
                NSInteger smallest = NSIntegerMax;
                for (YTAFFormat *f in videos) {
                    if (f.height > 0 && f.height < smallest) smallest = f.height;
                }
                if (smallest == NSIntegerMax) return nil;
                targetHeight = smallest;
            }
        }
    }

    NSMutableArray<YTAFFormat *> *atHeight = [NSMutableArray array];
    for (YTAFFormat *f in videos) {
        if (f.height == targetHeight) [atHeight addObject:f];
    }
    bucket = atHeight;
    if (bucket.count == 0) return nil;

    // Step 2: codec filter. Relax to Any if filter eliminates everything.
    NSMutableArray<YTAFFormat *> *filtered = [NSMutableArray array];
    for (YTAFFormat *f in bucket) {
        if (YTAFFormatPassesCodecFilter(f, codec)) [filtered addObject:f];
    }
    if (filtered.count == 0) {
        filtered = [bucket mutableCopy];
    }

    // Step 3-4: Prefer Premium, then bitrate desc.
    NSArray<YTAFFormat *> *sorted = [filtered sortedArrayUsingComparator:^NSComparisonResult(YTAFFormat *a, YTAFFormat *b) {
        return YTAFCompareVideoBest(a, b);
    }];
    return sorted.firstObject;
}

+ (nullable YTAFFormatPair *)selectVideoPairFromResult:(YTAFExtractionResult *)result
                                               quality:(YTAFQualityPreference)quality
                                                 codec:(YTAFCodecPreference)codec
                                          audioQuality:(YTAFAudioQualityPreference)audioQuality {
    if (result == nil) return nil;
    YTAFFormat *video = [self bestVideoForResult:result quality:quality codec:codec];
    if (video == nil) return nil;
    YTAFFormat *audio = YTAFSelectAudioFormat(result, audioQuality);

    YTAFFormatPair *pair = [[YTAFFormatPair alloc] init];
    pair.videoFormat = video;
    pair.audioFormat = audio;

    YTAGLog(@"selector", @"picked video itag=%ld %@ codec=%@ bitrate=%ld audio itag=%ld (%@)",
            (long)video.itag,
            video.qualityLabel ?: @"?",
            video.codec ?: @"?",
            (long)video.bitrate,
            (long)(audio ? audio.itag : -1),
            audio ? (audio.isDRC ? @"DRC" : @"non-DRC") : @"none");
    return pair;
}

+ (nullable YTAFFormatPair *)selectAudioPairFromResult:(YTAFExtractionResult *)result
                                          audioQuality:(YTAFAudioQualityPreference)audioQuality {
    if (result == nil) return nil;
    YTAFFormat *audio = YTAFSelectAudioFormat(result, audioQuality);
    if (audio == nil) return nil;
    YTAFFormatPair *pair = [[YTAFFormatPair alloc] init];
    pair.videoFormat = nil;
    pair.audioFormat = audio;
    YTAGLog(@"selector", @"picked audio-only itag=%ld bitrate=%ld %@",
            (long)audio.itag,
            (long)audio.bitrate,
            audio.isDRC ? @"DRC" : @"non-DRC");
    return pair;
}

+ (NSArray<YTAFFormatPair *> *)allOfferablePairsFromResult:(YTAFExtractionResult *)result
                                              audioQuality:(YTAFAudioQualityPreference)audioQuality {
    NSMutableArray<YTAFFormatPair *> *out = [NSMutableArray array];
    if (result == nil) return out;

    YTAFFormat *audio = YTAFSelectAudioFormat(result, audioQuality);

    // Group video formats by qualityLabel; for each label, pick highest-bitrate video.
    NSMutableDictionary<NSString *, YTAFFormat *> *byLabel = [NSMutableDictionary dictionary];
    NSMutableArray<YTAFFormat *> *unlabeled = [NSMutableArray array];
    for (YTAFFormat *f in result.videoFormats) {
        if (f.qualityLabel.length == 0) {
            [unlabeled addObject:f];
            continue;
        }
        YTAFFormat *existing = byLabel[f.qualityLabel];
        if (existing == nil || f.bitrate > existing.bitrate) {
            byLabel[f.qualityLabel] = f;
        }
    }

    NSArray<YTAFFormat *> *distinctVideos = byLabel.allValues;

    // Sort: height desc, Premium before non-Premium, H.264 before AV1 before VP9, then bitrate desc.
    NSArray<YTAFFormat *> *sorted = [distinctVideos sortedArrayUsingComparator:^NSComparisonResult(YTAFFormat *a, YTAFFormat *b) {
        if (a.height != b.height) return a.height > b.height ? NSOrderedAscending : NSOrderedDescending;
        BOOL ap = YTAFLabelIsPremium(a.qualityLabel);
        BOOL bp = YTAFLabelIsPremium(b.qualityLabel);
        if (ap != bp) return ap ? NSOrderedAscending : NSOrderedDescending;
        NSInteger ar = YTAFCodecSortRank(a.codec);
        NSInteger br = YTAFCodecSortRank(b.codec);
        if (ar != br) return ar < br ? NSOrderedAscending : NSOrderedDescending;
        if (a.bitrate != b.bitrate) return a.bitrate > b.bitrate ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];

    // Split formats with bad metadata (contentLength == 0) to the bottom of video rows.
    NSMutableArray<YTAFFormat *> *good = [NSMutableArray array];
    NSMutableArray<YTAFFormat *> *bad = [NSMutableArray array];
    for (YTAFFormat *f in sorted) {
        if (f.contentLength > 0) [good addObject:f];
        else [bad addObject:f];
    }

    for (YTAFFormat *f in good) {
        YTAFFormatPair *pair = [[YTAFFormatPair alloc] init];
        pair.videoFormat = f;
        pair.audioFormat = audio;
        [out addObject:pair];
    }
    for (YTAFFormat *f in bad) {
        YTAFFormatPair *pair = [[YTAFFormatPair alloc] init];
        pair.videoFormat = f;
        pair.audioFormat = audio;
        [out addObject:pair];
    }

    // Append audio-only trailer if we have any audio.
    if (audio != nil) {
        YTAFFormatPair *audioOnly = [[YTAFFormatPair alloc] init];
        audioOnly.videoFormat = nil;
        audioOnly.audioFormat = audio;
        [out addObject:audioOnly];
    }

    YTAGLog(@"selector", @"offerable pairs: %lu rows (audio itag=%ld)",
            (unsigned long)out.count,
            (long)(audio ? audio.itag : -1));
    return out;
}

@end
