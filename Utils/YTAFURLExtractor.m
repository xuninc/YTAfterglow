#import "YTAFURLExtractor.h"
#import "YTAGLog.h"

static NSString *const YTAFURLExtractorErrorDomain = @"YTAFURLExtractor";

#pragma mark - YTAFFormat

@implementation YTAFFormat
@end

#pragma mark - YTAFExtractionResult

@implementation YTAFExtractionResult

- (NSArray<YTAFFormat *> *)videoFormats {
    NSMutableArray<YTAFFormat *> *out = [NSMutableArray array];
    for (YTAFFormat *f in self.formats) {
        if (f.isVideoOnly) {
            [out addObject:f];
        }
    }
    return [out copy];
}

- (NSArray<YTAFFormat *> *)audioFormats {
    NSMutableArray<YTAFFormat *> *out = [NSMutableArray array];
    for (YTAFFormat *f in self.formats) {
        if (f.isAudioOnly) {
            [out addObject:f];
        }
    }
    return [out copy];
}

@end

#pragma mark - Helpers

/// Coerce a JSON value (which may be NSNumber or NSString) to NSInteger. Returns 0 for nil/NSNull.
static NSInteger YTAFIntegerValue(id value) {
    if (value == nil || value == [NSNull null]) return 0;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value integerValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value integerValue];
    return 0;
}

static long long YTAFLongLongValue(id value) {
    if (value == nil || value == [NSNull null]) return 0;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value longLongValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value longLongValue];
    return 0;
}

static NSString * _Nullable YTAFStringValue(id value) {
    if (value == nil || value == [NSNull null]) return nil;
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return nil;
}

static BOOL YTAFBoolValue(id value) {
    if (value == nil || value == [NSNull null]) return NO;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value boolValue];
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)value lowercaseString];
        return [s isEqualToString:@"true"] || [s isEqualToString:@"1"];
    }
    return NO;
}

/// Parse "video/mp4; codecs=\"avc1.64002A\"" -> container "mp4", codec "avc1.64002A".
static void YTAFParseMimeType(NSString * _Nullable mimeType, NSString * _Nullable * _Nullable outContainer, NSString * _Nullable * _Nullable outCodec) {
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
static BOOL YTAFDetectDRCFromURL(NSString * _Nullable urlString) {
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
static NSString * _Nullable YTAFPickBestThumbnail(NSDictionary *videoDetails) {
    NSDictionary *thumbnail = videoDetails[@"thumbnail"];
    if (![thumbnail isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *thumbnails = thumbnail[@"thumbnails"];
    if (![thumbnails isKindOfClass:[NSArray class]] || thumbnails.count == 0) return nil;

    NSString *bestURL = nil;
    NSInteger bestArea = -1;
    for (id entry in thumbnails) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *url = YTAFStringValue(entry[@"url"]);
        NSInteger w = YTAFIntegerValue(entry[@"width"]);
        NSInteger h = YTAFIntegerValue(entry[@"height"]);
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
            bestURL = YTAFStringValue(((NSDictionary *)last)[@"url"]);
        }
    }
    return bestURL;
}

#pragma mark - YTAFURLExtractor

@implementation YTAFURLExtractor

+ (void)extractVideoID:(NSString *)videoID
              clientID:(YTAFClientID)clientID
            completion:(YTAFExtractionCompletion)completion {
    if (completion == nil) return;

    if (videoID.length == 0) {
        NSError *err = [NSError errorWithDomain:YTAFURLExtractorErrorDomain
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Missing videoID"}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
        return;
    }

    NSString *innertubeKey;
    NSString *clientName;
    NSString *clientVersion;
    NSString *deviceModel = nil;

    switch (clientID) {
        case YTAFClientIDMediaConnect:
            innertubeKey = @"AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w";
            clientName = @"MEDIA_CONNECT_FRONTEND";
            clientVersion = @"0.1";
            break;
        case YTAFClientIDiOS:
        default:
            innertubeKey = @"AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc";
            clientName = @"IOS";
            clientVersion = @"19.09.3";
            deviceModel = @"iPhone14,3";
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

    NSDictionary *body = @{
        @"context": @{ @"client": client },
        @"contentCheckOk": @YES,
        @"racyCheckOk": @YES,
        @"videoId": videoID,
    };

    NSError *jsonErr = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (bodyData == nil) {
        NSError *err = [NSError errorWithDomain:YTAFURLExtractorErrorDomain
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
        void (^finish)(YTAFExtractionResult *, NSError *) = ^(YTAFExtractionResult *r, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(r, e); });
        };

        if (error) {
            YTAGLog(@"extractor", @"network error: %@", error.localizedDescription);
            finish(nil, error);
            return;
        }
        if (data == nil) {
            NSError *err = [NSError errorWithDomain:YTAFURLExtractorErrorDomain
                                               code:-3
                                           userInfo:@{NSLocalizedDescriptionKey: @"Empty response body"}];
            finish(nil, err);
            return;
        }

        NSError *parseErr = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseErr];
        if (![parsed isKindOfClass:[NSDictionary class]]) {
            NSString *msg = parseErr ? [NSString stringWithFormat:@"JSON parse failed: %@", parseErr.localizedDescription] : @"Malformed JSON response";
            NSError *err = [NSError errorWithDomain:YTAFURLExtractorErrorDomain
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
            NSString *status = YTAFStringValue(playability[@"status"]);
            if (status.length > 0 && ![status isEqualToString:@"OK"]) {
                NSString *reason = YTAFStringValue(playability[@"reason"]) ?: [NSString stringWithFormat:@"Video not playable (%@)", status];
                NSError *err = [NSError errorWithDomain:YTAFURLExtractorErrorDomain
                                                   code:-5
                                               userInfo:@{NSLocalizedDescriptionKey: reason}];
                YTAGLog(@"extractor", @"playabilityStatus=%@ reason=%@", status, reason);
                finish(nil, err);
                return;
            }
        }

        YTAFExtractionResult *result = [[YTAFExtractionResult alloc] init];
        result.videoID = videoID;

        NSDictionary *videoDetails = json[@"videoDetails"];
        if ([videoDetails isKindOfClass:[NSDictionary class]]) {
            result.title = YTAFStringValue(videoDetails[@"title"]);
            result.author = YTAFStringValue(videoDetails[@"author"]);
            result.duration = (NSTimeInterval)YTAFIntegerValue(videoDetails[@"lengthSeconds"]);
            result.thumbnailURL = YTAFPickBestThumbnail(videoDetails);
        }

        NSMutableArray<YTAFFormat *> *formats = [NSMutableArray array];
        NSDictionary *streamingData = json[@"streamingData"];
        if ([streamingData isKindOfClass:[NSDictionary class]]) {
            NSArray *adaptive = streamingData[@"adaptiveFormats"];
            if ([adaptive isKindOfClass:[NSArray class]]) {
                for (id entry in adaptive) {
                    if (![entry isKindOfClass:[NSDictionary class]]) continue;
                    NSDictionary *f = (NSDictionary *)entry;

                    YTAFFormat *fmt = [[YTAFFormat alloc] init];
                    fmt.itag = YTAFIntegerValue(f[@"itag"]);
                    fmt.url = YTAFStringValue(f[@"url"]) ?: @"";
                    fmt.mimeType = YTAFStringValue(f[@"mimeType"]) ?: @"";

                    NSString *container = nil;
                    NSString *codec = nil;
                    YTAFParseMimeType(fmt.mimeType, &container, &codec);
                    fmt.container = container;
                    fmt.codec = codec;

                    fmt.width = YTAFIntegerValue(f[@"width"]);
                    fmt.height = YTAFIntegerValue(f[@"height"]);
                    fmt.fps = YTAFIntegerValue(f[@"fps"]);
                    fmt.bitrate = YTAFIntegerValue(f[@"bitrate"]);
                    fmt.contentLength = YTAFLongLongValue(f[@"contentLength"]);

                    NSInteger approxMs = YTAFIntegerValue(f[@"approxDurationMs"]);
                    fmt.duration = approxMs > 0 ? (NSTimeInterval)approxMs / 1000.0 : 0;

                    fmt.qualityLabel = YTAFStringValue(f[@"qualityLabel"]);
                    fmt.audioQuality = YTAFStringValue(f[@"audioQuality"]);

                    BOOL drcFromJSON = YTAFBoolValue(f[@"isDrc"]);
                    BOOL drcFromURL = YTAFDetectDRCFromURL(fmt.url);
                    fmt.isDRC = drcFromJSON || drcFromURL;

                    fmt.isVideoOnly = [fmt.mimeType hasPrefix:@"video/"];
                    fmt.isAudioOnly = [fmt.mimeType hasPrefix:@"audio/"];

                    [formats addObject:fmt];
                }
            }
        }
        result.formats = [formats copy];

        YTAGLog(@"extractor", @"parsed %lu formats (title=%@)", (unsigned long)formats.count, result.title ?: @"<nil>");
        finish(result, nil);
    }];
    [task resume];
}

@end
