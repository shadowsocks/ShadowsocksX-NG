//
//  QRCodeUtils.m
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/8.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>

void ScanQRCodeOnScreen() {
    /* displays[] Quartz display ID's */
    CGDirectDisplayID   *displays = nil;
    
    CGError             err = CGDisplayNoErr;
    CGDisplayCount      dspCount = 0;
    
    /* How many active displays do we have? */
    err = CGGetActiveDisplayList(0, NULL, &dspCount);
    
    /* If we are getting an error here then their won't be much to display. */
    if(err != CGDisplayNoErr)
    {
        NSLog(@"Could not get active display count (%d)\n", err);
        return;
    }
    
    /* Allocate enough memory to hold all the display IDs we have. */
    displays = calloc((size_t)dspCount, sizeof(CGDirectDisplayID));
    
    // Get the list of active displays
    err = CGGetActiveDisplayList(dspCount,
                                 displays,
                                 &dspCount);
    
    /* More error-checking here. */
    if(err != CGDisplayNoErr)
    {
        NSLog(@"Could not get active display list (%d)\n", err);
        return;
    }
    
    NSMutableArray* foundSSUrls = [NSMutableArray array];
    
    CIDetector *detector = [CIDetector detectorOfType:@"CIDetectorTypeQRCode"
                                              context:nil
                                              options:@{ CIDetectorAccuracy:CIDetectorAccuracyHigh }];
    
    for (unsigned int displaysIndex = 0; displaysIndex < dspCount; displaysIndex++)
    {
        /* Make a snapshot image of the current display. */
        CGImageRef image = CGDisplayCreateImage(displays[displaysIndex]);
        NSArray *features = [detector featuresInImage:[CIImage imageWithCGImage:image]];
        for (CIQRCodeFeature *feature in features) {
            NSLog(@"%@", feature.messageString);
            if ( [feature.messageString hasPrefix:@"ss://"] )
            {
                [foundSSUrls addObject:[NSURL URLWithString:feature.messageString]];
            }
        }
         CGImageRelease(image);
    }
    
    free(displays);
    
    [[NSNotificationCenter defaultCenter]
     postNotificationName:@"NOTIFY_FOUND_SS_URL"
     object:nil
     userInfo: @{ @"urls": foundSSUrls,
                  @"source": @"qrcode"
                 }
     ];
}
