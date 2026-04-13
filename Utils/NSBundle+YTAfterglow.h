#import <Foundation/Foundation.h>
#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#define jbroot(path) (path)
#endif

NS_ASSUME_NONNULL_BEGIN

@interface NSBundle (YTAfterglow)

// Returns YTAfterglow default bundle. Supports rootless if defined in compilation parameters
@property (class, nonatomic, readonly) NSBundle *ytag_defaultBundle;

@end

NS_ASSUME_NONNULL_END
