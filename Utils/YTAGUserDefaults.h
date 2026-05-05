#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTAGUserDefaults : NSUserDefaults

@property (class, readonly, strong) YTAGUserDefaults *standardUserDefaults;

- (NSArray<NSString *> *)currentActiveTabs;
- (void)setActiveTabs:(NSArray<NSString *> *)tabs;
- (NSString *)currentStartupTab;

- (void)reset;
- (nullable NSData *)exportPreferencesDataWithError:(NSError **)error;
- (BOOL)importPreferencesData:(NSData *)data error:(NSError **)error;

+ (NSArray<NSString *> *)defaultActiveTabs;
+ (void)resetUserDefaults;

@end

NS_ASSUME_NONNULL_END
