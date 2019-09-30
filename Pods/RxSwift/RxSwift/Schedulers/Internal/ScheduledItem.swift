//
//  ScheduledItem.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/2/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

struct ScheduledItem<T>
    : ScheduledItemType
    , InvocableType {
    typealias Action = (T) -> Disposable
    
    private let _action: Action
    private let _state: T

    private let _disposable = SingleAssignmentDisposable()

    var isDisposed: Bool {
        return self._disposable.isDisposed
    }
    
    init(action: @escaping Action, state: T) {
        self._action = action
        self._state = state
    }
    
    func invoke() {
         self._disposable.setDisposable(self._action(self._state))
    }
    
    func dispose() {
        self._disposable.dispose()
    }
}
