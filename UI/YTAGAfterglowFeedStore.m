#import "YTAGAfterglowFeedStore.h"
#import "../Utils/YTAGLog.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString *const YTAGAfterglowFeedStoreDidUpdateNotification = @"YTAGAfterglowFeedStoreDidUpdateNotification";
NSString *const YTAGAfterglowFeedStoreSourceUserInfoKey = @"source";
NSString *const YTAGAfterglowFeedStoreLoadStateDidChangeNotification = @"YTAGAfterglowFeedStoreLoadStateDidChangeNotification";

static id YTAGFeedValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        SEL selector = NSSelectorFromString(key);
        if ([object respondsToSelector:selector]) {
            return ((id (*)(id, SEL))objc_msgSend)(object, selector);
        }
        return [object valueForKey:key];
    } @catch (__unused id exception) {
        return nil;
    }
}

static NSArray *YTAGFeedArrayValue(id object, NSString *key) {
    id value = YTAGFeedValue(object, key);
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSString *YTAGFeedStringValue(id object, NSString *key) {
    id value = YTAGFeedValue(object, key);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSString *YTAGFeedNormalizedString(NSString *string) {
    if (string.length == 0) return @"";
    NSMutableString *normalized = [NSMutableString stringWithCapacity:string.length];
    NSString *lower = string.lowercaseString;
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([allowed characterIsMember:c]) [normalized appendFormat:@"%C", c];
    }
    return normalized;
}

static BOOL YTAGFeedTextContainsAny(NSString *haystack, NSArray<NSString *> *needles) {
    NSString *normalized = YTAGFeedNormalizedString(haystack);
    if (normalized.length == 0) return NO;
    for (NSString *needle in needles) {
        if ([normalized containsString:YTAGFeedNormalizedString(needle)]) return YES;
    }
    return NO;
}

static NSString *YTAGFeedTextFromObject(id object);

static BOOL YTAGFeedTextLooksLikePlaylistSurface(NSString *text) {
    NSString *normalized = YTAGFeedNormalizedString(text);
    if (normalized.length == 0) return NO;
    NSSet *exactMarkers = [NSSet setWithArray:@[@"playlist", @"playlists", @"mix", @"mixes", @"radio", @"watchlater", @"queue"]];
    if ([exactMarkers containsObject:normalized]) return YES;
    for (NSString *marker in @[@"mixplaylist", @"playlistmix", @"watchlater"]) {
        if ([normalized containsString:marker]) return YES;
    }
    return NO;
}

static BOOL YTAGFeedRendererIsPlaylistLike(id renderer) {
    if (!renderer) return NO;
    NSString *className = NSStringFromClass([renderer class]);
    NSArray *markers = @[
        @"playlist",
        @"mixplaylist",
        @"playlistmix",
        @"radio",
        @"watchlater",
        @"queue",
        @"mix",
        @"shelfheader"
    ];
    if (YTAGFeedTextContainsAny(className, markers)) return YES;
    if (YTAGFeedTextLooksLikePlaylistSurface(YTAGFeedTextFromObject(renderer))) return YES;
    for (NSString *key in @[@"playlistId", @"playlistID", @"browseId", @"canonicalBaseURL", @"url"]) {
        if (YTAGFeedTextContainsAny(YTAGFeedStringValue(renderer, key), markers)) return YES;
    }
    return NO;
}

// Deep scan: a renderer or command has "playlist affinity" if any reachable
// field carries a playlist identifier — clicking the tile would start
// playlist/mix/queue playback, which we cannot dispatch in-app. Walks a
// limited set of known nesting keys to keep the check bounded.
static BOOL YTAGFeedObjectHasPlaylistAffinity(id object, NSUInteger depth) {
    if (!object || depth > 6) return NO;
    if (YTAGFeedRendererIsPlaylistLike(object)) return YES;

    for (NSString *key in @[@"playlistId", @"playlistID", @"playlistVideoId",
                            @"playlistVideoID", @"mixId", @"mixID", @"list", @"listType",
                            @"watchPlaylistEndpoint", @"watchPlaylistEndpointCommand"]) {
        id value = YTAGFeedValue(object, key);
        if (!value || value == [NSNull null]) continue;
        if ([value isKindOfClass:[NSString class]]) {
            if (((NSString *)value).length > 0) return YES;
        } else {
            return YES;
        }
    }

    for (NSString *nestedKey in @[@"watchEndpoint", @"reelWatchEndpoint", @"shortsWatchEndpoint",
                                  @"navigationEndpoint", @"command", @"endpoint", @"onTap"]) {
        id value = YTAGFeedValue(object, nestedKey);
        if (value && YTAGFeedObjectHasPlaylistAffinity(value, depth + 1)) return YES;
    }

    return NO;
}

static NSString *YTAGFeedTextFromObject(id object) {
    if (!object) return nil;
    if ([object isKindOfClass:[NSString class]]) return object;

    for (NSString *key in @[@"text", @"simpleText", @"title", @"content", @"accessibilityLabel"]) {
        NSString *text = YTAGFeedStringValue(object, key);
        if (text.length > 0) return text;
    }

    for (NSString *arrayKey in @[@"runsArray", @"contentsArray"]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (id run in YTAGFeedArrayValue(object, arrayKey)) {
            NSString *part = YTAGFeedTextFromObject(run);
            if (part.length > 0) [parts addObject:part];
        }
        if (parts.count > 0) return [parts componentsJoinedByString:@""];
    }

    return nil;
}

static NSString *YTAGFeedFirstText(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSString *text = YTAGFeedTextFromObject(YTAGFeedValue(object, key));
        if (text.length > 0) return text;
    }
    return nil;
}

static id YTAGFeedFirstCommand(id object) {
    for (NSString *key in @[@"navigationEndpoint", @"command", @"endpoint", @"onTap", @"watchEndpoint"]) {
        id value = YTAGFeedValue(object, key);
        if (value) return value;
    }
    return nil;
}

static NSString *YTAGFeedDirectVideoID(id object) {
    for (NSString *key in @[@"videoId", @"videoID", @"videoIDString"]) {
        NSString *value = YTAGFeedStringValue(object, key);
        if (value.length > 0) return value;
    }
    return nil;
}

static id YTAGFeedPlayableEndpoint(id command) {
    if (!command || YTAGFeedRendererIsPlaylistLike(command)) return nil;
    if (YTAGFeedObjectHasPlaylistAffinity(command, 0)) return nil;
    for (NSString *key in @[@"watchEndpoint", @"reelWatchEndpoint", @"shortsWatchEndpoint"]) {
        id value = YTAGFeedValue(command, key);
        if (!value) continue;
        if (YTAGFeedRendererIsPlaylistLike(value)) continue;
        if (YTAGFeedObjectHasPlaylistAffinity(value, 0)) continue;
        return value;
    }
    return nil;
}

static BOOL YTAGFeedCommandLooksPlayable(id command) {
    if (!command || YTAGFeedRendererIsPlaylistLike(command)) return NO;
    if (YTAGFeedObjectHasPlaylistAffinity(command, 0)) return NO;

    // Only count a command as playable if it actually resolves to a clean
    // watchEndpoint that carries a real videoId. We never accept a command
    // based on description-text matching alone, because that's how mix/radio
    // commands sneak through and end up bouncing to an external YT client.
    id watchEndpoint = YTAGFeedPlayableEndpoint(command);
    if (!watchEndpoint) return NO;
    return YTAGFeedDirectVideoID(watchEndpoint).length > 0;
}

static NSString *YTAGFeedURLStringFromThumbnailObject(id object) {
    if (!object) return nil;
    for (NSString *key in @[@"url", @"URL"]) {
        NSString *url = YTAGFeedStringValue(object, key);
        if ([url hasPrefix:@"http"]) return url;
    }
    for (NSString *key in @[@"thumbnailsArray", @"sourcesArray", @"imageSourcesArray"]) {
        NSArray *values = YTAGFeedArrayValue(object, key);
        for (id value in [values reverseObjectEnumerator]) {
            NSString *url = YTAGFeedURLStringFromThumbnailObject(value);
            if (url.length > 0) return url;
        }
    }
    return nil;
}

static NSString *YTAGFeedThumbnailURLString(id renderer) {
    for (NSString *key in @[@"thumbnail", @"thumbnailDetails", @"thumbnailRenderer", @"richThumbnail"]) {
        NSString *url = YTAGFeedURLStringFromThumbnailObject(YTAGFeedValue(renderer, key));
        if (url.length > 0) return url;
    }
    return nil;
}

static BOOL YTAGFeedClassNameContains(id object, NSArray<NSString *> *needles) {
    NSString *className = NSStringFromClass([object class]);
    NSString *description = [object description];
    for (NSString *needle in needles) {
        if ([className rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
        if ([description rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static YTAGAfterglowFeedContentKind YTAGFeedContentKindForRenderer(id renderer) {
    if (YTAGFeedClassNameContains(renderer, @[@"Reel", @"Shorts"])) return YTAGAfterglowFeedContentKindShort;
    if (YTAGFeedClassNameContains(renderer, @[@"Channel"])) return YTAGAfterglowFeedContentKindChannel;
    if (YTAGFeedClassNameContains(renderer, @[@"Post", @"Backstage"])) return YTAGAfterglowFeedContentKindPost;
    return YTAGAfterglowFeedContentKindVideo;
}

static YTAGAfterglowFeedItem *YTAGFeedItemFromRenderer(id renderer) {
    if (!renderer || YTAGFeedRendererIsPlaylistLike(renderer)) return nil;
    if (YTAGFeedObjectHasPlaylistAffinity(renderer, 0)) return nil;

    NSString *title = YTAGFeedFirstText(renderer, @[@"title", @"headline", @"shortTitle", @"accessibility", @"accessibilityData"]);
    if (YTAGFeedTextLooksLikePlaylistSurface(title)) return nil;

    NSString *subtitle = YTAGFeedFirstText(renderer, @[@"shortBylineText", @"longBylineText", @"ownerText", @"byline", @"channelTitle"]);
    NSString *duration = YTAGFeedFirstText(renderer, @[@"lengthText", @"thumbnailOverlays", @"duration", @"length"]);
    NSString *views = YTAGFeedFirstText(renderer, @[@"viewCountText", @"shortViewCountText", @"metadataText"]);
    NSString *age = YTAGFeedFirstText(renderer, @[@"publishedTimeText", @"publishedText", @"timestampText"]);
    NSString *metadata = nil;
    if (views.length > 0 && age.length > 0) metadata = [NSString stringWithFormat:@"%@ · %@", views, age];
    else metadata = views ?: age ?: @"";

    id command = YTAGFeedFirstCommand(renderer);
    if (command && YTAGFeedObjectHasPlaylistAffinity(command, 0)) return nil;

    // Positive identification: we only mint a tile when there is a clean
    // watch endpoint backing a real videoId. Anything else (shelves, chips,
    // mix carousels, channel cards, posts) is dropped before becoming a tile
    // — we can't dispatch them through the in-app responder chain anyway.
    id watchEndpoint = YTAGFeedPlayableEndpoint(command);
    NSString *videoID = YTAGFeedDirectVideoID(watchEndpoint) ?: YTAGFeedDirectVideoID(command) ?: YTAGFeedDirectVideoID(renderer);
    if (videoID.length == 0 && !YTAGFeedCommandLooksPlayable(command)) return nil;
    if (!watchEndpoint) return nil;

    NSString *thumbnailURLString = YTAGFeedThumbnailURLString(renderer);
    YTAGAfterglowFeedContentKind kind = YTAGFeedContentKindForRenderer(renderer);
    if (kind == YTAGAfterglowFeedContentKindChannel || kind == YTAGAfterglowFeedContentKindPost) return nil;

    return [YTAGAfterglowFeedItem itemWithTitle:title ?: @"YouTube Video"
                                       subtitle:subtitle ?: @""
                                       metadata:metadata ?: @""
                                        duration:duration ?: @""
                              thumbnailURLString:thumbnailURLString
                                         videoID:videoID
                               navigationCommand:command
                                  sourceRenderer:renderer
                                     contentKind:kind];
}

static NSArray<YTAGAfterglowFeedItem *> *YTAGFeedItemsFromObject(id root, NSUInteger depth) {
    if (!root || depth > 8 || YTAGFeedRendererIsPlaylistLike(root)) return @[];

    NSMutableArray<YTAGAfterglowFeedItem *> *items = [NSMutableArray array];
    YTAGAfterglowFeedItem *direct = YTAGFeedItemFromRenderer(root);
    if (direct) [items addObject:direct];

    NSArray *childKeys = @[
        @"contentsArray", @"itemsArray", @"entriesArray", @"rendererArray",
        @"richItemRenderer", @"videoRenderer", @"compactVideoRenderer",
        @"gridVideoRenderer", @"reelItemRenderer",
        @"richSectionRenderer", @"itemSectionRenderer", @"shelfRenderer",
        @"horizontalListRenderer", @"content", @"renderer"
    ];

    for (NSString *key in childKeys) {
        id value = YTAGFeedValue(root, key);
        if ([value isKindOfClass:[NSArray class]]) {
            for (id child in (NSArray *)value) {
                [items addObjectsFromArray:YTAGFeedItemsFromObject(child, depth + 1)];
            }
        } else if (value) {
            [items addObjectsFromArray:YTAGFeedItemsFromObject(value, depth + 1)];
        }
    }

    return items;
}

static NSArray<YTAGAfterglowFeedItem *> *YTAGFeedDedupeItems(NSArray<YTAGAfterglowFeedItem *> *items) {
    NSMutableArray<YTAGAfterglowFeedItem *> *deduped = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (YTAGAfterglowFeedItem *item in items) {
        if (item.contentKind == YTAGAfterglowFeedContentKindPost || item.contentKind == YTAGAfterglowFeedContentKindChannel) continue;
        NSString *key = [item dedupeKey];
        if (key.length == 0 || [seen containsObject:key]) continue;
        [seen addObject:key];
        [deduped addObject:item];
    }
    return deduped;
}

static NSArray<YTAGAfterglowFeedItem *> *YTAGFeedItemsMatchingKind(NSArray<YTAGAfterglowFeedItem *> *items, YTAGAfterglowFeedContentKind kind) {
    NSMutableArray<YTAGAfterglowFeedItem *> *matches = [NSMutableArray array];
    for (YTAGAfterglowFeedItem *item in items) {
        if (item.contentKind == kind) [matches addObject:item];
    }
    return matches;
}

static NSArray<YTAGAfterglowFeedItem *> *YTAGFeedItemsExcludingKind(NSArray<YTAGAfterglowFeedItem *> *items, YTAGAfterglowFeedContentKind kind) {
    NSMutableArray<YTAGAfterglowFeedItem *> *matches = [NSMutableArray array];
    for (YTAGAfterglowFeedItem *item in items) {
        if (item.contentKind != kind) [matches addObject:item];
    }
    return matches;
}

@interface YTAGAfterglowFeedStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<YTAGAfterglowFeedItem *> *> *itemsBySource;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *loadStatesBySource;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *loadStartTimesBySource;
@end

@implementation YTAGAfterglowFeedStore

+ (instancetype)sharedStore {
    static dispatch_once_t onceToken;
    static YTAGAfterglowFeedStore *store = nil;
    dispatch_once(&onceToken, ^{
        store = [YTAGAfterglowFeedStore new];
        store.itemsBySource = [NSMutableDictionary dictionary];
        store.loadStatesBySource = [NSMutableDictionary dictionary];
        store.loadStartTimesBySource = [NSMutableDictionary dictionary];
    });
    return store;
}

- (void)recordSectionListModel:(id)model sourceIdentifier:(NSString *)sourceIdentifier {
    if (!model) return;
    NSString *source = sourceIdentifier.length > 0 ? sourceIdentifier : @"home";
    NSArray *items = YTAGFeedDedupeItems(YTAGFeedItemsFromObject(model, 0));
    if (items.count == 0) return;

    @synchronized (self) {
        self.itemsBySource[source] = items;
        self.loadStatesBySource[source] = @(YTAGAfterglowSourceLoadStateLoaded);
    }
    YTAGLog(@"afterglow-feed", @"recorded %@ items=%lu", source, (unsigned long)items.count);
    NSDictionary *userInfo = @{YTAGAfterglowFeedStoreSourceUserInfoKey: source};
    [[NSNotificationCenter defaultCenter] postNotificationName:YTAGAfterglowFeedStoreDidUpdateNotification
                                                        object:self
                                                      userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTAGAfterglowFeedStoreLoadStateDidChangeNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (NSArray<YTAGAfterglowFeedItem *> *)itemsForSource:(NSString *)sourceIdentifier {
    if (sourceIdentifier.length == 0) return @[];
    @synchronized (self) {
        return self.itemsBySource[sourceIdentifier] ?: @[];
    }
}

- (YTAGAfterglowSourceLoadState)loadStateForSource:(NSString *)sourceIdentifier {
    if (sourceIdentifier.length == 0) return YTAGAfterglowSourceLoadStateIdle;
    @synchronized (self) {
        // If we have items, we're loaded regardless of any stale state entry.
        if ([self.itemsBySource[sourceIdentifier] count] > 0) return YTAGAfterglowSourceLoadStateLoaded;
        NSNumber *state = self.loadStatesBySource[sourceIdentifier];
        return state ? (YTAGAfterglowSourceLoadState)state.integerValue : YTAGAfterglowSourceLoadStateIdle;
    }
}

- (NSTimeInterval)loadStartTimeForSource:(NSString *)sourceIdentifier {
    if (sourceIdentifier.length == 0) return 0;
    @synchronized (self) {
        NSNumber *start = self.loadStartTimesBySource[sourceIdentifier];
        return start ? start.doubleValue : 0;
    }
}

- (void)setLoadState:(YTAGAfterglowSourceLoadState)state forSource:(NSString *)sourceIdentifier {
    if (sourceIdentifier.length == 0) return;
    @synchronized (self) {
        self.loadStatesBySource[sourceIdentifier] = @(state);
        if (state == YTAGAfterglowSourceLoadStateLoading) {
            self.loadStartTimesBySource[sourceIdentifier] = @([NSDate timeIntervalSinceReferenceDate]);
        } else if (state == YTAGAfterglowSourceLoadStateIdle ||
                   state == YTAGAfterglowSourceLoadStateLoaded ||
                   state == YTAGAfterglowSourceLoadStateFailed) {
            [self.loadStartTimesBySource removeObjectForKey:sourceIdentifier];
        }
    }
    NSDictionary *userInfo = @{YTAGAfterglowFeedStoreSourceUserInfoKey: sourceIdentifier};
    [[NSNotificationCenter defaultCenter] postNotificationName:YTAGAfterglowFeedStoreLoadStateDidChangeNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (NSArray<NSString *> *)missingSourceIdentifiersForSourceIdentifiers:(NSArray<NSString *> *)sourceIdentifiers {
    if (sourceIdentifiers.count == 0) return @[];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    @synchronized (self) {
        for (NSString *source in sourceIdentifiers) {
            if (![source isKindOfClass:[NSString class]] || source.length == 0) continue;
            NSArray *items = self.itemsBySource[source];
            if (items.count == 0) [missing addObject:source];
        }
    }
    return missing;
}

- (NSArray<YTAGAfterglowFeedSection *> *)currentSections {
    NSArray *home = nil;
    NSArray *subs = nil;
    NSArray *shortSource = nil;
    NSArray *history = nil;
    @synchronized (self) {
        home = self.itemsBySource[@"home"] ?: @[];
        subs = self.itemsBySource[@"subscriptions"] ?: @[];
        shortSource = self.itemsBySource[@"shorts"] ?: @[];
        history = self.itemsBySource[@"history"] ?: @[];
    }

    NSMutableArray<YTAGAfterglowFeedSection *> *sections = [NSMutableArray array];

    NSArray *recommended = YTAGFeedItemsExcludingKind(home, YTAGAfterglowFeedContentKindShort);
    if (recommended.count > 0) {
        [sections addObject:[YTAGAfterglowFeedSection sectionWithTitle:@"Recommended"
                                                                  kind:YTAGAfterglowFeedSectionKindRecommended
                                                                 items:recommended]];
    }

    NSArray *subscriptionVideos = YTAGFeedItemsExcludingKind(subs, YTAGAfterglowFeedContentKindShort);
    if (subscriptionVideos.count > 0) {
        [sections addObject:[YTAGAfterglowFeedSection sectionWithTitle:@"Subscriptions"
                                                                  kind:YTAGAfterglowFeedSectionKindSubscriptions
                                                                 items:subscriptionVideos]];
    }

    NSMutableArray *shorts = [NSMutableArray arrayWithArray:YTAGFeedItemsMatchingKind(home, YTAGAfterglowFeedContentKindShort)];
    [shorts addObjectsFromArray:YTAGFeedItemsMatchingKind(shortSource, YTAGAfterglowFeedContentKindShort)];
    NSArray *dedupedShorts = YTAGFeedDedupeItems(shorts);
    if (dedupedShorts.count > 0) {
        [sections addObject:[YTAGAfterglowFeedSection sectionWithTitle:@"Shorts"
                                                                  kind:YTAGAfterglowFeedSectionKindShorts
                                                                 items:dedupedShorts]];
    }

    NSArray *historyVideos = YTAGFeedItemsExcludingKind(history, YTAGAfterglowFeedContentKindShort);
    if (historyVideos.count > 0) {
        [sections addObject:[YTAGAfterglowFeedSection sectionWithTitle:@"Watch History"
                                                                  kind:YTAGAfterglowFeedSectionKindHype
                                                                 items:historyVideos]];
    }

    return sections;
}

- (BOOL)openItem:(YTAGAfterglowFeedItem *)item fromView:(UIView *)view firstResponder:(id)firstResponder {
    if (!item) return NO;
    id command = item.navigationCommand;
    if (!command) return NO;

    id responder = firstResponder ?: view;

    Class tappedEventClass = objc_lookUpClass("YTVideoCellTappedActionResponderEvent");
    if ([tappedEventClass respondsToSelector:@selector(eventWithCommand:firstResponder:)]) {
        id event = ((id (*)(id, SEL, id, id))objc_msgSend)(tappedEventClass, @selector(eventWithCommand:firstResponder:), command, responder);
        if ([event respondsToSelector:@selector(send)]) {
            ((void (*)(id, SEL))objc_msgSend)(event, @selector(send));
            return YES;
        }
    }

    Class commandEventClass = objc_lookUpClass("YTCommandResponderEvent");
    if ([commandEventClass respondsToSelector:@selector(eventWithCommand:fromView:displayTitle:firstResponder:)]) {
        id event = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(commandEventClass, @selector(eventWithCommand:fromView:displayTitle:firstResponder:), command, view, item.title, responder);
        if ([event respondsToSelector:@selector(send)]) {
            ((void (*)(id, SEL))objc_msgSend)(event, @selector(send));
            return YES;
        }
    }

    // We are not the official YouTube client and do not own the `youtube://`
    // URL scheme — handing the tap off to UIApplication would launch
    // whichever YT client iOS routes the scheme to. Better to fail silently.
    return NO;
}

@end
