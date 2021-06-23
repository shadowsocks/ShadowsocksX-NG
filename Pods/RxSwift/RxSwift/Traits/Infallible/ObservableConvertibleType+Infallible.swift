//
//  ObservableConvertibleType+Infallible.swift
//  RxSwift
//
//  Created by Shai Mishali on 27/08/2020.
//  Copyright © 2020 Krunoslav Zaher. All rights reserved.
//

public extension ObservableConvertibleType {
    /// Convert to an `Infallible`
    ///
    /// - returns: `Infallible<Element>`
    func asInfallible(onErrorJustReturn element: Element) -> Infallible<Element> {
        Infallible(self.asObservable().catchAndReturn(element))
    }

    /// Convert to an `Infallible`
    ///
    /// - parameter onErroFallbackTo: Fall back to this provided infallible on error
    ///
    ///
    /// - returns: `Infallible<Element>`
    func asInfallible(onErrorFallbackTo infallible: Infallible<Element>) -> Infallible<Element> {
        Infallible(self.asObservable().catch { _ in infallible.asObservable() })
    }

    /// Convert to an `Infallible`
    ///
    /// - parameter onErrorRecover: Recover with the this infallible closure
    ///
    /// - returns: `Infallible<Element>`
    func asInfallible(onErrorRecover: @escaping (Swift.Error) -> Infallible<Element>) -> Infallible<Element> {
        Infallible(asObservable().catch { onErrorRecover($0).asObservable() })
    }
}
