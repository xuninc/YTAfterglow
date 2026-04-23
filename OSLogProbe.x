// Empirical probe for whether `OSLogStore(scope:)` honors the
// `com.apple.developer.os-log-store` entitlement on our paid-dev-signed sideload.
//
// Logs a line for each scope at %ctor time, readable via Console.app / our YTAGLog HUD.
// If system-wide read works, the keyboard-debugger architecture becomes viable.

#import <Foundation/Foundation.h>
#import <OSLog/OSLog.h>
#import "Utils/YTAGLog.h"

static void YTAGProbeScope(NSInteger scope, NSString *label) {
    NSError *err = nil;
    Class cls = NSClassFromString(@"OSLogStore");
    if (!cls) {
        YTAGLogForce(@"oslogprobe", @"%@: OSLogStore class missing (pre-iOS 15?)", label);
        return;
    }
    // +[OSLogStore storeWithScope:error:] — selector exists on iOS 15+
    SEL sel = NSSelectorFromString(@"storeWithScope:error:");
    if (![cls respondsToSelector:sel]) {
        YTAGLogForce(@"oslogprobe", @"%@: +storeWithScope:error: missing", label);
        return;
    }
    __autoreleasing NSError *autoErr = nil;
    __autoreleasing NSError **errPtr = &autoErr;
    id store = nil;
    @try {
        NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        [inv setTarget:cls];
        [inv setArgument:&scope atIndex:2];
        [inv setArgument:&errPtr atIndex:3];
        [inv invoke];
        void *rawResult = NULL;
        [inv getReturnValue:&rawResult];
        store = (__bridge id)rawResult;
    } @catch (NSException *ex) {
        YTAGLogForce(@"oslogprobe", @"%@: exception %@", label, ex);
        return;
    }
    err = autoErr;

    if (store) {
        YTAGLogForce(@"oslogprobe", @"%@: ✅ got store %p", label, store);
    } else {
        YTAGLogForce(@"oslogprobe", @"%@: ❌ err domain=%@ code=%ld desc=%@",
                     label,
                     err.domain ?: @"(nil)",
                     (long)err.code,
                     err.localizedDescription ?: @"(nil)");
    }
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        YTAGLogForce(@"oslogprobe", @"---- OSLogStore entitlement probe ----");
        // 0 = CurrentProcessIdentifier, 1 = System (per OSLog.h).
        // We pass raw enum integers via NSInvocation so this compiles without needing
        // the OSLog headers to expose the scope enum.
        YTAGProbeScope(0, @"scope=CurrentProcess");
        YTAGProbeScope(1, @"scope=System");
    });
}
