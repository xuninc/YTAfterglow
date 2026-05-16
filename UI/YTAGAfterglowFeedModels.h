#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTAGAfterglowFeedDensity) {
    YTAGAfterglowFeedDensityCompact = 0,
    YTAGAfterglowFeedDensityMini = 1,
};

typedef NS_ENUM(NSInteger, YTAGAfterglowFeedSectionKind) {
    YTAGAfterglowFeedSectionKindSubscriptions = 0,
    YTAGAfterglowFeedSectionKindRecommended = 1,
    YTAGAfterglowFeedSectionKindShorts = 2,
    YTAGAfterglowFeedSectionKindHype = 3,
};

typedef NS_ENUM(NSInteger, YTAGAfterglowFeedContentKind) {
    YTAGAfterglowFeedContentKindVideo = 0,
    YTAGAfterglowFeedContentKindShort = 1,
    YTAGAfterglowFeedContentKindChannel = 2,
    YTAGAfterglowFeedContentKindPost = 3,
};

@interface YTAGAfterglowFeedItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *metadata;
@property (nonatomic, copy) NSString *duration;
@property (nonatomic, copy, nullable) NSString *thumbnailURLString;
@property (nonatomic, copy, nullable) NSString *videoID;
@property (nonatomic, strong, nullable) id navigationCommand;
@property (nonatomic, strong, nullable) id sourceRenderer;
@property (nonatomic, assign) YTAGAfterglowFeedContentKind contentKind;
+ (instancetype)itemWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                     metadata:(NSString *)metadata
                      duration:(NSString *)duration
            thumbnailURLString:(nullable NSString *)thumbnailURLString
                       videoID:(nullable NSString *)videoID
             navigationCommand:(nullable id)navigationCommand
                sourceRenderer:(nullable id)sourceRenderer
                   contentKind:(YTAGAfterglowFeedContentKind)contentKind;
- (NSString *)dedupeKey;
@end

@interface YTAGAfterglowFeedSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) YTAGAfterglowFeedSectionKind kind;
@property (nonatomic, copy) NSArray<YTAGAfterglowFeedItem *> *items;
+ (instancetype)sectionWithTitle:(NSString *)title
                            kind:(YTAGAfterglowFeedSectionKind)kind
                           items:(NSArray<YTAGAfterglowFeedItem *> *)items;
@end

NSString *YTAGAfterglowFeedDensityName(YTAGAfterglowFeedDensity density);

NS_ASSUME_NONNULL_END
