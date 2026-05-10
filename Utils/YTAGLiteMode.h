#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const YTAGLiteModeEnabledKey;
FOUNDATION_EXPORT NSString *const YTAGLiteModeDefaultThemeAppliedKey;
FOUNDATION_EXPORT NSString *const YTAGLiteModeDefaultThemeVersionKey;
FOUNDATION_EXPORT NSString *const YTAGThemeFontModeKey;

BOOL YTAGLiteModeEnabled(void);
BOOL YTAGEffectiveBool(NSString *key);
void YTAGSetLiteModeEnabled(BOOL enabled);
void YTAGLiteModeApplyDefaultThemeIfNeeded(void);
NSArray<NSString *> *YTAGLiteModeActiveTabs(void);
NSString *YTAGLiteModeStartupTab(void);
BOOL YTAGLiteModeShouldPruneFeedObject(id object);
BOOL YTAGThemeFontOverrideEnabled(void);
NSArray<NSString *> *YTAGThemeFontModeDisplayNames(void);
NSString *YTAGThemeFontModeDisplayName(NSInteger mode);
UIFont *YTAGLiteModeFont(CGFloat size, UIFontWeight weight);
UIFont *YTAGLiteModeFontMatchingFont(UIFont *font);
void YTAGLiteModeStyleLabel(UILabel *label);
NSAttributedString *YTAGLiteModeStyleAttributedString(NSAttributedString *attributedString);
BOOL YTAGLiteModeShouldCleanCollectionView(UIView *collectionView);
BOOL YTAGLiteModeShouldRemoveFeedView(UIView *view);
BOOL YTAGLiteModeShouldStyleCommentView(UIView *view);
void YTAGLiteModeApplyBackgroundColor(UIView *view);
void YTAGLiteModeApplyViewCleanup(UIView *root);
void YTAGLiteModeApplyCommentChrome(UIView *root);

NS_ASSUME_NONNULL_END
