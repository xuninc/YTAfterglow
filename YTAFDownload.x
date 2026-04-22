// YTAFDownload.x — download button integration into YouTube's player overlay.
//
// Captures the currently-playing videoID via a hook on YTIPlayerResponse, adds
// a Download button to the player overlay, and on tap presents a quality picker
// sheet followed by the modal progress UI driven by YTAFDownloadManager.
//
// MVP placement: one button in the top-right of the overlay controls row.
// YTLite's custom "second row" layout is deferred to a follow-up pass.

#import <UIKit/UIKit.h>
#import "Utils/YTAGLog.h"
#import "Utils/YTAFURLExtractor.h"
#import "Utils/YTAFFormatSelector.h"
#import "Utils/YTAFDownloadManager.h"

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
@interface UIView (YTAFResponderChain)
- (UIViewController *)ytaf_closestViewController;
@end

// --- Trigger action class (standard ObjC, no Logos directives) ---

@interface YTAFDownloadTrigger : NSObject
+ (void)handleButtonTap:(UIButton *)sender;
+ (void)presentQualityPickerForVideoID:(NSString *)videoID fromView:(UIView *)sourceView;
+ (void)startDownloadWithVideoID:(NSString *)videoID
                            pair:(YTAFFormatPair *)pair
                     resultTitle:(NSString *)title
                        fromView:(UIView *)sourceView;
@end

// --- State: current videoID cache ---

static NSString *gCurrentVideoID = nil;

static NSString *YTAFCurrentVideoID(void) {
    return gCurrentVideoID;
}

static const NSInteger kYTAFDownloadButtonTag = 998877;

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
- (UIViewController *)ytaf_closestViewController {
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
    UIButton *existing = (UIButton *)[self viewWithTag:kYTAFDownloadButtonTag];
    if (existing) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = kYTAFDownloadButtonTag;
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
    [btn addTarget:[YTAFDownloadTrigger class]
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

@implementation YTAFDownloadTrigger

+ (void)handleButtonTap:(UIButton *)sender {
    NSString *videoID = YTAFCurrentVideoID();
    if (videoID.length == 0) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"No video"
                             message:@"Couldn't identify the current video. Try tapping the player first, then Download."
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *vc = [sender.superview ytaf_closestViewController];
        [vc presentViewController:alert animated:YES completion:nil];
        return;
    }
    YTAGLog(@"dl-trigger", @"button tap, videoID=%@", videoID);
    [self presentQualityPickerForVideoID:videoID fromView:sender];
}

+ (void)presentQualityPickerForVideoID:(NSString *)videoID fromView:(UIView *)sourceView {
    UIViewController *presentingVC = [sourceView ytaf_closestViewController];
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

    [YTAFURLExtractor extractVideoID:videoID
                            clientID:YTAFClientIDiOS
                          completion:^(YTAFExtractionResult *result, NSError *error) {
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

            NSArray<YTAFFormatPair *> *pairs = [YTAFFormatSelector
                allOfferablePairsFromResult:result
                               audioQuality:YTAFAudioQualityStandard];
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

            for (YTAFFormatPair *pair in pairs) {
                UIAlertAction *action = [UIAlertAction
                    actionWithTitle:pair.descriptorString
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction *_) {
                    [YTAFDownloadTrigger startDownloadWithVideoID:videoID
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
                            pair:(YTAFFormatPair *)pair
                     resultTitle:(NSString *)title
                        fromView:(UIView *)sourceView
{
    UIViewController *presentingVC = [sourceView ytaf_closestViewController];
    if (!presentingVC) return;

    YTAFDownloadRequest *req = [YTAFDownloadRequest new];
    req.videoID = videoID;
    req.titleOverride = title;
    req.pair = pair;
    req.postAction = YTAFPostDownloadActionAsk;

    [[YTAFDownloadManager sharedManager]
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
    YTAGLog(@"dl-trigger", @"YTAFDownload hook installed");
}
