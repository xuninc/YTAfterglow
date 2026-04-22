// YTAGDownload.x — download button integration into YouTube's player overlay.
//
// Captures the currently-playing videoID via a hook on YTIPlayerResponse, adds
// a Download button to the player overlay, and on tap presents a 2×3 tile grid
// bottom sheet (YTAGDownloadActionSheetViewController). Tiles route to the
// matching pipeline: DownloadVideo goes through the quality picker, DownloadAudio
// goes directly (no picker), and the utility tiles (Captions / Thumbnail /
// Copy Info / External Player) stub to "Coming soon" for now.

#import <UIKit/UIKit.h>
#import "Utils/YTAGLog.h"
#import "Utils/YTAGURLExtractor.h"
#import "Utils/YTAGFormatSelector.h"
#import "Utils/YTAGDownloadManager.h"
#import "UI/YTAGDownloadActionSheetViewController.h"

// --- YT classes we touch, forward-declared so this file compiles without full headers ---

@class YTIVideoDetails;
@interface YTIPlayerResponse : NSObject
@property (nonatomic, strong, readwrite) YTIVideoDetails *videoDetails;
@end
@interface YTIVideoDetails : NSObject
@property (nonatomic, copy, readwrite) NSString *videoId;
@end

// Player overlay view that contains the existing controls (pause / cast / cc / settings).
@interface YTMainAppControlsOverlayView : UIView
@end

// Responder-chain helper category added via %hook below.
@interface UIView (YTAGResponderChain)
- (UIViewController *)ytag_closestViewController;
@end

// --- Trigger action class (standard ObjC, no Logos directives) ---

@interface YTAGDownloadTrigger : NSObject
+ (void)handleButtonTap:(UIButton *)sender;
@end

// --- State: current videoID cache ---

static NSString *gCurrentVideoID = nil;

static NSString *YTAGCurrentVideoID(void) {
    return gCurrentVideoID;
}

static const NSInteger kYTAGDownloadButtonTag = 998877;

// --- File-scope helper: format a byte count for the chip ("2.4 MB" / "780 KB") ---

static NSString *YTAGFormatBytesShort(long long bytes) {
    if (bytes <= 0) return nil;
    double mb = (double)bytes / (1024.0 * 1024.0);
    if (mb >= 1.0) return [NSString stringWithFormat:@"%.1f MB", mb];
    double kb = (double)bytes / 1024.0;
    return [NSString stringWithFormat:@"%.0f KB", kb];
}

// --- Hooks ---

%hook YTIPlayerResponse

- (void)setVideoDetails:(YTIVideoDetails *)details {
    %orig;
    if ([details respondsToSelector:@selector(videoId)] && details.videoId.length > 0) {
        gCurrentVideoID = [details.videoId copy];
        YTAGLog(@"dl-trigger", @"captured videoID=%@", gCurrentVideoID);
    }
}

%end

%hook UIView

%new(@@:)
- (UIViewController *)ytag_closestViewController {
    UIResponder *r = self.nextResponder;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
        r = r.nextResponder;
    }
    return nil;
}

%end

%hook YTMainAppControlsOverlayView

- (void)layoutSubviews {
    %orig;

    // Install the download button once. Tag-check prevents re-add on each layout pass.
    UIButton *existing = (UIButton *)[self viewWithTag:kYTAGDownloadButtonTag];
    if (existing) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = kYTAGDownloadButtonTag;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.tintColor = [UIColor whiteColor];
    btn.accessibilityLabel = @"Download";
    if (@available(iOS 13.0, *)) {
        UIImage *icon = [UIImage systemImageNamed:@"arrow.down.circle"];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
        [btn setImage:[icon imageByApplyingSymbolConfiguration:cfg] ?: icon forState:UIControlStateNormal];
    } else {
        [btn setTitle:@"DL" forState:UIControlStateNormal];
    }
    [btn addTarget:[YTAGDownloadTrigger class]
            action:@selector(handleButtonTap:)
  forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:btn];

    // Top-right placement, safe-area aware. ~44pt from top, 12pt from right.
    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:44],
        [btn.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [btn.widthAnchor constraintEqualToConstant:36],
        [btn.heightAnchor constraintEqualToConstant:36],
    ]];
}

%end

// --- Trigger logic (standard ObjC @implementation outside any %hook) ---

@interface YTAGDownloadTrigger ()
+ (void)presentActionSheetWithResult:(YTAGExtractionResult *)result
                            videoID:(NSString *)videoID
                      presentingVC:(UIViewController *)presentingVC
                         fromView:(UIView *)sourceView;
+ (void)presentQualityPickerWithResult:(YTAGExtractionResult *)result
                              videoID:(NSString *)videoID
                         presentingVC:(UIViewController *)presentingVC
                             fromView:(UIView *)sourceView;
+ (void)startDownloadWithVideoID:(NSString *)videoID
                            pair:(YTAGFormatPair *)pair
                     resultTitle:(NSString *)title
                        fromView:(UIView *)sourceView;
+ (void)showComingSoon:(NSString *)feature on:(UIViewController *)presentingVC;
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message on:(UIViewController *)vc;
@end

@implementation YTAGDownloadTrigger

+ (void)handleButtonTap:(UIButton *)sender {
    NSString *videoID = YTAGCurrentVideoID();
    UIViewController *presentingVC = [sender.superview ytag_closestViewController];
    if (videoID.length == 0) {
        [self showAlertWithTitle:@"No video"
                         message:@"Couldn't identify the current video. Try tapping the player first, then Download."
                              on:presentingVC];
        return;
    }
    if (!presentingVC) {
        YTAGLog(@"dl-trigger", @"no presenting VC found");
        return;
    }

    YTAGLog(@"dl-trigger", @"button tap, videoID=%@", videoID);

    // Transient "Loading…" while we pre-fetch the extraction so the sheet can
    // show the real audio size chip and we don't need a second fetch for
    // Download Video / Download Audio actions.
    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:nil
                         message:@"Loading…"
                  preferredStyle:UIAlertControllerStyleAlert];
    [presentingVC presentViewController:loading animated:YES completion:nil];

    [YTAGURLExtractor extractVideoID:videoID
                            clientID:YTAGClientIDiOS
                          completion:^(YTAGExtractionResult *result, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error || !result) {
                [self showAlertWithTitle:@"Couldn't load video"
                                 message:error.localizedDescription ?: @"Unknown error"
                                      on:presentingVC];
                return;
            }
            [self presentActionSheetWithResult:result
                                       videoID:videoID
                                  presentingVC:presentingVC
                                      fromView:sender];
        }];
    }];
}

+ (void)presentActionSheetWithResult:(YTAGExtractionResult *)result
                             videoID:(NSString *)videoID
                        presentingVC:(UIViewController *)presentingVC
                            fromView:(UIView *)sourceView
{
    YTAGDownloadActionSheetViewController *sheet = [YTAGDownloadActionSheetViewController new];
    sheet.channelName = result.author;
    sheet.videoTitle = result.title;

    // Audio size chip: compute from the preferred audio format.
    YTAGFormatPair *audioPair = [YTAGFormatSelector
        selectAudioPairFromResult:result
                     audioQuality:YTAGAudioQualityStandard];
    sheet.audioSizeChip = audioPair ? YTAGFormatBytesShort(audioPair.audioFormat.contentLength) : nil;

    __weak UIViewController *weakPresenting = presentingVC;
    sheet.onAction = ^(YTAGDownloadAction action) {
        UIViewController *p = weakPresenting;
        if (!p) return;

        switch (action) {
            case YTAGDownloadActionDownloadVideo:
                [YTAGDownloadTrigger presentQualityPickerWithResult:result
                                                            videoID:videoID
                                                       presentingVC:p
                                                           fromView:sourceView];
                break;

            case YTAGDownloadActionDownloadAudio:
                if (audioPair) {
                    YTAGFormatPair *pair = [YTAGFormatPair new];
                    pair.audioFormat = audioPair.audioFormat;   // videoFormat nil = audio-only
                    [YTAGDownloadTrigger startDownloadWithVideoID:videoID
                                                             pair:pair
                                                      resultTitle:result.title
                                                         fromView:sourceView];
                } else {
                    [YTAGDownloadTrigger showAlertWithTitle:@"No audio available"
                                                    message:@"This video doesn't expose a downloadable audio track."
                                                         on:p];
                }
                break;

            case YTAGDownloadActionDownloadCaptions:
                [YTAGDownloadTrigger showComingSoon:@"Download Captions" on:p];
                break;

            case YTAGDownloadActionSaveImage:
                [YTAGDownloadTrigger showComingSoon:@"Save Thumbnail" on:p];
                break;

            case YTAGDownloadActionCopyInformation:
                [YTAGDownloadTrigger showComingSoon:@"Copy Info" on:p];
                break;

            case YTAGDownloadActionPlayInExternalPlayer:
                [YTAGDownloadTrigger showComingSoon:@"External Player" on:p];
                break;
        }
    };

    [presentingVC presentViewController:sheet animated:YES completion:nil];
}

+ (void)presentQualityPickerWithResult:(YTAGExtractionResult *)result
                               videoID:(NSString *)videoID
                          presentingVC:(UIViewController *)presentingVC
                              fromView:(UIView *)sourceView
{
    NSArray<YTAGFormatPair *> *pairs = [YTAGFormatSelector
        allOfferablePairsFromResult:result
                       audioQuality:YTAGAudioQualityStandard];

    // Filter to video entries only (the "all offerable" includes an audio-only
    // trailer). We already have a dedicated Audio tile for that case.
    NSMutableArray<YTAGFormatPair *> *videoPairs = [NSMutableArray array];
    for (YTAGFormatPair *p in pairs) {
        if (p.videoFormat != nil) [videoPairs addObject:p];
    }

    if (videoPairs.count == 0) {
        [self showAlertWithTitle:@"No downloadable formats"
                         message:@"This video has no streams we can download."
                              on:presentingVC];
        return;
    }

    UIAlertController *picker = [UIAlertController
        alertControllerWithTitle:result.title
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    for (YTAGFormatPair *pair in videoPairs) {
        [picker addAction:[UIAlertAction
            actionWithTitle:pair.descriptorString
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_) {
            [YTAGDownloadTrigger startDownloadWithVideoID:videoID
                                                     pair:pair
                                              resultTitle:result.title
                                                 fromView:sourceView];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;

    [presentingVC presentViewController:picker animated:YES completion:nil];
}

+ (void)startDownloadWithVideoID:(NSString *)videoID
                            pair:(YTAGFormatPair *)pair
                     resultTitle:(NSString *)title
                        fromView:(UIView *)sourceView
{
    UIViewController *presentingVC = [sourceView ytag_closestViewController];
    if (!presentingVC) return;

    YTAGDownloadRequest *req = [YTAGDownloadRequest new];
    req.videoID = videoID;
    req.titleOverride = title;
    req.pair = pair;
    req.postAction = YTAGPostDownloadActionAsk;

    [[YTAGDownloadManager sharedManager]
          startDownload:req
         presentingFrom:presentingVC
             completion:^(NSURL *outputFileURL, NSError *error) {
        if (error) {
            YTAGLog(@"dl-trigger", @"download error: %@", error.localizedDescription);
        } else {
            YTAGLog(@"dl-trigger", @"download ok: %@", outputFileURL.lastPathComponent);
        }
    }];
}

+ (void)showComingSoon:(NSString *)feature on:(UIViewController *)presentingVC {
    [self showAlertWithTitle:feature
                     message:@"Coming soon."
                          on:presentingVC];
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message on:(UIViewController *)vc {
    if (!vc) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

@end

// --- Ctor (outside any %hook) ---

%ctor {
    YTAGLog(@"dl-trigger", @"YTAGDownload hook installed");
}
