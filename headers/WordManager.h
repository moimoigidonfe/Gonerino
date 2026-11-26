#import <Foundation/Foundation.h>

@interface WordManager : NSObject

+ (instancetype)sharedInstance;
+ (BOOL)validateRule:(NSString *)rule error:(NSError **)error;
// 設定画面用の説明（"Regex" など）。通常の単語なら nil
+ (NSString *)summaryForRule:(NSString *)rule;

- (NSArray<NSString *> *)blockedWords;
- (void)addBlockedWord:(NSString *)word;
- (void)removeBlockedWord:(NSString *)word;
- (BOOL)isWordBlocked:(NSString *)text;
- (BOOL)isBlockedTitle:(NSString *)title channel:(NSString *)channel;
- (void)setBlockedWords:(NSArray<NSString *> *)words;

@end