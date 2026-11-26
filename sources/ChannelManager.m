#import "ChannelManager.h"

#import "Util.h"

static NSString *const BlockedChannelsDefaultsKey = @"GonerinoBlockedChannels";
static NSString *const ChannelLabelsDefaultsKey   = @"GonerinoChannelLabels";

static NSString *TrimmedChannelText(id value)
{
    if (![value isKindOfClass:[NSString class]])
        return nil;
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL IsGeneratedActionLabel(NSString *channel)
{
    NSString *normalized = TrimmedChannelText(channel).lowercaseString;
    return
        [normalized isEqualToString:@"action menu"] || [normalized isEqualToString:@"more actions"];
}

static NSString *ChannelLookupKey(NSString *channel)
{
    NSString        *normalized        = TrimmedChannelText(channel).lowercaseString;
    NSMutableString *key               = [NSMutableString stringWithCapacity:normalized.length];
    NSCharacterSet  *allowedCharacters = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger index = 0; index < normalized.length; index++)
    {
        unichar character = [normalized characterAtIndex:index];
        if ([allowedCharacters characterIsMember:character])
            [key appendFormat:@"%C", character];
    }
    return key.copy;
}

static NSString *FirstCaptureGroup(NSString *pattern, NSRegularExpressionOptions options,
                                   NSString *input)
{
    if (input.length == 0)
        return nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:options
                                                                             error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:input
                                                    options:0
                                                      range:NSMakeRange(0, input.length)];
    if (!match || match.numberOfRanges < 2)
        return nil;
    NSRange range = [match rangeAtIndex:1];
    return range.location == NSNotFound ? nil : [input substringWithRange:range];
}

@interface ChannelManager ()
@property (nonatomic, strong) NSMutableSet<NSString *>                       *entries;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *>    *labels;
@property (copy) NSSet<NSString *>                                           *idLookup;
@property (copy) NSSet<NSString *>                                           *handleLookup;
@property (copy) NSSet<NSString *>                                           *nameLookup;
@end

@implementation ChannelManager

+ (instancetype)sharedInstance
{
    static ChannelManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

+ (NSString *)channelIDFromInput:(NSString *)input
{
    NSString *text = TrimmedChannelText(input);
    return FirstCaptureGroup(@"^(UC[0-9A-Za-z_-]{22})$", 0, text)
               ?: FirstCaptureGroup(@"/channel/(UC[0-9A-Za-z_-]{22})(?:$|[/?#])", 0, text);
}

+ (NSString *)normalizedHandle:(NSString *)input
{
    NSString *text = TrimmedChannelText(input);
    NSString *name = FirstCaptureGroup(@"^/?@([^/?#\\s]+)(?:$|[/?#])", 0, text)
                         ?: FirstCaptureGroup(@"youtube\\.com/@([^/?#\\s]+)",
                                              NSRegularExpressionCaseInsensitive, text);
    if (name.length == 0)
        return nil;
    name = name.stringByRemovingPercentEncoding ?: name;
    return [@"@" stringByAppendingString:name.lowercaseString];
}

+ (NSString *)normalizedEntryFromInput:(NSString *)input
{
    NSString *text = TrimmedChannelText(input);
    if (text.length == 0 || IsGeneratedActionLabel(text))
        return nil;
    return [self channelIDFromInput:text] ?: [self normalizedHandle:text] ?: text;
}

+ (GNRChannelEntryKind)kindOfEntry:(NSString *)entry
{
    if (entry.length == 0)
        return GNRChannelEntryKindName;
    if ([[self channelIDFromInput:entry] isEqualToString:entry])
        return GNRChannelEntryKindID;
    if ([[self normalizedHandle:entry] isEqualToString:entry])
        return GNRChannelEntryKindHandle;
    return GNRChannelEntryKindName;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _entries                 = [NSMutableSet set];
        _labels                  = [NSMutableDictionary dictionary];
        BOOL changed             = NO;
        for (id value in [defaults arrayForKey:BlockedChannelsDefaultsKey])
        {
            NSString *entry = [ChannelManager normalizedEntryFromInput:value];
            if (!entry)
            {
                changed = YES;
                continue;
            }
            if (![entry isEqual:value])
                changed = YES;
            [_entries addObject:entry];
        }
        NSDictionary *storedLabels = [defaults dictionaryForKey:ChannelLabelsDefaultsKey];
        for (id key in storedLabels)
        {
            id label = storedLabels[key];
            if ([key isKindOfClass:[NSString class]] && [label isKindOfClass:[NSString class]] &&
                [_entries containsObject:key])
                _labels[key] = label;
        }
        [self rebuildLookups];
        if (changed)
            [self saveBlockedChannels];
    }
    return self;
}

- (void)rebuildLookups
{
    NSMutableSet *ids     = [NSMutableSet set];
    NSMutableSet *handles = [NSMutableSet set];
    NSMutableSet *names   = [NSMutableSet set];
    for (NSString *entry in self.entries)
    {
        switch ([ChannelManager kindOfEntry:entry])
        {
            case GNRChannelEntryKindID:
                [ids addObject:entry];
                break;
            case GNRChannelEntryKindHandle:
                [handles addObject:entry];
                break;
            default:
            {
                NSString *key = ChannelLookupKey(entry);
                if (key.length > 0)
                    [names addObject:key];
                break;
            }
        }
    }
    self.idLookup     = ids;
    self.handleLookup = handles;
    self.nameLookup   = names;
}

- (NSArray<NSString *> *)blockedChannels
{
    return [[self.entries allObjects]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)addBlockedChannel:(NSString *)channelName
{
    [self addBlockedChannel:channelName label:nil];
}

- (void)addBlockedChannel:(NSString *)channelName label:(NSString *)label
{
    NSString *entry = [ChannelManager normalizedEntryFromInput:channelName];
    if (!entry)
        return;
    GNRChannelEntryKind kind    = [ChannelManager kindOfEntry:entry];
    BOOL                changed = NO;
    if (![self isChannelBlocked:entry])
    {
        [self.entries addObject:entry];
        changed = YES;
    }
    NSString *cleanLabel = TrimmedChannelText(label);
    if (kind != GNRChannelEntryKindName && cleanLabel.length > 0 &&
        !IsGeneratedActionLabel(cleanLabel) && ![cleanLabel isEqualToString:entry] &&
        ![self.labels[entry] isEqualToString:cleanLabel])
    {
        self.labels[entry] = cleanLabel;
        changed            = YES;
    }
    if (changed)
    {
        [self rebuildLookups];
        [self saveBlockedChannels];
    }
    // 名前登録のときだけ従来どおり名前付きで通知する。ID・ハンドルは全体を再評価させる
    FeedMetadataRecord *metadata =
        kind == GNRChannelEntryKindName ? [[FeedMetadataRecord alloc] initWithVideoID:nil
                                                                                title:nil
                                                                              channel:entry]
                                        : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:FeedFilterStateDidChangeNotification
                                                        object:metadata];
}

- (void)removeBlockedChannel:(NSString *)channelName
{
    NSString *entry = [ChannelManager normalizedEntryFromInput:channelName];
    if (!entry)
        return;
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    if ([ChannelManager kindOfEntry:entry] == GNRChannelEntryKindName)
    {
        NSString *key = ChannelLookupKey(entry);
        for (NSString *value in self.entries)
        {
            if ([ChannelManager kindOfEntry:value] == GNRChannelEntryKindName &&
                [ChannelLookupKey(value) isEqualToString:key])
                [removed addObject:value];
        }
    }
    else if ([self.entries containsObject:entry])
    {
        [removed addObject:entry];
    }
    if (removed.count == 0)
        return;
    for (NSString *value in removed)
    {
        [self.entries removeObject:value];
        [self.labels removeObjectForKey:value];
    }
    [self rebuildLookups];
    [self saveBlockedChannels];
    [[NSNotificationCenter defaultCenter] postNotificationName:FeedFilterStateDidChangeNotification
                                                        object:nil];
}

- (BOOL)isChannelBlocked:(NSString *)channelName
{
    NSString *entry = [ChannelManager normalizedEntryFromInput:channelName];
    if (!entry)
        return NO;
    switch ([ChannelManager kindOfEntry:entry])
    {
        case GNRChannelEntryKindID:
            return [self.idLookup containsObject:entry];
        case GNRChannelEntryKindHandle:
            return [self.handleLookup containsObject:entry];
        default:
            return [self.nameLookup containsObject:ChannelLookupKey(entry)];
    }
}

- (BOOL)isChannelBlockedWithID:(NSString *)channelID
                        handle:(NSString *)handle
                          name:(NSString *)name
{
    NSSet<NSString *> *ids     = self.idLookup;
    NSSet<NSString *> *handles = self.handleLookup;
    NSSet<NSString *> *names   = self.nameLookup;
    if (ids.count == 0 && handles.count == 0 && names.count == 0)
        return NO;

    if ([channelID isKindOfClass:[NSString class]] && channelID.length > 0 &&
        [ids containsObject:channelID])
        return YES;
    if (handles.count > 0 && [handle isKindOfClass:[NSString class]] && handle.length > 0 &&
        [handles containsObject:handle.lowercaseString])
        return YES;
    if (![name isKindOfClass:[NSString class]] || name.length == 0)
        return NO;
    // Shortsではチャンネル名として "@handle" が入ってくる
    if (handles.count > 0 && [name hasPrefix:@"@"] && [handles containsObject:name.lowercaseString])
        return YES;
    return names.count > 0 && [names containsObject:ChannelLookupKey(name)];
}

- (NSString *)labelForChannel:(NSString *)entry
{
    return entry.length > 0 ? self.labels[entry] : nil;
}

- (NSDictionary<NSString *, NSString *> *)channelLabels
{
    return [self.labels copy];
}

- (void)setChannelLabels:(NSDictionary<NSString *, NSString *> *)labels
{
    NSMutableDictionary *valid = [NSMutableDictionary dictionary];
    for (id key in labels)
    {
        id label = labels[key];
        if ([key isKindOfClass:[NSString class]] && [label isKindOfClass:[NSString class]] &&
            [self.entries containsObject:key])
            valid[key] = label;
    }
    self.labels = valid;
    [self saveBlockedChannels];
}

- (void)saveBlockedChannels
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[self.entries allObjects] forKey:BlockedChannelsDefaultsKey];
    [defaults setObject:[self.labels copy] forKey:ChannelLabelsDefaultsKey];
    [defaults synchronize];
}

- (void)setBlockedChannels:(NSArray<NSString *> *)channels
{
    self.entries = [NSMutableSet set];
    for (id value in channels)
    {
        NSString *entry = [ChannelManager normalizedEntryFromInput:value];
        if (entry)
            [self.entries addObject:entry];
    }
    for (NSString *key in self.labels.allKeys)
    {
        if (![self.entries containsObject:key])
            [self.labels removeObjectForKey:key];
    }
    [self rebuildLookups];
    [self saveBlockedChannels];
    [[NSNotificationCenter defaultCenter] postNotificationName:FeedFilterStateDidChangeNotification
                                                        object:nil];
}

@end