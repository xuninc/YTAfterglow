// YTAGDownload.x — download button integration into YouTube's player overlay.
//
// Captures the currently-playing videoID via a hook on YTIPlayerResponse, adds
// a Download button to the player overlay, and on tap presents a quality picker
// sheet followed by the modal progress UI driven by YTAGDownloadManager.
//
// MVP placement: one button in the top-right of the overlay controls row.
// YTLite's custom "second row" layout is deferred to a follow-up pass.

#import <UIKit/UIKit.h>
#import "Utils/YTAGLog.h"
#import "Utils/YTAGURLExtractor.h"
#import "Utils/YTAGFormatSelector.h"
#import "Utils/YTAGDownloadManager.h"

// --- YT classes we touch, forward-declared so this file compiles without full headers ---

@class YTIVideoDetails;
@interface YTIPlayerResponse : NSObject
@property (nonatomic, strong, readwrite) YTIVideoDetails *videoDetails;
@end
@interface YTIVideoDetails : NSObject
@property (nonatomic, copy, readwrite) NSString *videoId;
@end

// Player overlay view that contains the existing controls (pause / cast / cc / settings).
// We attach a button subview here. Real declaration lives in YouTubeHeader.
@interface YTMainAppControlsOverlayView : UIView
@end

// Responder-chain helper category added via %hook below.
@interface UIView (YTAGResponderChain)
- (UIViewController *)ytag_closestViewController;
@end

// --- Trigger action class (standard ObjC, no Logos directives) ---

@interface YTAGDownloadTrigger : NSObject
+ (void)handleButtonTap:(UIButton *)sender;
+ (void)presentQualityPickerForVideoID:(NSString *)videoID fromView:(UIView *)sourceView;
+ (void)startDownloadWithVideoID:(NSString *)videoID
                            pair:(YTAGFormatPair *)pair
                     resultTitle:(NSString *)title
                        fromView:(UIView *)sourceView;
@end

// --- State: current videoID cache ---

static NSString *gCurrentVideoID = nil;

static NSString *YTAGCurrentVideoID(void) {
    return gCurrentVideoID;
}

static const NSInteger kYTAGDownloadButtonTag = 998877;

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

@implementation YTAGDownloadTrigger

+ (void)handleButtonTap:(UIButton *)sender {
    NSString *videoID = YTAGCurrentVideoID();
    if (videoID.length == 0) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"No video"
                             message:@"Couldn't identify the current video. Try tapping the player first, then Download."
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *vc = [sender.superview ytag_closestViewController];
        [vc presentViewController:alert animated:YES completion:nil];
        return;
    }
    YTAGLog(@"dl-trigger", @"button tap, videoID=%@", videoID);
    [self presentQualityPickerForVideoID:videoID fromView:sender];
}

+ (void)presentQualityPickerForVideoID:(NSString *)videoID fromView:(UIView *)sourceView {
    UIViewController *presentingVC = [sourceView ytag_closestViewController];
    if (!presentingVC) {
        YTAGLog(@"dl-trigger", @"no presenting VC found");
        return;
    }

    // Show a transient "Loading formats…" alert while we fetch.
    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:nil
                         message:@"Loading formats…"
                  preferredStyle:UIAlertControllerStyleAlert];
    [presentingVC presentViewController:loading animated:YES completion:nil];

    [YTAGURLExtractor extractVideoID:videoID
                            clientID:YTAGClientIDiOS
                          completion:^(YTAGExtractionResult *result, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error || !result) {
                UIAlertController *err = [UIAlertController
                    alertControllerWithTitle:@"Couldn't load formats"
                                     message:error.localizedDescription ?: @"Unknown error"
                              preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [presentingVC presentViewController:err animated:YES completion:nil];
                return;
            }

            NSArray<YTAGFormatPair *> *pairs = [YTAGFormatSelector
                allOfferablePairsFromResult:result
                               audioQuality:YTAGAudioQualityStandard];
            if (pairs.count == 0) {
                UIAlertController *empty = [UIAlertController
                    alertControllerWithTitle:@"No downloadable formats"
                                     message:@"This video has no streams we can download."
                              preferredStyle:UIAlertControllerStyleAlert];
                [empty addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [presentingVC presentViewController:empty animated:YES completion:nil];
                return;
            }

            UIAlertController *sheet = [UIAlertController
                alertControllerWithTitle:result.title
                                 message:nil
                          preferredStyle:UIAlertControllerStyleActionSheet];

            for (YTAGFormatPair *pair in pairs) {
                UIAlertAction *action = [UIAlertAction
                    actionWithTitle:pair.descriptorString
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction *_) {
                    [YTAGDownloadTrigger startDownloadWithVideoID:videoID
                                                             pair:pair
                                                      resultTitle:result.title
                                                         fromView:sourceView];
                }];
                [sheet addAction:action];
            }
            [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

            // iPad popover anchor
            sheet.popoverPresentationController.sourceView = sourceView;
            sheet.popoverPresentationController.sourceRect = sourceView.bounds;

            [presentingVC presentViewController:sheet animated:YES completion:nil];
        }];
    }];
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

@end

// --- Ctor (outside any %hook) ---

%ctor {
    YTAGLog(@"dl-trigger", @"YTAGDownload hook installed");
}
