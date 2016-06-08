//
//  QRCodeWindowController.m
//  shadowsocks
//
//  Created by clowwindy on 10/12/14.
//  Copyright (c) 2014 clowwindy. All rights reserved.
//

#import "SWBQRCodeWindowController.h"

@interface SWBQRCodeWindowController ()

@end

@implementation SWBQRCodeWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [self.webView.mainFrame loadRequest:[NSURLRequest requestWithURL:[[NSBundle mainBundle] URLForResource:@"qrcode" withExtension:@"htm"]]];
    self.webView.frameLoadDelegate = self;
}

-(void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    if (self.qrCode) {
        [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"genCode('%@')", _qrCode]];
    }
}

-(void)dealloc {
    self.webView.frameLoadDelegate = nil;
}

@end
