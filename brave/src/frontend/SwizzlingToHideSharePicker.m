#import "SwizzlingToHideSharePicker.h"
#import <UIKit/UIKit.h>
#import "Swizzling.h"

bool hackyHide = false;
__weak UIViewController *currentActivityView = nil;

@implementation UIActivityViewController(Cancel)
+ (void)load
{
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        SwizzleInstanceMethods(self.class, @selector(viewWillAppear:), @selector(_viewWillAppear:));
    });
}

void forceAlpha(CGFloat alpha)
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        currentActivityView.view.superview.superview.alpha = alpha;
    } else {
        currentActivityView.view.superview.alpha = alpha;
    }
}

+ (void)hackyHideSharePickerOn:(bool)on
{
    hackyHide = on;
    if (!on && currentActivityView) {
        forceAlpha(1.0);
    }
}

-(void)_viewWillAppear:(BOOL)animated
{
    if (hackyHide) {
        currentActivityView = self;
        forceAlpha(0.0);
    }
    [self _viewWillAppear:animated];
}

+(void)hackyDismissal
{
    if (currentActivityView) {
        [currentActivityView dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
