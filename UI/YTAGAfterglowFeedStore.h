#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "YTAGAfterglowFeedModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const YTAGAfterglowFeedStoreDidUpdateNotification;
extern NSString *const YTAGAfterglowFeedStoreSourceUserInfoKey;        // NSString — source id whose state changed
extern NSString *const YTAGAfterglowFeedStoreLoadStateDidChangeNotification;

typedef NS_ENUM(NSInteger, YTAGAfterglowSourceLoadState) {
    YTAGAfterglowSourceLoadStateIdle = 0,
    YTAGAfterglowSourceLoadStateLoading,
    YTAGAfterglowSourceLoadStateLoaded,
    YTAGAfterglowSourceLoadStateFailed,
};

@interface YTAGAfterglowFeedStore : NSObject
+ (instancetype)sharedStore;
- (void)recordSectionListModel:(id)model sourceIdentifier:(NSString *)sourceIdentifier;
- (NSArray<NSString *> *)missingSourceIdentifiersForSourceIdentifiers:(NSArray<NSString *> *)sourceIdentifiers;
- (NSArray<YTAGAfterglowFeedSection *> *)currentSections;
- (NSArray<YTAGAfterglowFeedItem *> *)itemsForSource:(NSString *)sourceIdentifier;
- (BOOL)openItem:(YTAGAfterglowFeedItem *)item fromView:(UIView *)view firstResponder:(nullable id)firstResponder;

// Load-state coordination. The store does not perform loads itself; the
// orchestrator in YTAfterglow.x (`YTAGRequestLoadOfSource`) reports state
// changes here so the VC can re-render placeholders/spinners.
- (YTAGAfterglowSourceLoadState)loadStateForSource:(NSString *)sourceIdentifier;
- (NSTimeInterval)loadStartTimeForSource:(NSString *)sourceIdentifier;
- (void)setLoadState:(YTAGAfterglowSourceLoadState)state forSource:(NSString *)sourceIdentifier;
@end

NS_ASSUME_NONNULL_END
