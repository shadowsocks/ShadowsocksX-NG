# BRLOptionParser [![Build Status][1]][2]

A short wrapper for [getopt_long(3)][3] (and getopt_long_only(3)).

[1]: https://img.shields.io/travis/stephencelis/BRLOptionParser.svg?style=flat
[2]: https://travis-ci.org/stephencelis/BRLOptionParser
[3]: https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man3/getopt_long.3.html

## Install

With [CocoaPods][4]:

``` rb
# Podfile
pod 'BRLOptionParser', '~> 0.3.1'
```

[4]: http://cocoapods.org

## Example

``` objc
// main.m
#import <BRLOptionParser/BRLOptionParser.h>

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSString *name = @"world";
        BOOL verbose = NO;

        BRLOptionParser *options = [BRLOptionParser new];

        [options setBanner:@"usage: %s [-n <name>] [-vh]", argv[0]];
        [options addOption:"name" flag:'n' description:@"Your name" argument:&name];
        [options addSeparator];
        [options addOption:"verbose" flag:'v' description:nil value:&verbose];
        __weak typeof(options) weakOptions = options;
        [options addOption:"help" flag:'h' description:@"Show this message" block:^{
            printf("%s", [[weakOptions description] UTF8String]);
            exit(EXIT_SUCCESS);
        }];

        NSError *error = nil;
        if (![options parseArgc:argc argv:argv error:&error]) {
            const char * message = error.localizedDescription.UTF8String;
            fprintf(stderr, "%s: %s\n", argv[0], message);
            exit(EXIT_FAILURE);
        }

        if (verbose) {
            fprintf(stderr, "(Preparing to say hello...)\n");
        }

        printf("Hello, %s!\n", name.UTF8String);
    }

    return EXIT_SUCCESS;
}
```

In practice:

```
$ hello
Hello, world!
$ hello -h
usage: hello [-n <name>] [-vh]
    -n, --name                       Your name

    -v, --verbose
    -h, --help                       Show this message
$ hello -n
hello: option `-n' requires an argument
$ hello --name Stephen
Hello, Stephen!
$ hello -vngoodbye
(Preparing to say hello...)
Hello, goodbye!
$ hello --goodbye
hello: unrecognized option `--goodbye'
```

## License

BRLOptionParser is available under the MIT license. See the LICENSE file
for more information.

