//
//  SynchronizedOnType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

protocol SynchronizedOnType : class, ObserverType, Lock {
    func _synchronized_on(_ event: Event<E>)
}

extension SynchronizedOnType {
    func synchronizedOn(_ event: Event<E>) {
        self.lock(); defer { self.unlock() }
        self._synchronized_on(event)
    }
}
