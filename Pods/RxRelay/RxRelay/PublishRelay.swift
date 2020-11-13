//
//  PublishRelay.swift
//  RxRelay
//
//  Created by Krunoslav Zaher on 3/28/15.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

import RxSwift

/// PublishRelay is a wrapper for `PublishSubject`.
///
/// Unlike `PublishSubject` it can't terminate with error or completed.
public final class PublishRelay<Element>: ObservableType {
    private let _subject: PublishSubject<Element>
    
    // Accepts `event` and emits it to subscribers
    public func accept(_ event: Element) {
        self._subject.onNext(event)
    }
    
    /// Initializes with internal empty subject.
    public init() {
        self._subject = PublishSubject()
    }

    /// Subscribes observer
    public func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        return self._subject.subscribe(observer)
    }
    
    /// - returns: Canonical interface for push style sequence
    public func asObservable() -> Observable<Element> {
        return self._subject.asObservable()
    }
}
