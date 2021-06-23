//
//  ReplayRelay.swift
//  RxRelay
//
//  Created by Zsolt Kovacs on 12/22/19.
//  Copyright © 2019 Krunoslav Zaher. All rights reserved.
//

import RxSwift

/// ReplayRelay is a wrapper for `ReplaySubject`.
///
/// Unlike `ReplaySubject` it can't terminate with an error or complete.
public final class ReplayRelay<Element>: ObservableType {
    private let subject: ReplaySubject<Element>

    // Accepts `event` and emits it to subscribers
    public func accept(_ event: Element) {
        self.subject.onNext(event)
    }

    private init(subject: ReplaySubject<Element>) {
        self.subject = subject
    }

    /// Creates new instance of `ReplayRelay` that replays at most `bufferSize` last elements sent to it.
    ///
    /// - parameter bufferSize: Maximal number of elements to replay to observers after subscription.
    /// - returns: New instance of replay relay.
    public static func create(bufferSize: Int) -> ReplayRelay<Element> {
        ReplayRelay(subject: ReplaySubject.create(bufferSize: bufferSize))
    }

    /// Creates a new instance of `ReplayRelay` that buffers all the sent to it.
    /// To avoid filling up memory, developer needs to make sure that the use case will only ever store a 'reasonable'
    /// number of elements.
    public static func createUnbound() -> ReplayRelay<Element> {
        ReplayRelay(subject: ReplaySubject.createUnbounded())
    }

    /// Subscribes observer
    public func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        self.subject.subscribe(observer)
    }

    /// - returns: Canonical interface for push style sequence
    public func asObservable() -> Observable<Element> {
        self.subject.asObserver()
    }
}
