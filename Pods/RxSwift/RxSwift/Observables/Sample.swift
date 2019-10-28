//
//  Sample.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/1/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Samples the source observable sequence using a sampler observable sequence producing sampling ticks.

     Upon each sampling tick, the latest element (if any) in the source sequence during the last sampling interval is sent to the resulting sequence.

     **In case there were no new elements between sampler ticks, no element is sent to the resulting sequence.**

     - seealso: [sample operator on reactivex.io](http://reactivex.io/documentation/operators/sample.html)

     - parameter sampler: Sampling tick sequence.
     - returns: Sampled observable sequence.
     */
    public func sample<O: ObservableType>(_ sampler: O)
        -> Observable<E> {
            return Sample(source: self.asObservable(), sampler: sampler.asObservable())
    }
}

final private class SamplerSink<O: ObserverType, SampleType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias E = SampleType
    
    typealias Parent = SampleSequenceSink<O, SampleType>
    
    fileprivate let _parent: Parent

    var _lock: RecursiveLock {
        return self._parent._lock
    }
    
    init(parent: Parent) {
        self._parent = parent
    }
    
    func on(_ event: Event<E>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next, .completed:
            if let element = _parent._element {
                self._parent._element = nil
                self._parent.forwardOn(.next(element))
            }

            if self._parent._atEnd {
                self._parent.forwardOn(.completed)
                self._parent.dispose()
            }
        case .error(let e):
            self._parent.forwardOn(.error(e))
            self._parent.dispose()
        }
    }
}

final private class SampleSequenceSink<O: ObserverType, SampleType>
    : Sink<O>
    , ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias Element = O.E
    typealias Parent = Sample<Element, SampleType>
    
    fileprivate let _parent: Parent

    let _lock = RecursiveLock()
    
    // state
    fileprivate var _element = nil as Element?
    fileprivate var _atEnd = false
    
    fileprivate let _sourceSubscription = SingleAssignmentDisposable()
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        self._sourceSubscription.setDisposable(self._parent._source.subscribe(self))
        let samplerSubscription = self._parent._sampler.subscribe(SamplerSink(parent: self))
        
        return Disposables.create(_sourceSubscription, samplerSubscription)
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next(let element):
            self._element = element
        case .error:
            self.forwardOn(event)
            self.dispose()
        case .completed:
            self._atEnd = true
            self._sourceSubscription.dispose()
        }
    }
    
}

final private class Sample<Element, SampleType>: Producer<Element> {
    fileprivate let _source: Observable<Element>
    fileprivate let _sampler: Observable<SampleType>

    init(source: Observable<Element>, sampler: Observable<SampleType>) {
        self._source = source
        self._sampler = sampler
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = SampleSequenceSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
