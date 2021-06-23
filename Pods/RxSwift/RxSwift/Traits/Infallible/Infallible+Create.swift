//
//  Infallible+Create.swift
//  RxSwift
//
//  Created by Shai Mishali on 27/08/2020.
//  Copyright © 2020 Krunoslav Zaher. All rights reserved.
//

import Foundation

public enum InfallibleEvent<Element> {
    /// Next element is produced.
    case next(Element)

    /// Sequence completed successfully.
    case completed
}

extension Infallible {
    public typealias InfallibleObserver = (InfallibleEvent<Element>) -> Void

    /**
     Creates an observable sequence from a specified subscribe method implementation.

     - seealso: [create operator on reactivex.io](http://reactivex.io/documentation/operators/create.html)

     - parameter subscribe: Implementation of the resulting observable sequence's `subscribe` method.
     - returns: The observable sequence with the specified implementation for the `subscribe` method.
     */
    public static func create(subscribe: @escaping (@escaping InfallibleObserver) -> Disposable) -> Infallible<Element> {
        let source = Observable<Element>.create { observer in
            subscribe { event in
                switch event {
                case .next(let element):
                    observer.onNext(element)
                case .completed:
                    observer.onCompleted()
                }
            }
        }

        return Infallible(source)
    }
}
