//
//  WithUnretained.swift
//  RxSwift
//
//  Created by Vincent Pradeilles on 01/01/2021.
//  Copyright © 2020 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Provides an unretained, safe to use (i.e. not implicitly unwrapped), reference to an object along with the events emitted by the sequence.
     
     In the case the provided object cannot be retained successfully, the seqeunce will complete.
     
     - note: Be careful when using this operator in a sequence that has a buffer or replay, for example `share(replay: 1)`, as the sharing buffer will also include the provided object, which could potentially cause a retain cycle.
     
     - parameter obj: The object to provide an unretained reference on.
     - parameter resultSelector: A function to combine the unretained referenced on `obj` and the value of the observable sequence.
     - returns: An observable sequence that contains the result of `resultSelector` being called with an unretained reference on `obj` and the values of the original sequence.
     */
    public func withUnretained<Object: AnyObject, Out>(
        _ obj: Object,
        resultSelector: @escaping (Object, Element) -> Out
    ) -> Observable<Out> {
        map { [weak obj] element -> Out in
            guard let obj = obj else { throw UnretainedError.failedRetaining }

            return resultSelector(obj, element)
        }
        .catch{ error -> Observable<Out> in
            guard let unretainedError = error as? UnretainedError,
                  unretainedError == .failedRetaining else {
                return .error(error)
            }

            return .empty()
        }
    }

    
    /**
     Provides an unretained, safe to use (i.e. not implicitly unwrapped), reference to an object along with the events emitted by the sequence.
     
     In the case the provided object cannot be retained successfully, the seqeunce will complete.
     
     - note: Be careful when using this operator in a sequence that has a buffer or replay, for example `share(replay: 1)`, as the sharing buffer will also include the provided object, which could potentially cause a retain cycle.
     
     - parameter obj: The object to provide an unretained reference on.
     - returns: An observable sequence of tuples that contains both an unretained reference on `obj` and the values of the original sequence.
     */
    public func withUnretained<Object: AnyObject>(_ obj: Object) -> Observable<(Object, Element)> {
        return withUnretained(obj) { ($0, $1) }
    }
}

private enum UnretainedError: Swift.Error {
    case failedRetaining
}
