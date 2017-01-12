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
    [self setQRCode:self.qrCode];
}

- (void)setQRCode:(NSString*) qrCode {
    CGImageRef cgImgRef = [self createQRImageForString:qrCode size:CGSizeMake(250, 250)];
    
    NSImage *image = [[NSImage alloc]initWithCGImage:cgImgRef size:CGSizeMake(250, 250)];
    self.imageView.image = image;
}

- (CGImageRef)createQRImageForString:(NSString *)string size:(CGSize)size {
    // Setup the QR filter with our string
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    [filter setValue:data forKey:@"inputMessage"];
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
    CIContext *context = [CIContext contextWithOptions:nil];
#else
    CIContext *context = [CIContext contextWithCGContext:bitmapRef options:nil];
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

@end
