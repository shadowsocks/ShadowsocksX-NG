//
//  PingManger.m
//  MacTool
//
//  Created by Rudy Yang on 2017/9/29.
//

#import "PingManager.h"
#import "SimplePing.h"

#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>

#pragma mark * Utilities

/*! Returns the string representation of the supplied address.
 *  \param address Contains a (struct sockaddr) with the address to render.
 *  \returns A string representation of that address.
 */

static NSString * displayAddressForAddress(NSData * address) {
    int         err;
    NSString *  result;
    char        hostStr[NI_MAXHOST];
    
    result = nil;
    
    if (address != nil) {
        err = getnameinfo(address.bytes, (socklen_t) address.length, hostStr, sizeof(hostStr), NULL, 0, NI_NUMERICHOST);
        if (err == 0) {
            result = @(hostStr);
        }
    }
    
    if (result == nil) {
        result = @"?";
    }
    
    return result;
}

/*! Returns a short error string for the supplied error.
 *  \param error The error to render.
 *  \returns A short string representing that error.
 */

static NSString * shortErrorFromError(NSError * error) {
    NSString *      result;
    NSNumber *      failureNum;
    int             failure;
    const char *    failureStr;
    
    assert(error != nil);
    
    result = nil;
    
    // Handle DNS errors as a special case.
    
    if ( [error.domain isEqual:(NSString *)kCFErrorDomainCFNetwork] && (error.code == kCFHostErrorUnknown) ) {
        failureNum = error.userInfo[(id) kCFGetAddrInfoFailureKey];
        if ( [failureNum isKindOfClass:[NSNumber class]] ) {
            failure = failureNum.intValue;
            if (failure != 0) {
                failureStr = gai_strerror(failure);
                if (failureStr != NULL) {
                    result = @(failureStr);
                }
            }
        }
    }
    
    // Otherwise try various properties of the error object.
    
    if (result == nil) {
        result = error.localizedFailureReason;
    }
    if (result == nil) {
        result = error.localizedDescription;
    }
    assert(result != nil);
    return result;
}


@interface PingManager() <SimplePingDelegate>

@property (nonatomic, assign, readwrite) BOOL                   forceIPv4;
@property (nonatomic, assign, readwrite) BOOL                   forceIPv6;
@property (nonatomic, strong, readwrite, nullable) SimplePing * pinger;
@property (nonatomic, strong, readwrite, nullable) NSTimer *    sendTimer;

@property (nonatomic, assign) NSTimeInterval ping;

@property (nonatomic, strong) NSDate *beginDate;

@property (strong, nonatomic) NSMutableDictionary *PingTimers;

@property (copy, nonatomic) void(^success)(NSInteger msCount);
@property (copy, nonatomic) void(^failure)();

@end

@implementation PingManager

- (void)dealloc {
    [self->_pinger stop];
    [self->_sendTimer invalidate];
}

- (BOOL)isValidIpAddress:(NSString *)ip {
    const char *utf8 = [ip UTF8String];
    
    // Check valid IPv4.
    struct in_addr dst;
    int success = inet_pton(AF_INET, utf8, &(dst.s_addr));
    if (success != 1) {
        // Check valid IPv6.
        struct in6_addr dst6;
        success = inet_pton(AF_INET6, utf8, &dst6);
    }
    return (success == 1);
}

- (void)pingHost:(NSString *)host success:(void(^)(NSInteger msCount))success failure:(void(^)())failure {
    
    const char *utf8 = [host UTF8String];
    struct in_addr dst;
    int isIPv4 = inet_pton(AF_INET, utf8, &(dst.s_addr));
    
    struct in6_addr dst6;
    int isIPv6 = inet_pton(AF_INET6, utf8, &dst6);
    self.forceIPv6 = NO;
    self.forceIPv4 = NO;
    if (isIPv4 == 1) {
        self.forceIPv4 = YES;
    } else if (isIPv6 == 1) {
        self.forceIPv6 = YES;
    } else {
        self.forceIPv4 = YES;
    }
    
    self.success = success;
    self.failure = failure;
    [self runWithHostName:host];
}

- (void)close {
    [self.sendTimer invalidate];
    self.sendTimer = nil;
    self.pinger = nil;
}
/*! The Objective-C 'main' for this program.
 *  \details This creates a SimplePing object, configures it, and then runs the run loop
 *      sending pings and printing the results.
 *  \param hostName The host to ping.
 */

- (void)runWithHostName:(NSString *)hostName {
    assert(self.pinger == nil);
    
    self.pinger = [[SimplePing alloc] initWithHostName:hostName];
    assert(self.pinger != nil);
    
    // By default we use the first IP address we get back from host resolution (.Any)
    // but these flags let the user override that.
    
    if (self.forceIPv4 && ! self.forceIPv6) {
        self.pinger.addressStyle = SimplePingAddressStyleICMPv4;
    } else if (self.forceIPv6 && ! self.forceIPv4) {
        self.pinger.addressStyle = SimplePingAddressStyleICMPv6;
    }
    
    self.pinger.delegate = self;
    [self.pinger start];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.pinger != nil) {
            [self close];
            if (self.success) {
                self.success(-1);
            }
        }
    });
    do {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    } while (self.pinger != nil);
}

/*! Sends a ping.
 *  \details Called to send a ping, both directly (as soon as the SimplePing object starts up)
 *      and via a timer (to continue sending pings periodically).
 */

- (void)sendPing {
    assert(self.pinger != nil);
    [self.pinger sendPingWithData:nil];
}

- (void)simplePing:(SimplePing *)pinger didStartWithAddress:(NSData *)address {
#pragma unused(pinger)
    assert(pinger == self.pinger);
    assert(address != nil);
    self.beginDate = [NSDate date];
    NSLog(@"pinging %@", displayAddressForAddress(address));
    
    // Send the first ping straight away.
    
    [self sendPing];
    
    // And start a timer to send the subsequent pings.
    
    assert(self.sendTimer == nil);
    self.sendTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(sendPing) userInfo:nil repeats:YES];
}

- (void)simplePing:(SimplePing *)pinger didFailWithError:(NSError *)error {
#pragma unused(pinger)
    assert(pinger == self.pinger);
    NSLog(@"failed: %@", shortErrorFromError(error));
    [self close];
    if (self.failure) {
        self.failure();
    }
}

- (void)simplePing:(SimplePing *)pinger didSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber {
#pragma unused(pinger)
    assert(pinger == self.pinger);
#pragma unused(packet)
    NSLog(@"#%u sent", (unsigned int) sequenceNumber);
}

- (void)simplePing:(SimplePing *)pinger didFailToSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber error:(NSError *)error {
#pragma unused(pinger)
    assert(pinger == self.pinger);
#pragma unused(packet)
    NSLog(@"#%u send failed: %@", (unsigned int) sequenceNumber, shortErrorFromError(error));
    [self close];
    if (self.failure) {
        self.failure();
    }
}

- (void)simplePing:(SimplePing *)pinger didReceivePingResponsePacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber {
#pragma unused(pinger)
    assert(pinger == self.pinger);
#pragma unused(packet)
    self.ping = [[NSDate date] timeIntervalSinceDate:self.beginDate] * 1000;
//    NSLog(@"ping = %@", @(_ping));
    NSLog(@"#%u received, size=%zu", (unsigned int) sequenceNumber, (size_t) packet.length);
    [self close];
    if (self.success) {
        self.success(self.ping);
    }
}

- (void)simplePing:(SimplePing *)pinger didReceiveUnexpectedPacket:(NSData *)packet {
#pragma unused(pinger)
    assert(pinger == self.pinger);
    [self close];
    NSLog(@"unexpected packet, size=%zu", (size_t) packet.length);
    if (self.success) {
        self.success(0);
    }
}

@end
