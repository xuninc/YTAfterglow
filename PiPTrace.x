#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Utils/YTAGLog.h"

// Diagnostic hooks to trace WHEN and HOW an AVPictureInPictureController gets
// created and bound into YT's internal MLPIPController.  The YouPiP button
// path hits `MLPIPController.pictureInPictureController == nil` on YT
// 21.16.2 / iOS 26, while the swipe-to-miniplayer path succeeds — these
// hooks are here to reveal which selector fires along the working path so
// we can replicate it from the button.

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
