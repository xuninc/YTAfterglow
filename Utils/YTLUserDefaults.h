#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTLUserDefaults : NSUserDefaults

@property (class, readonly, strong) YTLUserDefaults *standardUserDefaults;

- (NSArray<NSString *> *)currentActiveTabs;
- (void)setActiveTabs:(NSArray<NSString *> *)tabs;
- (NSString *)currentStartupTab;

- (void)reset;

+ (NSArray<NSString *> *)defaultActiveTabs;
+ (void)resetUserDefaults;

@end

NS_ASSUME_NONNULL_END
