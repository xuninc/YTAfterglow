#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define YTAGLog(category, ...) YTAGLogWrite((category), [NSString stringWithFormat:__VA_ARGS__])
#define YTAGLogForce(category, ...) YTAGLogWriteForce((category), [NSString stringWithFormat:__VA_ARGS__])

extern NSString *const YTAGLogDidAppendNotification;

void YTAGLogWrite(NSString *category, NSString *message);
void YTAGLogWriteForce(NSString *category, NSString *message);
NSArray<NSString *> *YTAGLogRecentEntries(void);
NSString *YTAGLogFilePath(void);
void YTAGLogClear(void);
BOOL YTAGLogEnabled(void);

NS_ASSUME_NONNULL_END
