#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "GCDWebServer.h"
#import "GCDWebServerConnection.h"
#import "GCDWebServerFunctions.h"
#import "GCDWebServerHTTPStatusCodes.h"
#import "GCDWebServerRequest.h"
#import "GCDWebServerResponse.h"
#import "GCDWebServerDataRequest.h"
#import "GCDWebServerFileRequest.h"
#import "GCDWebServerMultiPartFormRequest.h"
#import "GCDWebServerURLEncodedFormRequest.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"
#import "GCDWebServerFileResponse.h"
#import "GCDWebServerStreamedResponse.h"

FOUNDATION_EXPORT double GCDWebServerVersionNumber;
FOUNDATION_EXPORT const unsigned char GCDWebServerVersionString[];

