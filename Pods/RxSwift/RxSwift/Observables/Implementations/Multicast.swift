//
//  Multicast.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/27/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class MulticastSink<S: SubjectType, O: ObserverType>: Sink<O>, ObserverType {
    typealias Element = O.E
    typealias ResultType = Element
    typealias MutlicastType = Multicast<S, O.E>
    
    private let _parent: MutlicastType
    
    init(parent: MutlicastType, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        do {
            let subject = try _parent._subjectSelector()
            let connectable = ConnectableObservableAdapter(source: _parent._source, subject: subject)
            
            let observable = try _parent._selector(connectable)
            
            let subscription = observable.subscribe(self)
            let connection = connectable.connect()
                
            return Disposables.create(subscription, connection)
        }
        catch let e {
            forwardOn(.error(e))
            dispose()
            return Disposables.create()
        }
    }
    
    func on(_ event: Event<ResultType>) {
        forwardOn(event)
        switch event {
            case .next: break
            case .error, .completed:
                dispose()
        }
    }
}

final class Multicast<S: SubjectType, R>: Producer<R> {
    typealias SubjectSelectorType = () throws -> S
    typealias SelectorType = (Observable<S.E>) throws -> Observable<R>
    
    fileprivate let _source: Observable<S.SubjectObserverType.E>
    fileprivate let _subjectSelector: SubjectSelectorType
    fileprivate let _selector: SelectorType
    
    init(source: Observable<S.SubjectObserverType.E>, subjectSelector: @escaping SubjectSelectorType, selector: @escaping SelectorType) {
        _source = source
        _subjectSelector = subjectSelector
        _selector = selector
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == R {
        let sink = MulticastSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
