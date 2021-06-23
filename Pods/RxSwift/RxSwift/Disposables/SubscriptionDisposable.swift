//
//  SubscriptionDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 10/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

struct SubscriptionDisposable<T: SynchronizedUnsubscribeType> : Disposable {
    private let key: T.DisposeKey
    private weak var owner: T?

    init(owner: T, key: T.DisposeKey) {
        self.owner = owner
        self.key = key
    }

    func dispose() {
        self.owner?.synchronizedUnsubscribe(self.key)
    }
}
