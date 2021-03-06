#import "MatchaObjcBridge.h"
#import "MatchaBridge.h"
#import "MatchaBuildNode.h"
#import "MatchaViewController_Private.h"
#import "MatchaDeadlockLogger.h"
#import "MatchaProtobuf.h"
#import <CoreText/CoreText.h>

@implementation MatchaObjcBridge_X

+ (NSMapTable *)viewControllers {
    static NSMapTable *sMapTable;
    static dispatch_once_t sOnce;
    dispatch_once(&sOnce, ^{
        sMapTable = [NSMapTable strongToWeakObjectsMapTable];
    });
    return sMapTable;
}

+ (void)configure {
    static dispatch_once_t sOnce = 0;
    dispatch_once(&sOnce, ^{
        [MatchaDeadlockLogger sharedLogger]; // Initialize
        
        MatchaObjcBridge_X *x = [[MatchaObjcBridge_X alloc] init];
        [[MatchaObjcBridge sharedBridge] setObject:x forKey:@""];
    
        static CADisplayLink *displayLink = nil;
        if (displayLink == nil) {
            displayLink = [CADisplayLink displayLinkWithTarget:x selector:@selector(screenUpdate)];
    //        displayLink.preferredFramesPerSecond = 1;
            [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
        
        MatchaGoValue *screenScaleFunc = [[MatchaGoValue alloc] initWithFunc:@"gomatcha.io/matcha/internal/device setScreenScale"];
        [screenScaleFunc call:nil, [[MatchaGoValue alloc] initWithDouble:UIScreen.mainScreen.scale], nil];

        [[NSNotificationCenter defaultCenter] addObserver:x selector:@selector(didChangeOrientation:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
        [x didChangeOrientation:nil];
    });
}

- (MatchaGoValue *)sizeForAttributedString:(NSData *)protobuf maxLines:(int)maxLines {
    MatchaPBSizeFunc *func = [[MatchaPBSizeFunc alloc] initWithData:protobuf error:nil];
    
    NSAttributedString *attrStr = [[NSAttributedString alloc] initWithProtobuf:func.text];
    
    CGFloat maximumHeight = func.maxSize.toCGSize.height;
    if (maximumHeight > 1e7) {
        maximumHeight = 1e7;
    }
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, func.maxSize.toCGSize.width, maximumHeight)];
    CTFramesetterRef framesetterRef = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrStr);
    CTFrameRef frameRef = CTFramesetterCreateFrame(framesetterRef, CFRangeMake(0, 0), path.CGPath, NULL);
    CFArrayRef linesRef = CTFrameGetLines(frameRef);
    
    CFIndex count = CFArrayGetCount(linesRef);
    CGPoint origins[count];
    CTFrameGetLineOrigins(frameRef, CFRangeMake(0, count), origins);
    
    // transform to flip coordinate
    CGAffineTransform transform = CGAffineTransformMakeTranslation(0, 1e7);
    transform = CGAffineTransformScale(transform, 1, -1);
    
    CGFloat maxWidth = 0;
    CGFloat maxHeight = 0;
    if (maxLines == 0) {
        maxLines = (int)count;
    }
    for (NSInteger i = 0; i < MIN(maxLines, count); i++) {
        CGPoint flipped = CGPointApplyAffineTransform(origins[i], transform);
        CGFloat ascent, descent, leading;
        CGFloat width = CTLineGetTypographicBounds(CFArrayGetValueAtIndex(linesRef, i), &ascent, &descent, &leading);
        if (width > maxWidth) {
            maxWidth = flipped.x + width;
        }
        if (flipped.y + descent > maxHeight) {
            maxHeight = flipped.y + descent;
        }
    }
    
    CFRelease(framesetterRef);
    CFRelease(frameRef);
    
    MatchaLayoutPBPoint *point = [[MatchaLayoutPBPoint alloc] initWithCGSize:CGSizeMake(ceil(maxWidth), ceil(maxHeight))];
    return [[MatchaGoValue alloc] initWithData:point.data];
}

- (void)screenUpdate {
    static MatchaGoValue *updateFunc = nil;
    if (updateFunc == nil) {
        updateFunc = [[MatchaGoValue alloc] initWithFunc:@"gomatcha.io/matcha/animate screenUpdate"];
    }
    [updateFunc call:nil, nil];
}

- (bool)updateId:(NSInteger)identifier withProtobuf:(NSData *)protobuf {
    NSMapTable *mapTable = [MatchaObjcBridge_X viewControllers];
    MatchaViewController *vc = [mapTable objectForKey:@(identifier)];
    if (vc == nil) {
        return false;
    }
    
    MatchaViewPBRoot *pbroot = [[MatchaViewPBRoot alloc] initWithData:protobuf error:nil];
    [vc update:pbroot];
    return true;
}

- (NSString *)assetsDir {
     return [[NSBundle mainBundle] resourcePath];
}

- (MatchaGoValue *)imageForResource:(NSString *)path {
    UIImage *image = [UIImage imageNamed:path];
    if (image == nil) {
        return nil;
    }
    NSData *data = UIImagePNGRepresentation(image);
    return [[MatchaGoValue alloc] initWithData:data];
}

- (MatchaGoValue *)propertiesForResource:(NSString *)path {
    UIImage *image = [UIImage imageNamed:path];
    if (image == nil) {
        return nil;
    }
    MatchaPBImageProperties *props = [[MatchaPBImageProperties alloc] init];
    props.width = ceil(image.size.width * image.scale);
    props.height = ceil(image.size.height * image.scale);
    props.scale = image.scale;
    return [[MatchaGoValue alloc] initWithData:props.data];
}

- (void)displayAlert:(NSData *)protobuf {
    MatchaViewPBAlert *pbalert = [[MatchaViewPBAlert alloc] initWithData:protobuf error:nil];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:pbalert.title message:pbalert.message preferredStyle:UIAlertControllerStyleAlert];
    for (NSInteger i = 0; i < pbalert.buttonsArray.count; i++) {
        MatchaViewPBAlertButton *button = pbalert.buttonsArray[i];
        UIAlertAction *action = [UIAlertAction actionWithTitle:button.title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            MatchaGoValue *onPress = [[MatchaGoValue alloc] initWithFunc:@"gomatcha.io/matcha/view/alert onPress"];
            [onPress call:nil, [[MatchaGoValue alloc] initWithLongLong:pbalert.id_p], [[MatchaGoValue alloc] initWithLongLong:i], nil];
        }];
        [alert addAction:action];
    }
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (BOOL)openURL:(NSString *)url {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
#pragma GCC diagnostic pop
}

- (int)orientation {
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (orientation == UIInterfaceOrientationPortrait) {
        return 0;
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        return 1;
    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        return 2;
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        return 3;
    }
    return 0;
}

- (void)didChangeOrientation:(NSNotification *)note {
    static MatchaGoValue *orientationFunc = nil;
    if (orientationFunc == nil) {
        orientationFunc = [[MatchaGoValue alloc] initWithFunc:@"gomatcha.io/matcha/application SetOrientation"];
    }
    [orientationFunc call:nil, [[MatchaGoValue alloc] initWithInt:self.orientation], nil];
}

@end
