#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const YTAGLiteModeEnabledKey;
FOUNDATION_EXPORT NSString *const YTAGLiteModeDefaultThemeAppliedKey;
FOUNDATION_EXPORT NSString *const YTAGLiteModeDefaultThemeVersionKey;

BOOL YTAGLiteModeEnabled(void);
BOOL YTAGEffectiveBool(NSString *key);
void YTAGSetLiteModeEnabled(BOOL enabled);
void YTAGLiteModeApplyDefaultThemeIfNeeded(void);
BOOL YTAGLiteModeShouldCleanCollectionView(UIView *collectionView);
BOOL YTAGLiteModeShouldRemoveFeedView(UIView *view);
BOOL YTAGLiteModeShouldStyleCommentView(UIView *view);
void YTAGLiteModeApplyViewCleanup(UIView *root);
void YTAGLiteModeApplyCommentChrome(UIView *root);

NS_ASSUME_NONNULL_END
