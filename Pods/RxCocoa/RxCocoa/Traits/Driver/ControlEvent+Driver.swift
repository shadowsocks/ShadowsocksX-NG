//
//  ControlEvent+Driver.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift
    
extension ControlEvent {
    /// Converts `ControlEvent` to `Driver` trait.
    ///
    /// `ControlEvent` already can't fail, so no special case needs to be handled.
    public func asDriver() -> Driver<Element> {
        return self.asDriver { _ -> Driver<Element> in
            #if DEBUG
                rxFatalError("Somehow driver received error from a source that shouldn't fail.")
            #else
                return Driver.empty()
            #endif
        }
    }
}
