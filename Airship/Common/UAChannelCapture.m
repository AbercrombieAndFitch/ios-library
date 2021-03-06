/*
 Copyright 2009-2015 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "UAChannelCapture.h"

#import "UAirship.h"
#import "UAPush.h"
#import "UAConfig.h"
#import "UA_Base64.h"

@interface UAChannelCapture()

@property (nonatomic, strong) NSURL *channelURL;
@property (nonatomic, strong) UIAlertView *alertView;
@property (nonatomic, strong) UAPush *push;
@property (nonatomic, strong) UAConfig *config;

@end

@implementation UAChannelCapture

NSString *const UAChannelBaseURL = @"https://go.urbanairship.com/";
NSString *const UAChannelPlaceHolder = @"CHANNEL";

- (instancetype)initWithConfig:(UAConfig *)config push:(UAPush *)push {
    self = [super init];
    if (self) {
        self.config = config;
        self.push = push;

        if (config.channelCaptureEnabled) {
            // App inactive/active for incoming calls, notification center, and taskbar
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(didBecomeActive)
                                                         name:UIApplicationDidBecomeActiveNotification
                                                       object:nil];
        }
    }

    return self;
}

+ (instancetype)channelCaptureWithConfig:(UAConfig *)config push:(UAPush *)push {
    return [[UAChannelCapture alloc] initWithConfig:config push:push];
}

- (void)didBecomeActive {
    // Magic can be slow
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [self checkClipboard];
    });
}

/**
 * Checks the clipboard for the token and displays an alert view if
 * the token is available.
 */
- (void)checkClipboard {
    if ([self.alertView isVisible]) {
        return;
    }

    if (!self.push.channelID) {
        return;
    }

    NSString *pasteBoardString = [UIPasteboard generalPasteboard].string;
    if (!pasteBoardString.length) {
        return;
    }

    NSData *base64Data = UA_dataFromBase64String(pasteBoardString);
    if (!base64Data) {
        return;
    }

    NSString *decodedPasteBoardString = [[NSString alloc] initWithData:base64Data encoding:NSUTF8StringEncoding];
    if (!decodedPasteBoardString.length) {
        return;
    }

    NSString *token = [self generateToken];
    if (![decodedPasteBoardString hasPrefix:token]) {
        return;
    }

    // Perform the magic

    // Generate the URL
    NSURL *url;
    if (decodedPasteBoardString.length > token.length) {
        // Generate the URL
        NSString *urlString = [decodedPasteBoardString stringByReplacingOccurrencesOfString:token
                                                                       withString:UAChannelBaseURL];

        urlString = [urlString stringByReplacingOccurrencesOfString:UAChannelPlaceHolder
                                                         withString:self.push.channelID];

        urlString = [urlString stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        url =[NSURL URLWithString:urlString];
    }

    // Display the alert view on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.alertView isVisible]) {
            return;
        }

        self.channelURL = url;
        self.alertView = [[UIAlertView alloc] initWithTitle:@"Channel ID"
                                                    message:self.push.channelID
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Copy", url == nil ? nil : @"Save", nil];

        [self.alertView show];
    });

    // Clear the clipboard
    [UIPasteboard generalPasteboard].string = @"";
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    UA_LTRACE(@"Button index %ld", (long)buttonIndex);

    if (buttonIndex == 1) {
        // Copy the channel
        [UIPasteboard generalPasteboard].string = self.push.channelID ?: @"";
        UA_LINFO(@"Copied channel %@ to the pasteboard", self.push.channelID);
    } else if (buttonIndex == 2 && self.channelURL) {
        // Open the channel URL
        [[UIApplication sharedApplication] openURL:self.channelURL];
        UA_LINFO(@"Opened url: %@", self.channelURL.absoluteString);
    }

    self.alertView = nil;
}

/**
 * Generates the expected clipboard token.
 *
 * @return The generated clipboard token.
 */
- (NSString *)generateToken {
    const char *keyCStr = [self.config.appKey cStringUsingEncoding:NSASCIIStringEncoding];
    size_t keyCstrLen = strlen(keyCStr);

    const char *secretCStr = [self.config.appSecret cStringUsingEncoding:NSASCIIStringEncoding];
    size_t secretCstrLen = strlen(secretCStr);

    NSMutableString *combined = [NSMutableString string];
    for (size_t i = 0; i < keyCstrLen; i++) {
        [combined appendFormat:@"%02x", (int)(keyCStr[i] ^ secretCStr[i % secretCstrLen])];
    }

    return combined;
}

@end
