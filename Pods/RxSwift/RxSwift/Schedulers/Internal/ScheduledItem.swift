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
    
    private let action: Action
    private let state: T

    private let disposable = SingleAssignmentDisposable()

    var isDisposed: Bool {
        self.disposable.isDisposed
    }
    
    init(action: @escaping Action, state: T) {
        self.action = action
        self.state = state
    }
    
    func invoke() {
         self.disposable.setDisposable(self.action(self.state))
    }
    
    func dispose() {
        self.disposable.dispose()
    }
}
