//
//  SubscriptionDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

struct SubscriptionDisposable<T: SynchronizedUnsubscribeType> : Disposable {
    private let _key: T.DisposeKey
    private weak var _owner: T?

    init(owner: T, key: T.DisposeKey) {
        self._owner = owner
        self._key = key
    }

    func dispose() {
        self._owner?.synchronizedUnsubscribe(self._key)
    }
}
