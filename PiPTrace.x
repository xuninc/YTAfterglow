#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Utils/YTAGLog.h"

// Diagnostic hooks for PiP setup compatibility. These logs show when an
// AVPictureInPictureController is created and bound into YouTube's internal
// MLPIPController so button-driven PiP can follow the same healthy setup path
// as swipe-to-miniplayer PiP.

@interface MLPIPController : NSObject
@end

%hook AVPictureInPictureController

- (instancetype)initWithPlayerLayer:(AVPlayerLayer *)playerLayer {
    AVPictureInPictureController *r = %orig;
    YTAGLogForce(@"avpip", @"init(PlayerLayer=%p) -> %p layer=%@", playerLayer, r, playerLayer);
    return r;
}

- (instancetype)initWithContentSource:(id)contentSource {
    AVPictureInPictureController *r = %orig;
    YTAGLogForce(@"avpip", @"init(ContentSource=%p) -> %p source=%@", contentSource, r, contentSource);
    return r;
}

- (void)startPictureInPicture {
    YTAGLogForce(@"avpip", @"startPictureInPicture self=%p active=%@ possible=%@",
                 self,
                 self.pictureInPictureActive ? @"YES" : @"NO",
                 [AVPictureInPictureController isPictureInPictureSupported] ? @"YES" : @"NO");
    %orig;
}

- (void)stopPictureInPicture {
    YTAGLogForce(@"avpip", @"stopPictureInPicture self=%p", self);
    %orig;
}

%end

%hook MLPIPController

- (void)setPictureInPictureController:(id)controller {
    YTAGLogForce(@"mlpip", @"setPictureInPictureController: self=%p avpip=%p", self, controller);
    %orig;
}

%end
