//
//  UIWebView+Rx.swift
//  RxCocoa
//
//  Created by Andrew Breckenridge on 8/30/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

#if os(iOS)

    import UIKit
    import RxSwift

    extension Reactive where Base: UIWebView {

        /// Reactive wrapper for `delegate`.
        /// For more information take a look at `DelegateProxyType` protocol documentation.
        public var delegate: DelegateProxy<UIWebView, UIWebViewDelegate> {
            return RxWebViewDelegateProxy.proxy(for: base)
        }

        /// Reactive wrapper for `delegate` message.
        public var didStartLoad: Observable<Void> {
            return delegate
                .methodInvoked(#selector(UIWebViewDelegate.webViewDidStartLoad(_:)))
                .map { _ in }
        }

        /// Reactive wrapper for `delegate` message.
        public var didFinishLoad: Observable<Void> {
            return delegate
                .methodInvoked(#selector(UIWebViewDelegate.webViewDidFinishLoad(_:)))
                .map { _ in }
        }
        
        /// Reactive wrapper for `delegate` message.
        public var didFailLoad: Observable<Error> {
            return delegate
                .methodInvoked(#selector(UIWebViewDelegate.webView(_:didFailLoadWithError:)))
                .map { a in
                    return try castOrThrow(Error.self, a[1])
                }
        }
    }

#endif
