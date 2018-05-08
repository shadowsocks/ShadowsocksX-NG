//
//  ControlEvent+Signal.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 11/1/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

import RxSwift

extension ControlEvent {
    /// Converts `ControlEvent` to `Signal` trait.
    ///
    /// `ControlEvent` already can't fail, so no special case needs to be handled.
    public func asSignal() -> Signal<E> {
        return self.asSignal { (error) -> Signal<E> in
            #if DEBUG
                rxFatalError("Somehow signal received error from a source that shouldn't fail.")
            #else
                return Signal.empty()
            #endif
        }
    }
}

