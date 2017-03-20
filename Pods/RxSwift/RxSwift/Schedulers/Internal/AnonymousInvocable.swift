//
//  AnonymousInvocable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 11/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

struct AnonymousInvocable : InvocableType {
    private let _action: () -> ()

    init(_ action: @escaping () -> ()) {
        _action = action
    }

    func invoke() {
        _action()
    }
}
