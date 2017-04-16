//
//  QRCodeUtils.h
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/8.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

#ifndef QRCodeUtils_h
#define QRCodeUtils_h

void ScanQRCodeOnScreen();

NSString* decode64(NSString* str);

NSString* encode64(NSString* str);

NSDictionary<NSString*, id>* ParseAppURLSchemes(NSURL* url);

static NSDictionary<NSString*, id>* ParseSSURL(NSURL* url);

static NSDictionary<NSString*, id>* ParseSSRURL(NSURL* url);

static NSDictionary<NSString*, id>* parseSSRLastParam(NSString* lastParam);

#endif /* QRCodeUtils_h */
