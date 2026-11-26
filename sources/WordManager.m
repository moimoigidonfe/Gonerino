#import "WordManager.h"

#import "Localization.h"
#import "Util.h"

typedef NS_ENUM(NSInteger, GNRWordScope) {
    GNRWordScopeAny = 0,
    GNRWordScopeTitle,
    GNRWordScopeChannel,
};

static NSString *TrimmedWord(id value)
{
    if (![value isKindOfClass:[NSString class]])
        return nil;
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Rule

@interface GNRWordRule : NSObject
@property (nonatomic) BOOL                         exception;
@property (nonatomic) GNRWordScope                 scope;
@property (nonatomic, copy) NSString              *literal;
@property (nonatomic, strong) NSRegularExpression *regex;
@end

@implementation GNRWordRule

+ (instancetype)ruleWithString:(NSString *)raw error:(NSError **)error
{
    NSString    *text = TrimmedWord(raw);
    GNRWordRule *rule = [GNRWordRule new];
    if ([text hasPrefix:@"!"])
    {
        rule.exception = YES;
        text           = TrimmedWord([text substringFromIndex:1]);
    }
    NSString *lower = text.lowercaseString;
    if ([lower hasPrefix:@"title:"])
    {
        rule.scope = GNRWordScopeTitle;
        text       = TrimmedWord([text substringFromIndex:6]);
    }
    else if ([lower hasPrefix:@"channel:"])
    {
        rule.scope = GNRWordScopeChannel;
        text       = TrimmedWord([text substringFromIndex:8]);
    }
    if (text.length == 0)
    {
        if (error)
            *error = [NSError errorWithDomain:@"GonerinoWordRule"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey : @"Empty rule"}];
        return nil;
    }

    // /pattern/flags 形式は正規表現（flags は i, m, s）
    NSRange lastSlash = [text rangeOfString:@"/" options:NSBackwardsSearch];
    if ([text hasPrefix:@"/"] && lastSlash.location >= 2)
    {
        NSString       *flags = [text substringFromIndex:lastSlash.location + 1];
        NSCharacterSet *invalidFlags =
            [[NSCharacterSet characterSetWithCharactersInString:@"ims"] invertedSet];
        if ([flags rangeOfCharacterFromSet:invalidFlags].location == NSNotFound)
        {
            NSRegularExpressionOptions options = 0;
            if ([flags containsString:@"i"])
                options |= NSRegularExpressionCaseInsensitive;
            if ([flags containsString:@"m"])
                options |= NSRegularExpressionAnchorsMatchLines;
            if ([flags containsString:@"s"])
                options |= NSRegularExpressionDotMatchesLineSeparators;
            NSString *pattern =
                [text substringWithRange:NSMakeRange(1, lastSlash.location - 1)];
            rule.regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                   options:options
                                                                     error:error];
            return rule.regex ? rule : nil;
        }
    }

    rule.literal = text.lowercaseString;
    return rule;
}

- (BOOL)matchesText:(NSString *)text lowercase:(NSString *)lowercase
{
    if (text.length == 0)
        return NO;
    if (self.regex)
        return [self.regex rangeOfFirstMatchInString:text
                                             options:0
                                               range:NSMakeRange(0, text.length)]
                   .location != NSNotFound;
    return [lowercase containsString:self.literal];
}

- (BOOL)matchesTitle:(NSString *)title
      lowercaseTitle:(NSString *)lowercaseTitle
             channel:(NSString *)channel
    lowercaseChannel:(NSString *)lowercaseChannel
{
    if (self.scope != GNRWordScopeChannel && [self matchesText:title lowercase:lowercaseTitle])
        return YES;
    if (self.scope != GNRWordScopeTitle && [self matchesText:channel lowercase:lowercaseChannel])
        return YES;
    return NO;
}

@end

#pragma mark - Rule set

@interface GNRWordRuleSet : NSObject
@property (nonatomic, copy) NSArray<GNRWordRule *>             *blockRules;
@property (nonatomic, copy) NSArray<GNRWordRule *>             *exceptionRules;
@property (nonatomic, strong) NSCache<NSString *, NSNumber *>  *resultCache;
@end

@implementation GNRWordRuleSet
@end

#pragma mark - Manager

@interface WordManager ()
@property (nonatomic, strong) NSMutableSet<NSString *> *blockedWordSet;
@property (strong) GNRWordRuleSet                      *ruleSet;
@end

@implementation WordManager

+ (instancetype)sharedInstance
{
    static WordManager    *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

+ (BOOL)validateRule:(NSString *)rule error:(NSError **)error
{
    return [GNRWordRule ruleWithString:rule error:error] != nil;
}

+ (NSString *)summaryForRule:(NSString *)rule
{
    GNRWordRule *parsed = [GNRWordRule ruleWithString:rule error:nil];
    if (!parsed)
        return LocalizedString(@"Invalid rule (ignored)");
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (parsed.exception)
        [parts addObject:LocalizedString(@"Exception")];
    if (parsed.regex)
        [parts addObject:LocalizedString(@"Regex")];
    if (parsed.scope == GNRWordScopeTitle)
        [parts addObject:LocalizedString(@"Title only")];
    else if (parsed.scope == GNRWordScopeChannel)
        [parts addObject:LocalizedString(@"Channel name only")];
    return parts.count > 0 ? [parts componentsJoinedByString:@" · "] : nil;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _blockedWordSet = [NSMutableSet set];
        for (id value in
             [[NSUserDefaults standardUserDefaults] arrayForKey:@"GonerinoBlockedWords"])
        {
            NSString *word = TrimmedWord(value);
            if (word.length > 0)
                [_blockedWordSet addObject:word];
        }
        [self rebuildRules];
    }
    return self;
}

- (void)rebuildRules
{
    NSMutableArray<GNRWordRule *> *blockRules     = [NSMutableArray array];
    NSMutableArray<GNRWordRule *> *exceptionRules = [NSMutableArray array];
    for (NSString *word in self.blockedWordSet)
    {
        GNRWordRule *rule = [GNRWordRule ruleWithString:word error:nil];
        if (!rule)
            continue;
        if (rule.exception)
            [exceptionRules addObject:rule];
        else
            [blockRules addObject:rule];
    }
    GNRWordRuleSet *ruleSet        = [GNRWordRuleSet new];
    ruleSet.blockRules             = blockRules;
    ruleSet.exceptionRules         = exceptionRules;
    ruleSet.resultCache            = [NSCache new];
    ruleSet.resultCache.countLimit = 2048;
    self.ruleSet                   = ruleSet;
}

- (NSArray<NSString *> *)blockedWords
{
    return [[self.blockedWordSet allObjects]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)addBlockedWord:(NSString *)word
{
    NSString *normalizedWord = TrimmedWord(word);
    if (normalizedWord.length == 0)
        return;
    [self.blockedWordSet addObject:normalizedWord];
    [self rebuildRules];
    [self saveBlockedWords];
    [[NSNotificationCenter defaultCenter] postNotificationName:FeedFilterStateDidChangeNotification
                                                        object:nil];
}

- (void)removeBlockedWord:(NSString *)word
{
    if (!word)
        return;
    [self.blockedWordSet removeObject:word];
    [self rebuildRules];
    [self saveBlockedWords];
    [[NSNotificationCenter defaultCenter] postNotificationName:FeedFilterStateDidChangeNotification
                                                        object:nil];
}

- (BOOL)isWordBlocked:(NSString *)text
{
    return [self isBlockedTitle:text channel:nil];
}

- (BOOL)isBlockedTitle:(NSString *)title channel:(NSString *)channel
{
    GNRWordRuleSet *ruleSet = self.ruleSet;
    if (ruleSet.blockRules.count == 0)
        return NO;
    NSString *titleText   = [title isKindOfClass:[NSString class]] ? title : @"";
    NSString *channelText = [channel isKindOfClass:[NSString class]] ? channel : @"";
    if (titleText.length == 0 && channelText.length == 0)
        return NO;

    NSString *cacheKey = [NSString stringWithFormat:@"%@\n%@", titleText, channelText];
    NSNumber *cached   = [ruleSet.resultCache objectForKey:cacheKey];
    if (cached)
        return cached.boolValue;

    NSString *lowercaseTitle   = titleText.lowercaseString;
    NSString *lowercaseChannel = channelText.lowercaseString;
    BOOL      excepted         = NO;
    for (GNRWordRule *rule in ruleSet.exceptionRules)
    {
        if ([rule matchesTitle:titleText
                  lowercaseTitle:lowercaseTitle
                         channel:channelText
                lowercaseChannel:lowercaseChannel])
        {
            excepted = YES;
            break;
        }
    }
    BOOL blocked = NO;
    if (!excepted)
    {
        for (GNRWordRule *rule in ruleSet.blockRules)
        {
            if ([rule matchesTitle:titleText
                      lowercaseTitle:lowercaseTitle
                             channel:channelText
                    lowercaseChannel:lowercaseChannel])
            {
                blocked = YES;
                break;
            }
        }
    }
    [ruleSet.resultCache setObject:@(blocked) forKey:cacheKey];
    return blocked;
}

- (void)saveBlockedWords
{
    [[NSUserDefaults standardUserDefaults] setObject:[self.blockedWordSet allObjects]
                                              forKey:@"GonerinoBlockedWords"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setBlockedWords:(NSArray<NSString *> *)words
{
    self.blockedWordSet = [NSMutableSet set];
    for (id value in words)
    {
        NSString *word = TrimmedWord(value);
        if (word.length > 0)
            [self.blockedWordSet addObject:word];
    }
    [self rebuildRules];
    [self saveBlockedWords];
    [[NSNotificationCenter defaultCenter] postNotificationName:FeedFilterStateDidChangeNotification
                                                        object:nil];
}

@end