// Main.m - AFLATOON
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include "Shared.h"

__attribute__((constructor)) static void ap_entry(void) {
    ap_install_hooks();
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ap_ui_start(); });
    }];
}
