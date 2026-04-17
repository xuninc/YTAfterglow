#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <substrate.h>
#include <string.h>

// iOS 26 CoreMedia emits a flood of "AudioFormatDescription signalled err=-12710"
// log lines during DASH audio playback. Stock YouTube hits it too — it's Apple's
// beta logging verbosity, not something we can fix at the call site. We hook the
// unified log entry point and drop messages whose format string identifies them
// as that specific noise. Everything else passes through untouched.

typedef void (*os_log_impl_t)(void *dso, void *log, uint8_t type,
                              const char *format, uint8_t *buf, uint32_t size);

static os_log_impl_t orig_os_log_impl;

static void ytag_os_log_impl(void *dso, void *log, uint8_t type,
                             const char *format, uint8_t *buf, uint32_t size) {
    if (format && strstr(format, "AudioFormatDescription")) return;
    orig_os_log_impl(dso, log, type, format, buf, size);
}

%ctor {
    void *sym = dlsym(RTLD_DEFAULT, "_os_log_impl");
    if (sym) {
        MSHookFunction(sym, (void *)ytag_os_log_impl, (void **)&orig_os_log_impl);
    }
}
