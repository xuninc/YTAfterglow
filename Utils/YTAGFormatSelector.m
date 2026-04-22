#import "YTAGFormatSelector.h"
#import "YTAGURLExtractor.h"
#import "YTAGLog.h"

#pragma mark - Helpers

static BOOL YTAGLabelIsPremium(NSString * _Nullable label) {
    if (label.length == 0) return NO;
    return [label rangeOfString:@"Premium" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL YTAGCodecMatchesH264(NSString * _Nullable codec) {
    return codec.length > 0 && [codec hasPrefix:@"avc1."];
}

static BOOL YTAGCodecMatchesAV1(NSString * _Nullable codec) {
    return codec.length > 0 && [codec hasPrefix:@"av01."];
}

static BOOL YTAGCodecMatchesVP9(NSString * _Nullable codec) {
    if (codec.length == 0) return NO;
    return [codec isEqualToString:@"vp9"] || [codec hasPrefix:@"vp09."];
}

static BOOL YTAGFormatPassesCodecFilter(YTAGFormat *f, YTAGCodecPreference codec) {
    switch (codec) {
        case YTAGCodecPreferenceH264: return YTAGCodecMatchesH264(f.codec);
        case YTAGCodecPreferenceAV1:  return YTAGCodecMatchesAV1(f.codec);
        case YTAGCodecPreferenceVP9:  return YTAGCodecMatchesVP9(f.codec);
        case YTAGCodecPreferenceAny:  return YES;
    }
    return YES;
}

/// Ordering index for codec, smaller = preferred in YTLite's picker ordering.
static NSInteger YTAGCodecSortRank(NSString * _Nullable codec) {
    if (YTAGCodecMatchesH264(codec)) return 0; // H.264 first
    if (YTAGCodecMatchesAV1(codec))  return 1;
    if (YTAGCodecMatchesVP9(codec))  return 2;
    return 3;
}

static NSString *YTAGCodecShortName(NSString * _Nullable codec, NSString * _Nullable container) {
    if (YTAGCodecMatchesH264(codec)) return @"H.264";
    if (YTAGCodecMatchesAV1(codec))  return @"AV1";
    if (YTAGCodecMatchesVP9(codec))  return @"VP9";
    if (container.length > 0)        return container;
    return @"Video";
}

static NSString *YTAGSizeString(long long bytes) {
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
static YTAGFormat * _Nullable YTAGPreferDRC(NSArray<YTAGFormat *> *candidates) {
    if (candidates.count == 0) return nil;
    YTAGFormat *drc = nil;
    YTAGFormat *nonDRC = nil;
    for (YTAGFormat *f in candidates) {
        if (f.isDRC && drc == nil) drc = f;
        else if (!f.isDRC && nonDRC == nil) nonDRC = f;
    }
    return drc ?: nonDRC ?: candidates.firstObject;
}

static NSArray<YTAGFormat *> *YTAGFormatsWithItag(NSArray<YTAGFormat *> *formats, NSInteger itag) {
    NSMutableArray<YTAGFormat *> *out = [NSMutableArray array];
    for (YTAGFormat *f in formats) {
        if (f.itag == itag) [out addObject:f];
    }
    return out;
}

static YTAGFormat * _Nullable YTAGSelectAudioFormat(YTAGExtractionResult *result,
                                                    YTAGAudioQualityPreference pref) {
    NSArray<YTAGFormat *> *audios = result.audioFormats;
    if (audios.count == 0) return nil;

    if (pref == YTAGAudioQualityHigh) {
        NSArray<YTAGFormat *> *i141 = YTAGFormatsWithItag(audios, 141);
        YTAGFormat *pick = YTAGPreferDRC(i141);
        if (pick) return pick;
        NSArray<YTAGFormat *> *i140 = YTAGFormatsWithItag(audios, 140);
        pick = YTAGPreferDRC(i140);
        if (pick) return pick;
        // fallback: highest-bitrate audio
        NSArray<YTAGFormat *> *sorted = [audios sortedArrayUsingComparator:^NSComparisonResult(YTAGFormat *a, YTAGFormat *b) {
            if (a.bitrate == b.bitrate) return NSOrderedSame;
            return a.bitrate > b.bitrate ? NSOrderedAscending : NSOrderedDescending;
        }];
        return sorted.firstObject;
    }

    // Standard
    NSArray<YTAGFormat *> *i140 = YTAGFormatsWithItag(audios, 140);
    YTAGFormat *pick = YTAGPreferDRC(i140);
    if (pick) return pick;
    return audios.firstObject;
}

/// Comparator for "best video" within a candidate set at a single resolution bucket:
/// Premium before non-Premium, then higher bitrate.
static NSComparisonResult YTAGCompareVideoBest(YTAGFormat *a, YTAGFormat *b) {
    BOOL ap = YTAGLabelIsPremium(a.qualityLabel);
    BOOL bp = YTAGLabelIsPremium(b.qualityLabel);
    if (ap != bp) return ap ? NSOrderedAscending : NSOrderedDescending;
    if (a.bitrate != b.bitrate) return a.bitrate > b.bitrate ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
}

#pragma mark - YTAGFormatPair

@implementation YTAGFormatPair

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
    NSString *sizeStr = YTAGSizeString(size);
    if (_videoFormat == nil) {
        return [NSString stringWithFormat:@"Audio only · %@", sizeStr];
    }
    NSString *label = _videoFormat.qualityLabel.length > 0 ? _videoFormat.qualityLabel : @"Video";
    NSString *codecShort = YTAGCodecShortName(_videoFormat.codec, _videoFormat.container);
    return [NSString stringWithFormat:@"%@ · %@ · %@", label, codecShort, sizeStr];
}

@end

#pragma mark - YTAGFormatSelector

@implementation YTAGFormatSelector

+ (nullable YTAGFormat *)bestVideoForResult:(YTAGExtractionResult *)result
                                     quality:(YTAGQualityPreference)quality
                                       codec:(YTAGCodecPreference)codec {
    NSArray<YTAGFormat *> *videos = result.videoFormats;
    if (videos.count == 0) return nil;

    // Step 1: pick target-height bucket.
    NSInteger targetHeight = 0;
    NSArray<YTAGFormat *> *bucket = nil;

    if (quality == YTAGQualityPreferenceHighest) {
        NSArray<YTAGFormat *> *sorted = [videos sortedArrayUsingComparator:^NSComparisonResult(YTAGFormat *a, YTAGFormat *b) {
            if (a.height != b.height) return a.height > b.height ? NSOrderedAscending : NSOrderedDescending;
            if (a.bitrate != b.bitrate) return a.bitrate > b.bitrate ? NSOrderedAscending : NSOrderedDescending;
            return NSOrderedSame;
        }];
        targetHeight = sorted.firstObject.height;
    } else {
        targetHeight = (NSInteger)quality;
        // exact match first
        NSMutableArray<YTAGFormat *> *exact = [NSMutableArray array];
        for (YTAGFormat *f in videos) {
            if (f.height == targetHeight) [exact addObject:f];
        }
        if (exact.count == 0) {
            // next-tallest <= target
            NSInteger bestH = 0;
            for (YTAGFormat *f in videos) {
                if (f.height <= targetHeight && f.height > bestH) bestH = f.height;
            }
            if (bestH > 0) {
                targetHeight = bestH;
            } else {
                // no format <= target; pick the smallest available
                NSInteger smallest = NSIntegerMax;
                for (YTAGFormat *f in videos) {
                    if (f.height > 0 && f.height < smallest) smallest = f.height;
                }
                if (smallest == NSIntegerMax) return nil;
                targetHeight = smallest;
            }
        }
    }

    NSMutableArray<YTAGFormat *> *atHeight = [NSMutableArray array];
    for (YTAGFormat *f in videos) {
        if (f.height == targetHeight) [atHeight addObject:f];
    }
    bucket = atHeight;
    if (bucket.count == 0) return nil;

    // Step 2: codec filter. Relax to Any if filter eliminates everything.
    NSMutableArray<YTAGFormat *> *filtered = [NSMutableArray array];
    for (YTAGFormat *f in bucket) {
        if (YTAGFormatPassesCodecFilter(f, codec)) [filtered addObject:f];
    }
    if (filtered.count == 0) {
        filtered = [bucket mutableCopy];
    }

    // Step 3-4: Prefer Premium, then bitrate desc.
    NSArray<YTAGFormat *> *sorted = [filtered sortedArrayUsingComparator:^NSComparisonResult(YTAGFormat *a, YTAGFormat *b) {
        return YTAGCompareVideoBest(a, b);
    }];
    return sorted.firstObject;
}

+ (nullable YTAGFormatPair *)selectVideoPairFromResult:(YTAGExtractionResult *)result
                                               quality:(YTAGQualityPreference)quality
                                                 codec:(YTAGCodecPreference)codec
                                          audioQuality:(YTAGAudioQualityPreference)audioQuality {
    if (result == nil) return nil;
    YTAGFormat *video = [self bestVideoForResult:result quality:quality codec:codec];
    if (video == nil) return nil;
    YTAGFormat *audio = YTAGSelectAudioFormat(result, audioQuality);

    YTAGFormatPair *pair = [[YTAGFormatPair alloc] init];
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

+ (nullable YTAGFormatPair *)selectAudioPairFromResult:(YTAGExtractionResult *)result
                                          audioQuality:(YTAGAudioQualityPreference)audioQuality {
    if (result == nil) return nil;
    YTAGFormat *audio = YTAGSelectAudioFormat(result, audioQuality);
    if (audio == nil) return nil;
    YTAGFormatPair *pair = [[YTAGFormatPair alloc] init];
    pair.videoFormat = nil;
    pair.audioFormat = audio;
    YTAGLog(@"selector", @"picked audio-only itag=%ld bitrate=%ld %@",
            (long)audio.itag,
            (long)audio.bitrate,
            audio.isDRC ? @"DRC" : @"non-DRC");
    return pair;
}

+ (NSArray<YTAGFormatPair *> *)allOfferablePairsFromResult:(YTAGExtractionResult *)result
                                              audioQuality:(YTAGAudioQualityPreference)audioQuality {
    NSMutableArray<YTAGFormatPair *> *out = [NSMutableArray array];
    if (result == nil) return out;

    YTAGFormat *audio = YTAGSelectAudioFormat(result, audioQuality);

    // Group video formats by qualityLabel; for each label, pick highest-bitrate video.
    NSMutableDictionary<NSString *, YTAGFormat *> *byLabel = [NSMutableDictionary dictionary];
    NSMutableArray<YTAGFormat *> *unlabeled = [NSMutableArray array];
    for (YTAGFormat *f in result.videoFormats) {
        if (f.qualityLabel.length == 0) {
            [unlabeled addObject:f];
            continue;
        }
        YTAGFormat *existing = byLabel[f.qualityLabel];
        if (existing == nil || f.bitrate > existing.bitrate) {
            byLabel[f.qualityLabel] = f;
        }
    }

    NSArray<YTAGFormat *> *distinctVideos = byLabel.allValues;

    // Sort: height desc, Premium before non-Premium, H.264 before AV1 before VP9, then bitrate desc.
    NSArray<YTAGFormat *> *sorted = [distinctVideos sortedArrayUsingComparator:^NSComparisonResult(YTAGFormat *a, YTAGFormat *b) {
        if (a.height != b.height) return a.height > b.height ? NSOrderedAscending : NSOrderedDescending;
        BOOL ap = YTAGLabelIsPremium(a.qualityLabel);
        BOOL bp = YTAGLabelIsPremium(b.qualityLabel);
        if (ap != bp) return ap ? NSOrderedAscending : NSOrderedDescending;
        NSInteger ar = YTAGCodecSortRank(a.codec);
        NSInteger br = YTAGCodecSortRank(b.codec);
        if (ar != br) return ar < br ? NSOrderedAscending : NSOrderedDescending;
        if (a.bitrate != b.bitrate) return a.bitrate > b.bitrate ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];

    // Split formats with bad metadata (contentLength == 0) to the bottom of video rows.
    NSMutableArray<YTAGFormat *> *good = [NSMutableArray array];
    NSMutableArray<YTAGFormat *> *bad = [NSMutableArray array];
    for (YTAGFormat *f in sorted) {
        if (f.contentLength > 0) [good addObject:f];
        else [bad addObject:f];
    }

    for (YTAGFormat *f in good) {
        YTAGFormatPair *pair = [[YTAGFormatPair alloc] init];
        pair.videoFormat = f;
        pair.audioFormat = audio;
        [out addObject:pair];
    }
    for (YTAGFormat *f in bad) {
        YTAGFormatPair *pair = [[YTAGFormatPair alloc] init];
        pair.videoFormat = f;
        pair.audioFormat = audio;
        [out addObject:pair];
    }

    // Append audio-only trailer if we have any audio.
    if (audio != nil) {
        YTAGFormatPair *audioOnly = [[YTAGFormatPair alloc] init];
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
