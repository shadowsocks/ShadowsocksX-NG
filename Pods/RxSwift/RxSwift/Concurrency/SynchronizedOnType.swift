//
//  SynchronizedOnType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

protocol SynchronizedOnType: AnyObject, ObserverType, Lock {
    func synchronized_on(_ event: Event<Element>)
}

extension SynchronizedOnType {
    func synchronizedOn(_ event: Event<Element>) {
        self.lock(); defer { self.unlock() }
        self.synchronized_on(event)
    }
}
