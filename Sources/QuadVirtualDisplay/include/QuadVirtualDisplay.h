#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
/// Runtime-checked private API boundary. Merely asking for support creates no display.
@interface QDVirtualDisplayHandle : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
+ (NSString *)supportProblem;
- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
