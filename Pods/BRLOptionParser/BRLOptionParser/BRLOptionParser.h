// BRLOptionParser.h
//
// Copyright © 2013–2015 Stephen Celis (<stephen@stephencelis.com>)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


@import Foundation;


typedef void (^BRLOptionParserOptionBlock)();
typedef void (^BRLOptionParserOptionBlockWithArgument)(NSString *value);


static NSString *const BRLOptionParserErrorDomain = @"BRLOptionParserErrorDomain";


typedef NS_ENUM(NSUInteger, BRLOptionParserErrorCode) {
    BRLOptionParserErrorCodeUnrecognized = 1,
    BRLOptionParserErrorCodeRequired
};


@interface BRLOptionParser : NSObject

+ (instancetype)parser;
+ (instancetype)longOnlyParser;

@property (nonatomic, getter = isLongOnly) BOOL longOnly;

@property (nonatomic, copy) NSString *banner;

- (void)setBanner:(NSString *)banner, ...;

- (void)addOption:(char *)option flag:(unichar)flag description:(NSString *)description block:(BRLOptionParserOptionBlock)block;
- (void)addOption:(char *)option flag:(unichar)flag description:(NSString *)description blockWithArgument:(BRLOptionParserOptionBlockWithArgument)blockWithArgument;

- (void)addOption:(char *)option flag:(unichar)flag description:(NSString *)description value:(BOOL *)value;
- (void)addOption:(char *)option flag:(unichar)flag description:(NSString *)description argument:(NSString *__strong *)argument;

- (void)addSeparator;
- (void)addSeparator:(NSString *)separator;

- (BOOL)parseArgc:(int)argc argv:(const char **)argv error:(NSError **)error;

@end
