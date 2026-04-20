// Linux-toolchain shim: the L1ghtmann/llvm-project iOS toolchain doesn't ship
// libclang_rt.ios.a, so `@available(...)` checks compile to an unresolved
// reference to `__isOSVersionAtLeast`. With `-Wl,-undefined,dynamic_lookup` the
// linker accepts the reference but dyld never binds it at runtime (the host
// YouTube binary doesn't export it either), so the first `@available` call
// jumps to NULL and the process dies. Providing our own definition here binds
// the symbol at link time in every dylib that links this file.
//
// Safe to keep even on Xcode/macOS builds: clang's libclang_rt wins because we
// aren't forcing load order, and the signatures match. See Apple's LLVM source
// for the canonical implementation.

#import <Foundation/Foundation.h>
#include <stdint.h>

__attribute__((visibility("default")))
int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor) {
    NSOperatingSystemVersion current = [[NSProcessInfo processInfo] operatingSystemVersion];
    if ((NSInteger)current.majorVersion != (NSInteger)major) {
        return (NSInteger)current.majorVersion > (NSInteger)major ? 1 : 0;
    }
    if ((NSInteger)current.minorVersion != (NSInteger)minor) {
        return (NSInteger)current.minorVersion > (NSInteger)minor ? 1 : 0;
    }
    return (NSInteger)current.patchVersion >= (NSInteger)subminor ? 1 : 0;
}
