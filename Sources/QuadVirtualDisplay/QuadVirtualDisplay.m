#import "QuadVirtualDisplay.h"
#import <objc/runtime.h>

// Private selector signatures verified against DeskPad's CGVirtualDisplayPrivate.h:
// https://github.com/Stengo/DeskPad/blob/main/DeskPad/CGVirtualDisplayPrivate.h
// Classes are looked up by name; there are no private class-symbol link dependencies.
@interface NSObject (QDVirtualDisplaySelectors)
- (void)setName:(NSString *)name;
- (void)setMaxPixelsWide:(unsigned int)value;
- (void)setMaxPixelsHigh:(unsigned int)value;
- (void)setSizeInMillimeters:(CGSize)value;
- (void)setVendorID:(unsigned int)value;
- (void)setProductID:(unsigned int)value;
- (void)setSerialNum:(unsigned int)value;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
- (void)setHiDPI:(unsigned int)value;
- (void)setModes:(NSArray *)modes;
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
- (CGDirectDisplayID)displayID;
@end

// Some macOS releases expose 32-bit mode dimensions, others use NSUInteger.
// Typed receiver declarations preserve ARC's initializer ownership in both cases.
@interface QDMode32 : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(CGFloat)rate;
@end
@interface QDMode64 : NSObject
- (instancetype)initWithWidth:(unsigned long long)width height:(unsigned long long)height refreshRate:(CGFloat)rate;
@end

@implementation QDVirtualDisplayHandle {
    id _display;
}
+ (NSString *)supportProblem {
    NSDictionary *requirements = @{
        @"CGVirtualDisplayDescriptor": @[@[@"init", @"@"], @[@"setName:", @"v", @"@"],
            @[@"setMaxPixelsWide:", @"v", @"I"], @[@"setMaxPixelsHigh:", @"v", @"I"],
            @[@"setSizeInMillimeters:", @"v", @(@encode(CGSize))], @[@"setVendorID:", @"v", @"I"],
            @[@"setProductID:", @"v", @"I"], @[@"setSerialNum:", @"v", @"I"],
            @[@"setDispatchQueue:", @"v", @(@encode(dispatch_queue_t))]],
        @"CGVirtualDisplayMode": @[@[@"initWithWidth:height:refreshRate:", @"@", @"I|Q", @"I|Q", @(@encode(CGFloat))]],
        @"CGVirtualDisplaySettings": @[@[@"init", @"@"], @[@"setHiDPI:", @"v", @"I"], @[@"setModes:", @"v", @"@"]],
        @"CGVirtualDisplay": @[@[@"initWithDescriptor:", @"@", @"@"], @[@"applySettings:", @(@encode(BOOL)), @"@"], @[@"displayID", @"I"]]
    };
    for (NSString *name in requirements) {
        Class cls = NSClassFromString(name);
        if (!cls) return [NSString stringWithFormat:@"%@ が見つかりません。", name];
        for (NSArray<NSString *> *spec in requirements[name]) {
            Method method = class_getInstanceMethod(cls, NSSelectorFromString(spec[0]));
            if (!method) return [NSString stringWithFormat:@"%@.%@ がありません。", name, spec[0]];
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (signature.numberOfArguments != spec.count || strcmp(signature.methodReturnType, spec[1].UTF8String) != 0)
                return [NSString stringWithFormat:@"%@.%@ の型が未対応です。", name, spec[0]];
            for (NSUInteger i = 2; i < spec.count; i++) {
                NSString *actual = [NSString stringWithUTF8String:[signature getArgumentTypeAtIndex:i]];
                if (![[spec[i] componentsSeparatedByString:@"|"] containsObject:actual])
                    return [NSString stringWithFormat:@"%@.%@ 引数%luの型 %@ は未対応です（%@）。", name, spec[0], (unsigned long)i-2, actual, spec[i]];
            }
            if ([name isEqualToString:@"CGVirtualDisplayMode"] &&
                strcmp([signature getArgumentTypeAtIndex:2], [signature getArgumentTypeAtIndex:3]) != 0)
                return @"仮想画面モードの幅と高さの引数型が一致しません。";
        }
    }
    return @"";
}
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error {
    NSString *problem = [QDVirtualDisplayHandle supportProblem];
    if (width < 640 || height < 480 || width > 4096 || height > 4096) problem = @"仮想画面サイズが範囲外です。";
    if (problem.length) {
        if (error) *error = [NSError errorWithDomain:@"QuadVirtualDisplay" code:1 userInfo:@{NSLocalizedDescriptionKey:problem}];
        return nil;
    }
    if (!(self = [super init])) return nil;
    id descriptor = [NSClassFromString(@"CGVirtualDisplayDescriptor") new];
    [descriptor setName:@"QuadDesk Native Preview"];
    [descriptor setMaxPixelsWide:(unsigned int)width];
    [descriptor setMaxPixelsHigh:(unsigned int)height];
    [descriptor setSizeInMillimeters:CGSizeMake(600, 375)];
    [descriptor setVendorID:0x5144]; [descriptor setProductID:0x5052];
    [descriptor setSerialNum:0x51505231]; [descriptor setDispatchQueue:dispatch_get_main_queue()];
    _display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
    id settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Method initializer = class_getInstanceMethod(modeClass, @selector(initWithWidth:height:refreshRate:));
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(initializer)];
    id mode;
    if (strcmp([signature getArgumentTypeAtIndex:2], "I") == 0)
        mode = [(QDMode32 *)[modeClass alloc] initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:60];
    else
        mode = [(QDMode64 *)[modeClass alloc] initWithWidth:width height:height refreshRate:60];
    [settings setHiDPI:0];
    if (mode) [settings setModes:@[mode]];
    if (!_display || !mode || ![_display applySettings:settings] || [_display displayID] == 0) {
        if (error) *error = [NSError errorWithDomain:@"QuadVirtualDisplay" code:2 userInfo:@{NSLocalizedDescriptionKey:@"仮想画面の作成に失敗しました。"}];
        return nil;
    }
    return self;
}
- (CGDirectDisplayID)displayID { return [_display displayID]; }
@end
