#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTAGDebugHUD : NSObject

+ (instancetype)sharedHUD;
- (void)show;
- (void)hide;
- (BOOL)isVisible;
+ (void)applyPreferenceOnLaunch;

@end

NS_ASSUME_NONNULL_END
