#import "YTAGAfterglowFeedModels.h"

@implementation YTAGAfterglowFeedItem

+ (instancetype)itemWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                     metadata:(NSString *)metadata
                      duration:(NSString *)duration
            thumbnailURLString:(NSString *)thumbnailURLString
                       videoID:(NSString *)videoID
             navigationCommand:(id)navigationCommand
                sourceRenderer:(id)sourceRenderer
                   contentKind:(YTAGAfterglowFeedContentKind)contentKind
{
    YTAGAfterglowFeedItem *item = [YTAGAfterglowFeedItem new];
    item.title = title.length > 0 ? title : @"Untitled";
    item.subtitle = subtitle ?: @"";
    item.metadata = metadata ?: @"";
    item.duration = duration ?: @"";
    item.thumbnailURLString = thumbnailURLString;
    item.videoID = videoID;
    item.navigationCommand = navigationCommand;
    item.sourceRenderer = sourceRenderer;
    item.contentKind = contentKind;
    return item;
}

- (NSString *)dedupeKey {
    if (self.videoID.length > 0) return [@"video:" stringByAppendingString:self.videoID];
    if (self.thumbnailURLString.length > 0) return [@"thumb:" stringByAppendingString:self.thumbnailURLString];
    return [NSString stringWithFormat:@"text:%@:%@:%@", self.title ?: @"", self.subtitle ?: @"", self.duration ?: @""];
}

@end

@implementation YTAGAfterglowFeedSection

+ (instancetype)sectionWithTitle:(NSString *)title
                            kind:(YTAGAfterglowFeedSectionKind)kind
                           items:(NSArray<YTAGAfterglowFeedItem *> *)items
{
    YTAGAfterglowFeedSection *section = [YTAGAfterglowFeedSection new];
    section.title = title ?: @"";
    section.kind = kind;
    section.items = items ?: @[];
    return section;
}

@end

NSString *YTAGAfterglowFeedDensityName(YTAGAfterglowFeedDensity density) {
    switch (density) {
        case YTAGAfterglowFeedDensityMini:
            return @"Mini";
        case YTAGAfterglowFeedDensityCompact:
        default:
            return @"Compact";
    }
}
