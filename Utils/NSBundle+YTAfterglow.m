#import "NSBundle+YTAfterglow.h"

@implementation NSBundle (YTAfterglow)

+ (NSBundle *)ytag_defaultBundle {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YTAfterglow" ofType:@"bundle"];
        NSString *kBundlePath = jbroot(@"/Library/Application Support/YTAfterglow.bundle");

        bundle = [NSBundle bundleWithPath:tweakBundlePath ?: kBundlePath];
    });

    return bundle;
}

@end
