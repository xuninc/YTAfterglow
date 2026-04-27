#import "YTAGURLExtractor.h"
#import "YTAGLog.h"

static NSString *const YTAGURLExtractorErrorDomain = @"YTAGURLExtractor";

#pragma mark - YTAGFormat

@implementation YTAGFormat
@end

#pragma mark - YTAGCaptionTrack

@implementation YTAGCaptionTrack
@end

#pragma mark - YTAGExtractionResult

@implementation YTAGExtractionResult

- (NSArray<YTAGFormat *> *)videoFormats {
    NSMutableArray<YTAGFormat *> *out = [NSMutableArray array];
    for (YTAGFormat *f in self.formats) {
        if (f.isVideoOnly) {
            [out addObject:f];
        }
    }
    return [out copy];
}

- (NSArray<YTAGFormat *> *)audioFormats {
    NSMutableArray<YTAGFormat *> *out = [NSMutableArray array];
    for (YTAGFormat *f in self.formats) {
        if (f.isAudioOnly) {
            [out addObject:f];
        }
    }
    return [out copy];
}

@end

#pragma mark - Helpers

/// Coerce a JSON value (which may be NSNumber or NSString) to NSInteger. Returns 0 for nil/NSNull.
static NSInteger YTAGIntegerValue(id value) {
    if (value == nil || value == [NSNull null]) return 0;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value integerValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value integerValue];
    return 0;
}

static long long YTAGLongLongValue(id value) {
    if (value == nil || value == [NSNull null]) return 0;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value longLongValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value longLongValue];
    return 0;
}

static NSString * _Nullable YTAGStringValue(id value) {
    if (value == nil || value == [NSNull null]) return nil;
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return nil;
}

static BOOL YTAGBoolValue(id value) {
    if (value == nil || value == [NSNull null]) return NO;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value boolValue];
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)value lowercaseString];
        return [s isEqualToString:@"true"] || [s isEqualToString:@"1"];
    }
    return NO;
}

/// Parse "video/mp4; codecs=\"avc1.64002A\"" -> container "mp4", codec "avc1.64002A".
static void YTAGParseMimeType(NSString * _Nullable mimeType, NSString * _Nullable * _Nullable outContainer, NSString * _Nullable * _Nullable outCodec) {
    if (outContainer) *outContainer = nil;
    if (outCodec) *outCodec = nil;
    if (mimeType.length == 0) return;

    // Container: text between '/' and ';'
    NSRange slash = [mimeType rangeOfString:@"/"];
    NSRange semi = [mimeType rangeOfString:@";"];
    if (outContainer && slash.location != NSNotFound) {
        NSUInteger start = NSMaxRange(slash);
        NSUInteger end = (semi.location != NSNotFound) ? semi.location : mimeType.length;
        if (end > start) {
            NSString *c = [[mimeType substringWithRange:NSMakeRange(start, end - start)]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (c.length > 0) *outContainer = c;
        }
    }

    // Codec: text inside codecs="..."
    if (outCodec) {
        NSRange codecsKey = [mimeType rangeOfString:@"codecs="];
        if (codecsKey.location != NSNotFound) {
            NSUInteger afterKey = NSMaxRange(codecsKey);
            if (afterKey < mimeType.length) {
                // Optional opening quote
                unichar ch = [mimeType characterAtIndex:afterKey];
                NSUInteger codecStart = (ch == '"' || ch == '\'') ? afterKey + 1 : afterKey;
                NSRange endQuote = [mimeType rangeOfString:@"\"" options:0 range:NSMakeRange(codecStart, mimeType.length - codecStart)];
                NSUInteger codecEnd = (endQuote.location != NSNotFound) ? endQuote.location : mimeType.length;
                if (codecEnd > codecStart) {
                    *outCodec = [mimeType substringWithRange:NSMakeRange(codecStart, codecEnd - codecStart)];
                }
            }
        }
    }
}

/// Detect DRC by inspecting the URL's xtags query parameter for "drc=1".
static BOOL YTAGDetectDRCFromURL(NSString * _Nullable urlString) {
    if (urlString.length == 0) return NO;
    // xtags is typically URL-encoded: xtags=drc%3D1 or xtags=acont%3Ddubbed%3Alang%3Den%3Adrc%3D1
    NSURLComponents *comps = [NSURLComponents componentsWithString:urlString];
    for (NSURLQueryItem *item in comps.queryItems) {
        if ([item.name isEqualToString:@"xtags"] && item.value.length > 0) {
            if ([item.value rangeOfString:@"drc=1"].location != NSNotFound) return YES;
        }
    }
    // Fallback: raw substring check (covers non-standard encoding).
    if ([urlString rangeOfString:@"drc%3D1"].location != NSNotFound) return YES;
    if ([urlString rangeOfString:@"drc=1"].location != NSNotFound) return YES;
    return NO;
}

/// Pick the highest-resolution thumbnail from videoDetails.thumbnail.thumbnails.
static NSString * _Nullable YTAGPickBestThumbnail(NSDictionary *videoDetails) {
    NSDictionary *thumbnail = videoDetails[@"thumbnail"];
    if (![thumbnail isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *thumbnails = thumbnail[@"thumbnails"];
    if (![thumbnails isKindOfClass:[NSArray class]] || thumbnails.count == 0) return nil;

    NSString *bestURL = nil;
    NSInteger bestArea = -1;
    for (id entry in thumbnails) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *url = YTAGStringValue(entry[@"url"]);
        NSInteger w = YTAGIntegerValue(entry[@"width"]);
        NSInteger h = YTAGIntegerValue(entry[@"height"]);
        NSInteger area = w * h;
        if (url.length > 0 && area > bestArea) {
            bestArea = area;
            bestURL = url;
        }
    }
    // If no sizes were provided, fall back to the last entry (YT orders smallest -> largest).
    if (bestURL == nil) {
        id last = thumbnails.lastObject;
        if ([last isKindOfClass:[NSDictionary class]]) {
            bestURL = YTAGStringValue(((NSDictionary *)last)[@"url"]);
        }
    }
    return bestURL;
}

#pragma mark - Live-read helpers

// Wrapper around @try/valueForKey: that returns nil on any exception rather than
// blowing up the whole extraction. YT's internal protobuf-backed classes are
// mostly KVC-compliant but a few properties throw if not set.
static id YTAGSafeValueForKey(id obj, NSString *key) {
    if (!obj || !key) return nil;
    @try { return [obj valueForKey:key]; }
    @catch (id ex) { return nil; }
}

static NSString *YTAGSafeStringValueForKey(id obj, NSString *key) {
    id v = YTAGSafeValueForKey(obj, key);
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static NSInteger YTAGSafeIntegerForKey(id obj, NSString *key) {
    id v = YTAGSafeValueForKey(obj, key);
    if ([v respondsToSelector:@selector(integerValue)]) return [v integerValue];
    return 0;
}

static long long YTAGSafeLongLongForKey(id obj, NSString *key) {
    id v = YTAGSafeValueForKey(obj, key);
    if ([v respondsToSelector:@selector(longLongValue)]) return [v longLongValue];
    return 0;
}

#pragma mark - YTAGURLExtractor

@implementation YTAGURLExtractor

+ (nullable YTAGExtractionResult *)extractFromPlayerVC:(id)playerVC {
    if (!playerVC) return nil;

    // Walk YTLite's documented path (decomp sub_361536, lines 361570-361573):
    //   [playerVC playerResponse] -> YTPlayerResponse
    //   .playerData                -> YTIPlayerResponse
    //   .streamingData             -> YTIStreamingData
    //   .adaptiveFormatsArray      -> NSArray<YTIFormatStream *>
    //
    // In YT 21.16.2 the `playerResponse` accessor has drifted — it returns nil
    // even though contentVideoID works on the same instance. Try several
    // plausible names in order before giving up.
    id playerResponse = nil;
    NSString *hitKey = nil;
    // Order matters: `contentPlayerResponse` is the accessor YT 21.16.2 actually
    // exposes (confirmed via OfflineProbe dump). The rest are historical aliases
    // kept as fallbacks in case of version drift in either direction.
    NSArray<NSString *> *responseKeys = @[
        @"contentPlayerResponse",
        @"playerResponse",
        @"_playerResponse",
        @"currentPlayerResponse",
        @"loadedPlayerResponse",
        @"activePlayerResponse",
        @"_currentPlayerResponse",
    ];
    for (NSString *key in responseKeys) {
        id v = YTAGSafeValueForKey(playerVC, key);
        if (v) { playerResponse = v; hitKey = key; break; }
    }
    // Fallback: ask the active single-video controller if the player VC doesn't
    // have it directly. YT's protobuf pipeline pushes player response into the
    // video controller on load.
    if (!playerResponse) {
        id activeVideo = YTAGSafeValueForKey(playerVC, @"activeVideo");
        for (NSString *key in responseKeys) {
            id v = YTAGSafeValueForKey(activeVideo, key);
            if (v) { playerResponse = v; hitKey = [@"activeVideo." stringByAppendingString:key]; break; }
        }
    }

    id playerData     = YTAGSafeValueForKey(playerResponse, @"playerData");
    id streamingData  = YTAGSafeValueForKey(playerData, @"streamingData");
    id adaptiveArray  = YTAGSafeValueForKey(streamingData, @"adaptiveFormatsArray");
    if (![adaptiveArray isKindOfClass:[NSArray class]]) {
        // Try alternate name
        adaptiveArray = YTAGSafeValueForKey(streamingData, @"adaptiveFormats");
    }
    if (![adaptiveArray isKindOfClass:[NSArray class]] || [(NSArray *)adaptiveArray count] == 0) {
        YTAGLog(@"extractor", @"live-read: no adaptiveFormatsArray (hitKey=%@ playerResponse=%@ playerData=%@ streamingData=%@)",
                hitKey ?: @"<nil>",
                NSStringFromClass([playerResponse class]) ?: @"<nil>",
                NSStringFromClass([playerData class]) ?: @"<nil>",
                NSStringFromClass([streamingData class]) ?: @"<nil>");
        return nil;
    }
    YTAGLog(@"extractor", @"live-read: found adaptive array via %@ (%lu formats)",
            hitKey ?: @"<unknown>", (unsigned long)[(NSArray *)adaptiveArray count]);

    YTAGExtractionResult *result = [[YTAGExtractionResult alloc] init];

    // videoID lives on YTPlayerResponse directly.
    NSString *vid = YTAGSafeStringValueForKey(playerResponse, @"videoID");
    if (!vid) vid = YTAGSafeStringValueForKey(playerResponse, @"videoId");
    if (!vid) {
        // Fallback: contentVideoID on the player VC.
        if ([playerVC respondsToSelector:@selector(contentVideoID)]) {
            vid = [playerVC performSelector:@selector(contentVideoID)];
        }
    }
    result.videoID = vid ?: @"";

    // Metadata from playerData.videoDetails.
    id videoDetails = YTAGSafeValueForKey(playerData, @"videoDetails");
    result.title            = YTAGSafeStringValueForKey(videoDetails, @"title");
    result.author           = YTAGSafeStringValueForKey(videoDetails, @"author");
    result.shortDescription = YTAGSafeStringValueForKey(videoDetails, @"shortDescription");
    result.duration = (NSTimeInterval)YTAGSafeIntegerForKey(videoDetails, @"lengthSeconds");

    // Thumbnail URL from videoDetails.thumbnail.thumbnailsArray (protobuf-backed —
    // ends in `Array` suffix in YT's generated accessors).
    id thumbnail = YTAGSafeValueForKey(videoDetails, @"thumbnail");
    id thumbArray = YTAGSafeValueForKey(thumbnail, @"thumbnailsArray");
    if (![thumbArray isKindOfClass:[NSArray class]]) {
        thumbArray = YTAGSafeValueForKey(thumbnail, @"thumbnails");
    }
    if ([thumbArray isKindOfClass:[NSArray class]]) {
        NSString *bestURL = nil;
        NSInteger bestArea = -1;
        for (id t in thumbArray) {
            NSString *u = YTAGSafeStringValueForKey(t, @"url");
            NSInteger w = YTAGSafeIntegerForKey(t, @"width");
            NSInteger h = YTAGSafeIntegerForKey(t, @"height");
            NSInteger area = w * h;
            if (u.length > 0 && area > bestArea) { bestArea = area; bestURL = u; }
        }
        if (!bestURL && [(NSArray *)thumbArray count] > 0) {
            bestURL = YTAGSafeStringValueForKey([thumbArray lastObject], @"url");
        }
        result.thumbnailURL = bestURL;
    }

    // Adaptive formats. Property names on YTIFormatStream (a GPBMessage): Apple's
    // Protobuf ObjC generator capitalizes acronyms, so the `url` protobuf field
    // becomes `URL` in Objective-C — NOT `url`. v33 used `@"url"` for KVC and
    // every live-read format returned a nil URL, which our `length > 0` filter
    // dropped — we saw "128 formats → 0 formats" in the log. Try `URL` first
    // (matches 21.16.2 behavior per YouTube_decompiled/MLFormat.c:674, YT calls
    // `-[YTIFormatStream URL]`), then `url` as a compatibility fallback for any
    // version drift.
    NSMutableArray<YTAGFormat *> *formats = [NSMutableArray array];
    for (id f in (NSArray *)adaptiveArray) {
        YTAGFormat *fmt = [[YTAGFormat alloc] init];
        fmt.itag = YTAGSafeIntegerForKey(f, @"itag");
        NSString *urlString = YTAGSafeStringValueForKey(f, @"URL");
        if (urlString.length == 0) urlString = YTAGSafeStringValueForKey(f, @"url");
        if (urlString.length == 0) {
            // GPB stores the URL as an NSURL object for some fields. Try converting.
            id urlObj = YTAGSafeValueForKey(f, @"URL") ?: YTAGSafeValueForKey(f, @"url");
            if ([urlObj isKindOfClass:[NSURL class]]) {
                urlString = [(NSURL *)urlObj absoluteString];
            }
        }
        fmt.url = urlString ?: @"";
        fmt.mimeType = YTAGSafeStringValueForKey(f, @"mimeType") ?: @"";

        NSString *container = nil;
        NSString *codec = nil;
        YTAGParseMimeType(fmt.mimeType, &container, &codec);
        fmt.container = container;
        fmt.codec = codec;

        fmt.width  = YTAGSafeIntegerForKey(f, @"width");
        fmt.height = YTAGSafeIntegerForKey(f, @"height");
        fmt.fps    = YTAGSafeIntegerForKey(f, @"fps");
        fmt.bitrate = YTAGSafeIntegerForKey(f, @"bitrate");
        fmt.contentLength = YTAGSafeLongLongForKey(f, @"contentLength");

        NSInteger approxMs = YTAGSafeIntegerForKey(f, @"approxDurationMs");
        fmt.duration = approxMs > 0 ? (NSTimeInterval)approxMs / 1000.0 : 0;

        fmt.qualityLabel = YTAGSafeStringValueForKey(f, @"qualityLabel");
        fmt.audioQuality = YTAGSafeStringValueForKey(f, @"audioQuality");
        fmt.isDRC = YTAGDetectDRCFromURL(fmt.url);
        fmt.isVideoOnly = [fmt.mimeType hasPrefix:@"video/"];
        fmt.isAudioOnly = [fmt.mimeType hasPrefix:@"audio/"];

        if (fmt.url.length > 0) [formats addObject:fmt];
    }
    result.formats = [formats copy];

    // Caption tracks from playerData.captions.playerCaptionsTracklistRenderer.captionTracksArray
    NSMutableArray<YTAGCaptionTrack *> *captions = [NSMutableArray array];
    id captionsContainer = YTAGSafeValueForKey(playerData, @"captions");
    id tracklistRenderer = YTAGSafeValueForKey(captionsContainer, @"playerCaptionsTracklistRenderer");
    id tracksArray = YTAGSafeValueForKey(tracklistRenderer, @"captionTracksArray");
    if (![tracksArray isKindOfClass:[NSArray class]]) {
        tracksArray = YTAGSafeValueForKey(tracklistRenderer, @"captionTracks");
    }
    if ([tracksArray isKindOfClass:[NSArray class]]) {
        for (id t in (NSArray *)tracksArray) {
            YTAGCaptionTrack *track = [[YTAGCaptionTrack alloc] init];
            track.baseURL = YTAGSafeStringValueForKey(t, @"baseUrl") ?: @"";
            track.languageCode = YTAGSafeStringValueForKey(t, @"languageCode") ?: @"";
            // Display name may be under .name.simpleText or .name.runs[0].text.
            id name = YTAGSafeValueForKey(t, @"name");
            track.displayName = YTAGSafeStringValueForKey(name, @"simpleText");
            NSString *kind = YTAGSafeStringValueForKey(t, @"kind");
            track.isAutoGenerated = [kind isEqualToString:@"asr"];
            if (track.baseURL.length > 0) [captions addObject:track];
        }
    }
    result.captionTracks = [captions copy];

    YTAGLog(@"extractor", @"live-read: videoID=%@ title=%@ formats=%lu captions=%lu",
            result.videoID, result.title ?: @"<nil>",
            (unsigned long)formats.count, (unsigned long)captions.count);
    return result;
}

+ (void)extractVideoID:(NSString *)videoID
              clientID:(YTAGClientID)clientID
            completion:(YTAGExtractionCompletion)completion {
    if (completion == nil) return;

    if (videoID.length == 0) {
        NSError *err = [NSError errorWithDomain:YTAGURLExtractorErrorDomain
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Missing videoID"}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
        return;
    }

    NSString *innertubeKey;
    NSString *clientName;
    NSString *clientVersion;
    NSString *deviceModel = nil;

    NSString *osVersion = nil;
    switch (clientID) {
        case YTAGClientIDMediaConnect:
            innertubeKey = @"AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w";
            clientName = @"MEDIA_CONNECT_FRONTEND";
            clientVersion = @"0.1";
            break;
        case YTAGClientIDTVEmbed:
            innertubeKey = @"AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";
            clientName = @"TVHTML5_SIMPLY_EMBEDDED_PLAYER";
            clientVersion = @"2.0";
            break;
        case YTAGClientIDiOS:
        default:
            innertubeKey = @"AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc";
            clientName = @"IOS";
            clientVersion = @"21.15.5";
            deviceModel = @"iPhone17,3";
            // YT gates higher-tier formats (1080p+, VP9/AV1) on osVersion being
            // set. Current iOS release works; using the beta-safe 18.5 string
            // matches what real iOS clients report.
            osVersion = @"18.5.0.22F76";
            break;
    }

    NSLocale *locale = [NSLocale currentLocale];
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode] ?: @"US";

    NSMutableDictionary *client = [NSMutableDictionary dictionary];
    client[@"hl"] = @"en";
    client[@"gl"] = countryCode;
    client[@"clientName"] = clientName;
    client[@"clientVersion"] = clientVersion;
    if (deviceModel) client[@"deviceModel"] = deviceModel;
    if (osVersion)   client[@"osVersion"] = osVersion;

    NSDictionary *body = @{
        @"context": @{ @"client": client },
        @"contentCheckOk": @YES,
        @"racyCheckOk": @YES,
        @"videoId": videoID,
    };

    NSError *jsonErr = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (bodyData == nil) {
        NSError *err = [NSError errorWithDomain:YTAGURLExtractorErrorDomain
                                           code:-2
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to serialize request body: %@", jsonErr.localizedDescription ?: @"unknown"]}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/player?key=%@&prettyPrint=false", innertubeKey];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = bodyData;

    YTAGLog(@"extractor", @"POST /player videoID=%@ client=%@", videoID, clientName);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        void (^finish)(YTAGExtractionResult *, NSError *) = ^(YTAGExtractionResult *r, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(r, e); });
        };

        if (error) {
            YTAGLog(@"extractor", @"network error: %@", error.localizedDescription);
            finish(nil, error);
            return;
        }
        if (data == nil) {
            NSError *err = [NSError errorWithDomain:YTAGURLExtractorErrorDomain
                                               code:-3
                                           userInfo:@{NSLocalizedDescriptionKey: @"Empty response body"}];
            finish(nil, err);
            return;
        }

        NSError *parseErr = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseErr];
        if (![parsed isKindOfClass:[NSDictionary class]]) {
            NSString *msg = parseErr ? [NSString stringWithFormat:@"JSON parse failed: %@", parseErr.localizedDescription] : @"Malformed JSON response";
            NSError *err = [NSError errorWithDomain:YTAGURLExtractorErrorDomain
                                               code:-4
                                           userInfo:@{NSLocalizedDescriptionKey: msg}];
            YTAGLog(@"extractor", @"%@", msg);
            finish(nil, err);
            return;
        }

        NSDictionary *json = (NSDictionary *)parsed;

        // playabilityStatus check
        NSDictionary *playability = json[@"playabilityStatus"];
        if ([playability isKindOfClass:[NSDictionary class]]) {
            NSString *status = YTAGStringValue(playability[@"status"]);
            if (status.length > 0 && ![status isEqualToString:@"OK"]) {
                NSString *reason = YTAGStringValue(playability[@"reason"]) ?: [NSString stringWithFormat:@"Video not playable (%@)", status];
                NSError *err = [NSError errorWithDomain:YTAGURLExtractorErrorDomain
                                                   code:-5
                                               userInfo:@{NSLocalizedDescriptionKey: reason}];
                YTAGLog(@"extractor", @"playabilityStatus=%@ reason=%@", status, reason);
                finish(nil, err);
                return;
            }
        }

        YTAGExtractionResult *result = [[YTAGExtractionResult alloc] init];
        result.videoID = videoID;

        NSDictionary *videoDetails = json[@"videoDetails"];
        if ([videoDetails isKindOfClass:[NSDictionary class]]) {
            result.title = YTAGStringValue(videoDetails[@"title"]);
            result.author = YTAGStringValue(videoDetails[@"author"]);
            result.shortDescription = YTAGStringValue(videoDetails[@"shortDescription"]);
            result.duration = (NSTimeInterval)YTAGIntegerValue(videoDetails[@"lengthSeconds"]);
            result.thumbnailURL = YTAGPickBestThumbnail(videoDetails);
        }

        NSMutableArray<YTAGCaptionTrack *> *captionTracks = [NSMutableArray array];
        NSDictionary *captions = json[@"captions"];
        if ([captions isKindOfClass:[NSDictionary class]]) {
            NSDictionary *tracklist = captions[@"playerCaptionsTracklistRenderer"];
            NSArray *tracks = [tracklist isKindOfClass:[NSDictionary class]] ? tracklist[@"captionTracks"] : nil;
            if ([tracks isKindOfClass:[NSArray class]]) {
                for (id entry in tracks) {
                    if (![entry isKindOfClass:[NSDictionary class]]) continue;
                    NSDictionary *t = (NSDictionary *)entry;
                    YTAGCaptionTrack *track = [[YTAGCaptionTrack alloc] init];
                    track.baseURL = YTAGStringValue(t[@"baseUrl"]) ?: @"";
                    track.languageCode = YTAGStringValue(t[@"languageCode"]) ?: @"";
                    NSDictionary *nameDict = t[@"name"];
                    if ([nameDict isKindOfClass:[NSDictionary class]]) {
                        track.displayName = YTAGStringValue(nameDict[@"simpleText"]);
                    }
                    NSString *kind = YTAGStringValue(t[@"kind"]);
                    track.isAutoGenerated = [kind isEqualToString:@"asr"];
                    if (track.baseURL.length > 0) [captionTracks addObject:track];
                }
            }
        }
        result.captionTracks = [captionTracks copy];

        NSMutableArray<YTAGFormat *> *formats = [NSMutableArray array];
        NSDictionary *streamingData = json[@"streamingData"];
        if ([streamingData isKindOfClass:[NSDictionary class]]) {
            NSArray *adaptive = streamingData[@"adaptiveFormats"];
            if ([adaptive isKindOfClass:[NSArray class]]) {
                for (id entry in adaptive) {
                    if (![entry isKindOfClass:[NSDictionary class]]) continue;
                    NSDictionary *f = (NSDictionary *)entry;

                    YTAGFormat *fmt = [[YTAGFormat alloc] init];
                    fmt.itag = YTAGIntegerValue(f[@"itag"]);
                    fmt.url = YTAGStringValue(f[@"url"]) ?: @"";
                    fmt.mimeType = YTAGStringValue(f[@"mimeType"]) ?: @"";

                    NSString *container = nil;
                    NSString *codec = nil;
                    YTAGParseMimeType(fmt.mimeType, &container, &codec);
                    fmt.container = container;
                    fmt.codec = codec;

                    fmt.width = YTAGIntegerValue(f[@"width"]);
                    fmt.height = YTAGIntegerValue(f[@"height"]);
                    fmt.fps = YTAGIntegerValue(f[@"fps"]);
                    fmt.bitrate = YTAGIntegerValue(f[@"bitrate"]);
                    fmt.contentLength = YTAGLongLongValue(f[@"contentLength"]);

                    NSInteger approxMs = YTAGIntegerValue(f[@"approxDurationMs"]);
                    fmt.duration = approxMs > 0 ? (NSTimeInterval)approxMs / 1000.0 : 0;

                    fmt.qualityLabel = YTAGStringValue(f[@"qualityLabel"]);
                    fmt.audioQuality = YTAGStringValue(f[@"audioQuality"]);

                    BOOL drcFromJSON = YTAGBoolValue(f[@"isDrc"]);
                    BOOL drcFromURL = YTAGDetectDRCFromURL(fmt.url);
                    fmt.isDRC = drcFromJSON || drcFromURL;

                    fmt.isVideoOnly = [fmt.mimeType hasPrefix:@"video/"];
                    fmt.isAudioOnly = [fmt.mimeType hasPrefix:@"audio/"];

                    [formats addObject:fmt];
                }
            }
        }
        result.formats = [formats copy];

        YTAGLog(@"extractor", @"parsed %lu formats (title=%@) client=%@",
                (unsigned long)formats.count, result.title ?: @"<nil>", clientName);

        // Summarize which resolutions + codecs came back so we can diagnose the
        // "only 720p offered" case without a full network trace.
        NSMutableArray<NSString *> *resSummary = [NSMutableArray array];
        for (YTAGFormat *f in formats) {
            if (f.isVideoOnly && f.qualityLabel.length > 0) {
                [resSummary addObject:[NSString stringWithFormat:@"%@/%@",
                                       f.qualityLabel,
                                       f.codec ?: f.container ?: @"?"]];
            }
        }
        if (resSummary.count > 0) {
            YTAGLog(@"extractor", @"video rungs: %@",
                    [resSummary componentsJoinedByString:@", "]);
        }

        // Client-rotation fallback, mirroring yt-dlp's strategy. Order: TV-embed
        // (default, returns URLs without tight IP/UA binding) → IOS (higher-tier
        // formats, tight-bound URLs that often 403 when replayed) → MediaConnect
        // (transcoding pipeline client, also loose binding). First one to return
        // >0 formats wins.
        if (formats.count == 0) {
            NSString *playabilityStatus = @"<no playabilityStatus>";
            if ([playability isKindOfClass:[NSDictionary class]]) {
                NSString *s = YTAGStringValue(playability[@"status"]);
                NSString *r = YTAGStringValue(playability[@"reason"]);
                playabilityStatus = [NSString stringWithFormat:@"status=%@ reason=%@", s ?: @"?", r ?: @"(none)"];
            }
            YTAGClientID nextClient = (YTAGClientID)-1;
            if (clientID == YTAGClientIDTVEmbed)      nextClient = YTAGClientIDiOS;
            else if (clientID == YTAGClientIDiOS)     nextClient = YTAGClientIDMediaConnect;
            if ((int)nextClient >= 0) {
                YTAGLog(@"extractor", @"0 formats on client=%d (%@) — rotating to client=%d",
                        (int)clientID, playabilityStatus, (int)nextClient);
                [YTAGURLExtractor extractVideoID:videoID
                                        clientID:nextClient
                                      completion:completion];
                return;
            }
            YTAGLog(@"extractor", @"all clients exhausted with 0 formats — %@", playabilityStatus);
        }

        finish(result, nil);
    }];
    [task resume];
}

@end
