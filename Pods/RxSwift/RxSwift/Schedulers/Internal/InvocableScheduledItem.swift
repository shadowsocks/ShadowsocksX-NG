//
//  InvocableScheduledItem.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 11/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

struct InvocableScheduledItem<I: InvocableWithValueType> : InvocableType {

    let invocable: I
    let state: I.Value

    init(invocable: I, state: I.Value) {
        self.invocable = invocable
        self.state = state
    }

    func invoke() {
        self.invocable.invoke(self.state)
    }
}
