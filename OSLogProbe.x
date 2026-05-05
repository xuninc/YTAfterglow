// Empirical probe for whether `OSLogStore(scope:)` honors the
// `com.apple.developer.os-log-store` entitlement on our paid-dev-signed sideload.
//
// Logs a line for each scope at %ctor time, readable via Console.app / our YTAGLog HUD.
// If system-wide read works, the keyboard-debugger architecture becomes viable.

#import <Foundation/Foundation.h>
#import <OSLog/OSLog.h>
#import <objc/message.h>
#import "Utils/YTAGLog.h"

typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

// Runtime values from OSLog.framework/Headers/Store.h in the iOS 16.5 SDK.
// Keep these local so the probe builds with the tweak's iOS 13 deployment target.
static const NSInteger kYTAGOSLogStoreScopeSystem = 0;
static const NSInteger kYTAGOSLogStoreScopeCurrentProcessIdentifier = 1;
static const NSUInteger kYTAGOSLogEnumeratorReverse = 1;

static NSString *YTAGTruncatedString(NSString *value, NSUInteger maxLength) {
    if (![value isKindOfClass:[NSString class]]) return value ? [value description] : @"";
    if (value.length <= maxLength) return value;
    return [[value substringToIndex:maxLength] stringByAppendingString:@"…"];
}

static id YTAGObjectValue(id target, SEL sel) {
    if (!target || ![target respondsToSelector:sel]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, sel);
    } @catch (__unused id ex) {
        return nil;
    }
}

static pid_t YTAGPidValue(id target, SEL sel) {
    if (!target || ![target respondsToSelector:sel]) return -1;
    @try {
        return ((pid_t (*)(id, SEL))objc_msgSend)(target, sel);
    } @catch (__unused id ex) {
        return -1;
    }
}

static NSString *YTAGErrorDescription(NSError *err) {
    if (!err) return @"domain=(nil) code=0 desc=(nil)";
    return [NSString stringWithFormat:@"domain=%@ code=%ld desc=%@",
            err.domain ?: @"(nil)",
            (long)err.code,
            err.localizedDescription ?: @"(nil)"];
}

static void YTAGProbeOSLogEntitlement(void) {
    CFErrorRef cfErr = NULL;
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) {
        YTAGLogForce(@"oslogprobe", @"entitlement com.apple.developer.os-log-store: SecTaskCreateFromSelf failed");
        return;
    }

    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.developer.os-log-store"), &cfErr);
    YTAGLogForce(@"oslogprobe", @"entitlement com.apple.developer.os-log-store: value=%@ err=%@",
                 value ? CFBridgingRelease(value) : @"(nil)",
                 cfErr ? CFBridgingRelease(cfErr) : @"(nil)");
    CFRelease(task);
}

static void YTAGProbeEnumerator(id store, NSString *label) {
    SEL enumSel = NSSelectorFromString(@"entriesEnumeratorWithOptions:position:predicate:error:");
    if (![store respondsToSelector:enumSel]) {
        YTAGLogForce(@"oslogprobe", @"%@: entriesEnumeratorWithOptions missing", label);
        return;
    }

    NSUInteger options = kYTAGOSLogEnumeratorReverse;
    id position = nil;
    id predicate = nil;
    __autoreleasing NSError *autoErr = nil;
    __autoreleasing NSError **errPtr = &autoErr;
    id enumerator = nil;

    @try {
        NSMethodSignature *sig = [store methodSignatureForSelector:enumSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:enumSel];
        [inv setTarget:store];
        [inv setArgument:&options atIndex:2];
        [inv setArgument:&position atIndex:3];
        [inv setArgument:&predicate atIndex:4];
        [inv setArgument:&errPtr atIndex:5];
        [inv invoke];
        void *rawResult = NULL;
        [inv getReturnValue:&rawResult];
        enumerator = (__bridge id)rawResult;
    } @catch (NSException *ex) {
        YTAGLogForce(@"oslogprobe", @"%@: enumerator exception %@", label, ex);
        return;
    }

    if (!enumerator) {
        YTAGLogForce(@"oslogprobe", @"%@: enumerator nil %@", label, YTAGErrorDescription(autoErr));
        return;
    }

    NSUInteger count = 0;
    for (NSUInteger i = 0; i < 3; i++) {
        id entry = [enumerator nextObject];
        if (!entry) break;
        count++;
        NSString *process = YTAGObjectValue(entry, @selector(process));
        NSString *sender = YTAGObjectValue(entry, @selector(sender));
        NSString *subsystem = YTAGObjectValue(entry, @selector(subsystem));
        NSString *category = YTAGObjectValue(entry, @selector(category));
        NSString *message = YTAGObjectValue(entry, @selector(composedMessage));
        YTAGLogForce(@"oslogprobe", @"%@: entry%lu class=%@ pid=%d process=%@ sender=%@ subsystem=%@ category=%@ msg=%@",
                     label,
                     (unsigned long)count,
                     NSStringFromClass([entry class]),
                     YTAGPidValue(entry, @selector(processIdentifier)),
                     process ?: @"(nil)",
                     sender ?: @"(nil)",
                     subsystem ?: @"(nil)",
                     category ?: @"(nil)",
                     YTAGTruncatedString(message, 160) ?: @"(nil)");
    }

    if (count == 0) {
        YTAGLogForce(@"oslogprobe", @"%@: enumerator returned no entries", label);
    }
}

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
        YTAGLogForce(@"oslogprobe", @"%@: rawScope=%ld ✅ got store %p", label, (long)scope, store);
        YTAGProbeEnumerator(store, label);
    } else {
        YTAGLogForce(@"oslogprobe", @"%@: rawScope=%ld ❌ %@",
                     label, (long)scope, YTAGErrorDescription(err));
    }
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        YTAGLogForce(@"oslogprobe", @"---- OSLogStore entitlement probe ----");
        YTAGProbeOSLogEntitlement();
        // System scope is API_UNAVAILABLE on iOS, but probing raw 0 confirms
        // whether the runtime accepts it for this entitlement/signing profile.
        YTAGProbeScope(kYTAGOSLogStoreScopeCurrentProcessIdentifier, @"scope=CurrentProcess(raw1)");
        YTAGProbeScope(kYTAGOSLogStoreScopeSystem, @"scope=System(raw0 unavailable on iOS)");
    });
}
