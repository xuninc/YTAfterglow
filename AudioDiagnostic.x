#import "YTAfterglow.h"
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>
#import <substrate.h>
#include <execinfo.h>

// Diagnostic counterpart to LogFilter.x. When the audioLogDiagnose setting is on,
// hook AudioFormatGetProperty and AudioFormatGetPropertyInfo; when either returns
// -12710 (kAudioFormatUnsupportedPropertyError), emit a compact line with the
// AudioFormatPropertyID as a FourCC, the input spec size, and the top 4 caller
// frames — enough to identify which Apple framework (Spatial Audio, AirPlay,
// AVFoundation, etc.) is making the query and which property it's asking for.

typedef OSStatus (*AudioFormatGetProperty_t)(AudioFormatPropertyID, UInt32, const void *, UInt32 *, void *);
typedef OSStatus (*AudioFormatGetPropertyInfo_t)(AudioFormatPropertyID, UInt32, const void *, UInt32 *);

static AudioFormatGetProperty_t orig_AudioFormatGetProperty;
static AudioFormatGetPropertyInfo_t orig_AudioFormatGetPropertyInfo;

static NSString *ytag_audioDiagLogPath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docs.count > 0) path = [docs.firstObject stringByAppendingPathComponent:@"Afterglow-audio-diag.log"];
    });
    return path;
}

static void ytag_appendAudioDiagLine(NSString *line) {
    NSString *path = ytag_audioDiagLogPath();
    if (!path) return;
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:NO];
        return;
    }
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (h) {
        [h seekToEndOfFile];
        [h writeData:data];
        [h closeFile];
    }
}

static void ytag_logAudioMiss(const char *entry, AudioFormatPropertyID prop, UInt32 specSize) {
    char fourcc[5] = {
        (char)((prop >> 24) & 0xFF),
        (char)((prop >> 16) & 0xFF),
        (char)((prop >> 8) & 0xFF),
        (char)(prop & 0xFF),
        0
    };
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterShortStyle
                                                         timeStyle:NSDateFormatterMediumStyle];
    NSMutableString *line = [NSMutableString stringWithFormat:@"[%@] %s prop='%s' (0x%08X) specSize=%u -> -12710",
                             timestamp, entry, fourcc, (unsigned)prop, (unsigned)specSize];

    void *frames[6];
    int n = backtrace(frames, 6);
    if (n > 1) {
        char **syms = backtrace_symbols(frames, n);
        if (syms) {
            for (int i = 1; i < n && i < 6; i++) {
                [line appendFormat:@"\n    #%d %s", i - 1, syms[i]];
            }
            free(syms);
        }
    }
    ytag_appendAudioDiagLine(line);
}

static OSStatus ytag_AudioFormatGetProperty(AudioFormatPropertyID prop, UInt32 specSize,
                                             const void *spec, UInt32 *size, void *data) {
    OSStatus r = orig_AudioFormatGetProperty(prop, specSize, spec, size, data);
    if (r == -12710) ytag_logAudioMiss("AudioFormatGetProperty", prop, specSize);
    return r;
}

static OSStatus ytag_AudioFormatGetPropertyInfo(AudioFormatPropertyID prop, UInt32 specSize,
                                                 const void *spec, UInt32 *size) {
    OSStatus r = orig_AudioFormatGetPropertyInfo(prop, specSize, spec, size);
    if (r == -12710) ytag_logAudioMiss("AudioFormatGetPropertyInfo", prop, specSize);
    return r;
}

%ctor {
    if (!ytagBool(@"audioLogDiagnose")) return;
    void *sym1 = dlsym(RTLD_DEFAULT, "AudioFormatGetProperty");
    if (sym1) MSHookFunction(sym1, (void *)ytag_AudioFormatGetProperty, (void **)&orig_AudioFormatGetProperty);
    void *sym2 = dlsym(RTLD_DEFAULT, "AudioFormatGetPropertyInfo");
    if (sym2) MSHookFunction(sym2, (void *)ytag_AudioFormatGetPropertyInfo, (void **)&orig_AudioFormatGetPropertyInfo);
}
