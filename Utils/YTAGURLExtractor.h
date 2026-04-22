#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAGClientID) {
    YTAGClientIDiOS = 0,                   // clientName "IOS"
    YTAGClientIDMediaConnect = 1,          // clientName "MEDIA_CONNECT_FRONTEND" — exposes itag 141 (AAC 256k Premium)
};

/// Represents a single adaptive format from YT's /player response.
@interface YTAGFormat : NSObject
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
@interface YTAGExtractionResult : NSObject
@property (nonatomic, copy) NSString *videoID;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, copy, nullable) NSString *thumbnailURL; // highest-res thumbnail
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSArray<YTAGFormat *> *formats;   // all adaptive formats
// Convenience filtered arrays:
@property (nonatomic, readonly) NSArray<YTAGFormat *> *videoFormats;
@property (nonatomic, readonly) NSArray<YTAGFormat *> *audioFormats;
@end

typedef void (^YTAGExtractionCompletion)(YTAGExtractionResult * _Nullable result, NSError * _Nullable error);

@interface YTAGURLExtractor : NSObject

/// Async POST to /youtubei/v1/player. Completion fires on the main queue.
+ (void)extractVideoID:(NSString *)videoID
              clientID:(YTAGClientID)clientID
            completion:(YTAGExtractionCompletion)completion;

@end

NS_ASSUME_NONNULL_END
