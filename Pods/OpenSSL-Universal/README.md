OpenSSL-Universal
=======

OpenSSL CocoaPod for iOS and OSX. Complete solution to OpenSSL on iOS and OSX. Package came with precompiled libraries, and include script to build newer version if necessary.

Current version contains binaries build with SDK iOS 8.0 (target 5.1.1), and SDK OSX 10.9 (target 10.8) for all supported architectures.

**Architectures**

- iOS with architectures: armv7, armv7s, arm64 + simulator (i386, x86_64)
- OSX with architectures: i386, x86_64

**Why?**

[Apple says](https://developer.apple.com/library/mac/documentation/security/Conceptual/cryptoservices/GeneralPurposeCrypto/GeneralPurposeCrypto.html):
"Although OpenSSL is commonly used in the open source community, OpenSSL does not provide a stable API from version to version. For this reason, although OS X provides OpenSSL libraries, the OpenSSL libraries in OS X are deprecated, and OpenSSL has never been provided as part of iOS."

**Installation**

````
pod 'OpenSSL-Universal', '1.0.1.k'
````

Or always latest version

````
pod 'OpenSSL-Universal', :git => 'https://github.com/krzyzanowskim/OpenSSL.git', :branch => :master
````

**Authors**

[Marcin Krzyżanowski](https://twitter.com/krzyzanowskim)
