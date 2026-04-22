#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAFClientID) {
    YTAFClientIDiOS = 0,                   // clientName "IOS"
    YTAFClientIDMediaConnect = 1,          // clientName "MEDIA_CONNECT_FRONTEND" — exposes itag 141 (AAC 256k Premium)
};

/// Represents a single adaptive format from YT's /player response.
@interface YTAFFormat : NSObject
@property (nonatomic, assign) NSInteger itag;
@property (nonatomic, copy)   NSString *url;
@property (nonatomic, copy)   NSString *mimeType;       // e.g. "video/mp4; codecs=\"avc1.64002A\""
@property (nonatomic, copy, nullable) NSString *codec;  // parsed out of mimeType, e.g. "avc1.64002A"
@property (nonatomic, copy, nullable) NSString *container; // "mp4" / "webm" / "m4a"
@property (nonatomic, assign) NSInteger width;          // 0 for audio
@property (nonatomic, assign) NSInteger height;         // 0 for audio
@property (nonatomic, assign) NSInteger fps;            // 0 for audio
@property (nonatomic, assign) NSInteger bitrate;
@property (nonatomic, assign) long long contentLength;  // clen param
@property (nonatomic, assign) NSTimeInterval duration;  // from approxDurationMs
@property (nonatomic, copy, nullable) NSString *qualityLabel; // "1080p60", "1080p60 Premium", etc.
@property (nonatomic, copy, nullable) NSString *audioQuality; // e.g. "AUDIO_QUALITY_MEDIUM"
@property (nonatomic, assign) BOOL isDRC;               // xtags=drc=1
@property (nonatomic, assign) BOOL isVideoOnly;         // true if mimeType starts with "video/"
@property (nonatomic, assign) BOOL isAudioOnly;         // true if mimeType starts with "audio/"
@end

/// Result envelope.
@interface YTAFExtractionResult : NSObject
@property (nonatomic, copy) NSString *videoID;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, copy, nullable) NSString *thumbnailURL; // highest-res thumbnail
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSArray<YTAFFormat *> *formats;   // all adaptive formats
// Convenience filtered arrays:
@property (nonatomic, readonly) NSArray<YTAFFormat *> *videoFormats;
@property (nonatomic, readonly) NSArray<YTAFFormat *> *audioFormats;
@end

typedef void (^YTAFExtractionCompletion)(YTAFExtractionResult * _Nullable result, NSError * _Nullable error);

@interface YTAFURLExtractor : NSObject

/// Async POST to /youtubei/v1/player. Completion fires on the main queue.
+ (void)extractVideoID:(NSString *)videoID
              clientID:(YTAFClientID)clientID
            completion:(YTAFExtractionCompletion)completion;

@end

NS_ASSUME_NONNULL_END
