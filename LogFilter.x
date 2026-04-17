#import "YTAfterglow.h"
#import <dlfcn.h>
#import <substrate.h>
#include <string.h>

// iOS 26 CoreMedia emits a flood of "AudioFormatDescription signalled err=-12710"
// during DASH audio playback. Stock YouTube hits it too — beta verbosity, not our
// bug. Hook _os_log_impl and drop messages whose format string identifies them.
// Gated on the audioLogSilence setting.

typedef void (*os_log_impl_t)(void *dso, void *log, uint8_t type,
                              const char *format, uint8_t *buf, uint32_t size);

static os_log_impl_t orig_os_log_impl;

static void ytag_os_log_impl(void *dso, void *log, uint8_t type,
                             const char *format, uint8_t *buf, uint32_t size) {
    if (format && strstr(format, "AudioFormatDescription")) return;
    orig_os_log_impl(dso, log, type, format, buf, size);
}

%ctor {
    if (!ytagBool(@"audioLogSilence")) return;
    void *sym = dlsym(RTLD_DEFAULT, "_os_log_impl");
    if (sym) {
        MSHookFunction(sym, (void *)ytag_os_log_impl, (void **)&orig_os_log_impl);
    }
}
