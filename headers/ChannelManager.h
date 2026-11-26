#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GNRChannelEntryKind) {
    GNRChannelEntryKindName = 0,
    GNRChannelEntryKindID,
    GNRChannelEntryKindHandle,
};

@interface ChannelManager : NSObject

+ (instancetype)sharedInstance;

// "UC…" / ".../channel/UC…" からチャンネルIDを取り出す。該当しなければ nil
+ (NSString *)channelIDFromInput:(NSString *)input;
// "@Handle" / "/@handle" / "youtube.com/@handle/..." を "@handle"(小文字) にする。該当しなければ nil
+ (NSString *)normalizedHandle:(NSString *)input;
// ID・ハンドルならその正規形、それ以外はトリムした名前。空なら nil
+ (NSString *)normalizedEntryFromInput:(NSString *)input;
+ (GNRChannelEntryKind)kindOfEntry:(NSString *)entry;

- (NSArray<NSString *> *)blockedChannels;
- (void)addBlockedChannel:(NSString *)channelName;
- (void)addBlockedChannel:(NSString *)channelName label:(NSString *)label;
- (void)removeBlockedChannel:(NSString *)channelName;
- (BOOL)isChannelBlocked:(NSString *)channelName;
- (BOOL)isChannelBlockedWithID:(NSString *)channelID
                        handle:(NSString *)handle
                          name:(NSString *)name;
- (void)setBlockedChannels:(NSArray<NSString *> *)channels;

// ID・ハンドル登録に付ける表示用の名前
- (NSString *)labelForChannel:(NSString *)entry;
- (NSDictionary<NSString *, NSString *> *)channelLabels;
- (void)setChannelLabels:(NSDictionary<NSString *, NSString *> *)labels;

@end