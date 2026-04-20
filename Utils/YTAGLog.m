#import "YTAGLog.h"
#import <os/log.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/file.h>
#import <sys/stat.h>

NSString *const YTAGLogDidAppendNotification = @"YTAGLogDidAppend";

static NSString *const kSuiteName = @"afterglow.vault";
static NSString *const kEnabledKey = @"debugLogEnabled";
static const NSUInteger kMaxRingEntries = 200;
static const off_t kRollBytes = 1024 * 1024;

static dispatch_queue_t log_queue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.ytafterglow.log", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSMutableArray<NSString *> *ring_buffer(void) {
    static NSMutableArray *buf;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ buf = [NSMutableArray arrayWithCapacity:kMaxRingEntries]; });
    return buf;
}

static NSString *log_file_path(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        path = [docs stringByAppendingPathComponent:@"ytag-debug.log"];
    });
    return path;
}

static NSDateFormatter *time_formatter(void) {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss.SSS";
    });
    return fmt;
}

BOOL YTAGLogEnabled(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    return [d boolForKey:kEnabledKey];
}

NSString *YTAGLogFilePath(void) { return log_file_path(); }

static void roll_if_needed(NSString *path) {
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return;
    if (st.st_size < kRollBytes) return;
    NSString *backup = [path stringByAppendingString:@".1"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:backup error:nil];
    [fm moveItemAtPath:path toPath:backup error:nil];
}

static void append_to_file(NSString *line) {
    NSString *path = log_file_path();
    roll_if_needed(path);
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (fd < 0) return;
    flock(fd, LOCK_EX);
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    write(fd, data.bytes, data.length);
    flock(fd, LOCK_UN);
    close(fd);
}

static void ytag_log_emit(NSString *category, NSString *message) {
    NSString *stamp = [time_formatter() stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"%@ [%@] %@", stamp, category ?: @"log", message ?: @""];
    os_log(OS_LOG_DEFAULT, "[ytag] %{public}s", line.UTF8String);
    dispatch_async(log_queue(), ^{
        NSMutableArray *buf = ring_buffer();
        [buf addObject:line];
        while (buf.count > kMaxRingEntries) [buf removeObjectAtIndex:0];
        append_to_file(line);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:YTAGLogDidAppendNotification object:nil];
        });
    });
}

void YTAGLogWrite(NSString *category, NSString *message) {
    if (!YTAGLogEnabled()) return;
    ytag_log_emit(category, message);
}

void YTAGLogWriteForce(NSString *category, NSString *message) {
    ytag_log_emit(category, message);
}

NSArray<NSString *> *YTAGLogRecentEntries(void) {
    __block NSArray *copy;
    dispatch_sync(log_queue(), ^{ copy = [ring_buffer() copy]; });
    return copy;
}

void YTAGLogClear(void) {
    dispatch_async(log_queue(), ^{
        [ring_buffer() removeAllObjects];
        NSString *path = log_file_path();
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingString:@".1"] error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:YTAGLogDidAppendNotification object:nil];
        });
    });
}
