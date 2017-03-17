//
//  Deferred.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

class DeferredSink<S: ObservableType, O: ObserverType> : Sink<O>, ObserverType where S.E == O.E {
    typealias E = O.E

    private let _observableFactory: () throws -> S

    init(observableFactory: @escaping () throws -> S, observer: O, cancel: Cancelable) {
        _observableFactory = observableFactory
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        do {
            let result = try _observableFactory()
            return result.subscribe(self)
        }
        catch let e {
            forwardOn(.error(e))
            dispose()
            return Disposables.create()
        }
    }
    
    func on(_ event: Event<E>) {
        forwardOn(event)
        
        switch event {
        case .next:
            break
        case .error:
            dispose()
        case .completed:
            dispose()
        }
    }
}

class Deferred<S: ObservableType> : Producer<S.E> {
    typealias Factory = () throws -> S
    
    private let _observableFactory : Factory
    
    init(observableFactory: @escaping Factory) {
        _observableFactory = observableFactory
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == S.E {
        let sink = DeferredSink(observableFactory: _observableFactory, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
