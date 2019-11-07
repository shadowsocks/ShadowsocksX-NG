//
//  InvocableScheduledItem.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 11/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

struct InvocableScheduledItem<I: InvocableWithValueType> : InvocableType {

    let _invocable: I
    let _state: I.Value

    init(invocable: I, state: I.Value) {
        self._invocable = invocable
        self._state = state
    }

    func invoke() {
        self._invocable.invoke(self._state)
    }
}
