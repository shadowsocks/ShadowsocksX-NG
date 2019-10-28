//
//  UIGestureRecognizer+Rx.swift
//  RxCocoa
//
//  Created by Carlos García on 10/6/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if os(iOS) || os(tvOS)

import UIKit
import RxSwift

// This should be only used from `MainScheduler`
final class GestureTarget<Recognizer: UIGestureRecognizer>: RxTarget {
    typealias Callback = (Recognizer) -> Void
    
    let selector = #selector(ControlTarget.eventHandler(_:))
    
    weak var gestureRecognizer: Recognizer?
    var callback: Callback?
    
    init(_ gestureRecognizer: Recognizer, callback: @escaping Callback) {
        self.gestureRecognizer = gestureRecognizer
        self.callback = callback
        
        super.init()
        
        gestureRecognizer.addTarget(self, action: selector)

        let method = self.method(for: selector)
        if method == nil {
            fatalError("Can't find method")
        }
    }
    
    @objc func eventHandler(_ sender: UIGestureRecognizer) {
        if let callback = self.callback, let gestureRecognizer = self.gestureRecognizer {
            callback(gestureRecognizer)
        }
    }
    
    override func dispose() {
        super.dispose()
        
        self.gestureRecognizer?.removeTarget(self, action: self.selector)
        self.callback = nil
    }
}

extension Reactive where Base: UIGestureRecognizer {
    
    /// Reactive wrapper for gesture recognizer events.
    public var event: ControlEvent<Base> {
        let source: Observable<Base> = Observable.create { [weak control = self.base] observer in
            MainScheduler.ensureRunningOnMainThread()

            guard let control = control else {
                observer.on(.completed)
                return Disposables.create()
            }
            
            let observer = GestureTarget(control) { control in
                observer.on(.next(control))
            }
            
            return observer
        }.takeUntil(deallocated)
        
        return ControlEvent(events: source)
    }
    
}

#endif
