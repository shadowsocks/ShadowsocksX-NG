//
//  QRCodeWindowController.m
//  shadowsocks
//
//  Created by clowwindy on 10/12/14.
//  Copyright (c) 2014 clowwindy. All rights reserved.
//

#import "SWBQRCodeWindowController.h"
@import CoreImage;

@interface SWBQRCodeWindowController ()

@end

@implementation SWBQRCodeWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [self setQRCode:self.qrCode withOverlayText:@"SIP002"];
}

- (void)setQRCode:(NSString*) qrCode withOverlayText: (NSString*) text {
    NSImage *image = [self createQRImageForString:qrCode size:NSMakeSize(250, 250)];
    
    if (text) {
        // Draw overlay text
        NSDictionary* attrs = @{
                                NSForegroundColorAttributeName: [NSColor colorWithRed:28/255.0 green:155/255.0 blue:71/255.0 alpha:1],
                                NSBackgroundColorAttributeName: [NSColor whiteColor],
                                NSFontAttributeName: [NSFont fontWithName:@"Helvetica" size:(CGFloat)16],
                                };
        NSMutableAttributedString* attrsText = [[NSMutableAttributedString alloc] initWithString: text
                                                                        attributes: attrs];
        
        [image lockFocus];
        [attrsText drawAtPoint: NSMakePoint(100, 5)];
        [image unlockFocus];
    }
    self.imageView.image = image;
}

- (NSImage*)createQRImageForString:(NSString *)string size:(NSSize)size {
    NSImage *outputImage = [[NSImage alloc]initWithSize:size];
    [outputImage lockFocus];
    
    // Setup the QR filter with our string
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    [filter setValue:data forKey:@"inputMessage"];
    /*
         L: 7%
         M: 15%
         Q: 25%
         H: 30%
     */
    [filter setValue:@"Q" forKey:@"inputCorrectionLevel"];
    
    CIImage *image = [filter valueForKey:@"outputImage"];
    
    // Calculate the size of the generated image and the scale for the desired image size
    CGRect extent = CGRectIntegral(image.extent);
    CGFloat scale = MIN(size.width / CGRectGetWidth(extent), size.height / CGRectGetHeight(extent));
    
    CGImageRef bitmapImage = [NSGraphicsContext.currentContext.CIContext createCGImage:image fromRect:extent];
    
    CGContextRef graphicsContext = NSGraphicsContext.currentContext.CGContext;
    
    CGContextSetInterpolationQuality(graphicsContext, kCGInterpolationNone);
    CGContextScaleCTM(graphicsContext, scale, scale);
    CGContextDrawImage(graphicsContext, extent, bitmapImage);
    
    // Cleanup
    CGImageRelease(bitmapImage);
    
    [outputImage unlockFocus];
    return outputImage;
}

- (IBAction) copyQRCode: (id) sender{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    NSArray *copiedObjects = [NSArray arrayWithObject: self.imageView.image];
    [pasteboard writeObjects:copiedObjects];
}

- (void)flagsChanged:(NSEvent *)event {
    NSUInteger modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (modifiers & NSEventModifierFlagOption) {
        [self setQRCode:self.legacyQRCode withOverlayText:@"Legacy"];
    } else {
        [self setQRCode:self.qrCode withOverlayText:@"SIP002"];
    }
}

@end
