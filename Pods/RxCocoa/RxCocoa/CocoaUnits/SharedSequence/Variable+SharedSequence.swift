//
//  Variable+SharedSequence.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 12/28/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#if !RX_NO_MODULE
    import RxSwift
#endif

extension Variable {
    /// Converts `Variable` to `SharedSequence` unit.
    ///
    /// - returns: Observable sequence.
    public func asSharedSequence<SharingStrategy: SharingStrategyProtocol>(strategy: SharingStrategy.Type = SharingStrategy.self) -> SharedSequence<SharingStrategy, E> {
        let source = self.asObservable()
            .observeOn(SharingStrategy.scheduler)
        return SharedSequence(source)
    }
}
