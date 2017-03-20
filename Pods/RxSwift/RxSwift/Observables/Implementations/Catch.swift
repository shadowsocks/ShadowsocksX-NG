//
//  Catch.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/19/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

// catch with callback

final class CatchSinkProxy<O: ObserverType> : ObserverType {
    typealias E = O.E
    typealias Parent = CatchSink<O>
    
    private let _parent: Parent
    
    init(parent: Parent) {
        _parent = parent
    }
    
    func on(_ event: Event<E>) {
        _parent.forwardOn(event)
        
        switch event {
        case .next:
            break
        case .error, .completed:
            _parent.dispose()
        }
    }
}

final class CatchSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias E = O.E
    typealias Parent = Catch<E>
    
    private let _parent: Parent
    private let _subscription = SerialDisposable()
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let d1 = SingleAssignmentDisposable()
        _subscription.disposable = d1
        d1.setDisposable(_parent._source.subscribe(self))

        return _subscription
    }
    
    func on(_ event: Event<E>) {
        switch event {
        case .next:
            forwardOn(event)
        case .completed:
            forwardOn(event)
            dispose()
        case .error(let error):
            do {
                let catchSequence = try _parent._handler(error)

                let observer = CatchSinkProxy(parent: self)
                
                _subscription.disposable = catchSequence.subscribe(observer)
            }
            catch let e {
                forwardOn(.error(e))
                dispose()
            }
        }
    }
}

final class Catch<Element> : Producer<Element> {
    typealias Handler = (Swift.Error) throws -> Observable<Element>
    
    fileprivate let _source: Observable<Element>
    fileprivate let _handler: Handler
    
    init(source: Observable<Element>, handler: @escaping Handler) {
        _source = source
        _handler = handler
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = CatchSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

// catch enumerable

final class CatchSequenceSink<S: Sequence, O: ObserverType>
    : TailRecursiveSink<S, O>
    , ObserverType where S.Iterator.Element : ObservableConvertibleType, S.Iterator.Element.E == O.E {
    typealias Element = O.E
    typealias Parent = CatchSequence<S>
    
    private var _lastError: Swift.Error?
    
    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        switch event {
        case .next:
            forwardOn(event)
        case .error(let error):
            _lastError = error
            schedule(.moveNext)
        case .completed:
            forwardOn(event)
            dispose()
        }
    }

    override func subscribeToNext(_ source: Observable<E>) -> Disposable {
        return source.subscribe(self)
    }
    
    override func done() {
        if let lastError = _lastError {
            forwardOn(.error(lastError))
        }
        else {
            forwardOn(.completed)
        }
        
        self.dispose()
    }
    
    override func extract(_ observable: Observable<Element>) -> SequenceGenerator? {
        if let onError = observable as? CatchSequence<S> {
            return (onError.sources.makeIterator(), nil)
        }
        else {
            return nil
        }
    }
}

final class CatchSequence<S: Sequence> : Producer<S.Iterator.Element.E> where S.Iterator.Element : ObservableConvertibleType {
    typealias Element = S.Iterator.Element.E
    
    let sources: S
    
    init(sources: S) {
        self.sources = sources
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = CatchSequenceSink<S, O>(observer: observer, cancel: cancel)
        let subscription = sink.run((self.sources.makeIterator(), nil))
        return (sink: sink, subscription: subscription)
    }
}
