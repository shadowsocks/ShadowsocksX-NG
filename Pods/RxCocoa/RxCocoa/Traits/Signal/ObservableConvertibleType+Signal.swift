//
//  ObservableConvertibleType+Signal.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import RxSwift

extension ObservableConvertibleType {
    /**
     Converts observable sequence to `Signal` trait.

     - parameter onErrorJustReturn: Element to return in case of error and after that complete the sequence.
     - returns: Signal trait.
     */
    public func asSignal(onErrorJustReturn: Element) -> Signal<Element> {
        let source = self
            .asObservable()
            .observe(on: SignalSharingStrategy.scheduler)
            .catchAndReturn(onErrorJustReturn)
        return Signal(source)
    }

    /**
     Converts observable sequence to `Signal` trait.

     - parameter onErrorSignalWith: Signal that continues to emit the sequence in case of error.
     - returns: Signal trait.
     */
    public func asSignal(onErrorSignalWith: Signal<Element>) -> Signal<Element> {
        let source = self
            .asObservable()
            .observe(on: SignalSharingStrategy.scheduler)
            .catch { _ in
                onErrorSignalWith.asObservable()
            }
        return Signal(source)
    }

    /**
     Converts observable sequence to `Signal` trait.

     - parameter onErrorRecover: Calculates signal that continues to emit the sequence in case of error.
     - returns: Signal trait.
     */
    public func asSignal(onErrorRecover: @escaping (_ error: Swift.Error) -> Signal<Element>) -> Signal<Element> {
        let source = self
            .asObservable()
            .observe(on: SignalSharingStrategy.scheduler)
            .catch { error in
                onErrorRecover(error).asObservable()
            }
        return Signal(source)
    }
}
