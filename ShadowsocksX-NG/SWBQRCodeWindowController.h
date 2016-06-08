//
//  QRCodeWindowController.h
//  shadowsocks
//
//  Created by clowwindy on 10/12/14.
//  Copyright (c) 2014 clowwindy. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface SWBQRCodeWindowController : NSWindowController <WebFrameLoadDelegate>

@property (nonatomic, strong) IBOutlet WebView *webView;
@property (nonatomic, copy) NSString *qrCode;

@end
