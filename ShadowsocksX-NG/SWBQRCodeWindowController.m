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
    CGImageRef cgImgRef = [self createQRImageForString:qrCode size:CGSizeMake(250, 250)];
    
    NSImage *image = [[NSImage alloc]initWithCGImage:cgImgRef size:CGSizeMake(250, 250)];
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

- (CGImageRef)createQRImageForString:(NSString *)string size:(CGSize)size {
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
    
    // Since CoreImage nicely interpolates, we need to create a bitmap image that we'll draw into
    // a bitmap context at the desired size;
    size_t width = CGRectGetWidth(extent) * scale;
    size_t height = CGRectGetHeight(extent) * scale;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef bitmapRef = CGBitmapContextCreate(nil, width, height, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaNone);
    
#if TARGET_OS_IPHONE
    CIContext *context = [CIContext contextWithOptions: @{kCIContextUseSoftwareRenderer: true}];
#else
    CIContext *context = [CIContext contextWithCGContext:bitmapRef options:@{kCIContextUseSoftwareRenderer: @true}];
#endif
    
    CGImageRef bitmapImage = [context createCGImage:image fromRect:extent];
    
    CGContextSetInterpolationQuality(bitmapRef, kCGInterpolationNone);
    CGContextScaleCTM(bitmapRef, scale, scale);
    CGContextDrawImage(bitmapRef, extent, bitmapImage);
    
    // Create an image with the contents of our bitmap
    CGImageRef scaledImage = CGBitmapContextCreateImage(bitmapRef);
    
    // Cleanup
    CGContextRelease(bitmapRef);
    CGImageRelease(bitmapImage);
    
    return scaledImage;
}

- (IBAction) copyQRCode: (id) sender{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    NSArray *copiedObjects = [NSArray arrayWithObject: self.imageView.image];
    [pasteboard writeObjects:copiedObjects];
}

- (void)flagsChanged:(NSEvent *)event {
    NSUInteger modifiers = event.modifierFlags & NSDeviceIndependentModifierFlagsMask;
    if (modifiers & NSAlternateKeyMask) {
        [self setQRCode:self.legacyQRCode withOverlayText:@"Legacy"];
    } else {
        [self setQRCode:self.qrCode withOverlayText:@"SIP002"];
    }
}

@end
