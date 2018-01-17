//
//  Observable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/8/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// A type-erased `ObservableType`. 
///
/// It represents a push style sequence.
public class Observable<Element> : ObservableType {
    /// Type of elements in sequence.
    public typealias E = Element
    
    init() {
#if TRACE_RESOURCES
        let _ = Resources.incrementTotal()
#endif
    }
    
    public func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E {
        rxAbstractMethod()
    }
    
    public func asObservable() -> Observable<E> {
        return self
    }
    
    deinit {
#if TRACE_RESOURCES
        let _ = Resources.decrementTotal()
#endif
    }

    // this is kind of ugly I know :(
    // Swift compiler reports "Not supported yet" when trying to override protocol extensions, so ¯\_(ツ)_/¯

    /// Optimizations for map operator
    internal func composeMap<R>(_ transform: @escaping (Element) throws -> R) -> Observable<R> {
        return _map(source: self, transform: transform)
    }
}

