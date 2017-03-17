//
//  ObservableConvertibleType+SharedSequence.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 9/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation
#if !RX_NO_MODULE
import RxSwift
#endif

extension ObservableConvertibleType {
    /**
    Converts anything convertible to `Observable` to `SharedSequence` unit.
    
    - parameter onErrorJustReturn: Element to return in case of error and after that complete the sequence.
    - returns: Driving observable sequence.
    */
    public func asSharedSequence<S: SharingStrategyProtocol>(sharingStrategy: S.Type = S.self, onErrorJustReturn: E) -> SharedSequence<S, E> {
        let source = self
            .asObservable()
            .observeOn(S.scheduler)
            .catchErrorJustReturn(onErrorJustReturn)
        return SharedSequence(source)
    }
    
    /**
    Converts anything convertible to `Observable` to `SharedSequence` unit.
    
    - parameter onErrorDriveWith: SharedSequence that provides elements of the sequence in case of error.
    - returns: Driving observable sequence.
    */
    public func asSharedSequence<S: SharingStrategyProtocol>(sharingStrategy: S.Type = S.self, onErrorDriveWith: SharedSequence<S, E>) -> SharedSequence<S, E> {
        let source = self
            .asObservable()
            .observeOn(S.scheduler)
            .catchError { _ in
                onErrorDriveWith.asObservable()
            }
        return SharedSequence(source)
    }

    /**
    Converts anything convertible to `Observable` to `SharedSequence` unit.
    
    - parameter onErrorRecover: Calculates driver that continues to drive the sequence in case of error.
    - returns: Driving observable sequence.
    */
    public func asSharedSequence<S: SharingStrategyProtocol>(sharingStrategy: S.Type = S.self, onErrorRecover: @escaping (_ error: Swift.Error) -> SharedSequence<S, E>) -> SharedSequence<S, E> {
        let source = self
            .asObservable()
            .observeOn(S.scheduler)
            .catchError { error in
                onErrorRecover(error).asObservable()
            }
        return SharedSequence(source)
    }
}
