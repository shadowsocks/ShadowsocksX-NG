//
//  Generate.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/2/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Generates an observable sequence by running a state-driven loop producing the sequence's elements, using the specified scheduler
     to run the loop send out observer messages.

     - seealso: [create operator on reactivex.io](http://reactivex.io/documentation/operators/create.html)

     - parameter initialState: Initial state.
     - parameter condition: Condition to terminate generation (upon returning `false`).
     - parameter iterate: Iteration step function.
     - parameter scheduler: Scheduler on which to run the generator loop.
     - returns: The generated sequence.
     */
    public static func generate(initialState: E, condition: @escaping (E) throws -> Bool, scheduler: ImmediateSchedulerType = CurrentThreadScheduler.instance, iterate: @escaping (E) throws -> E) -> Observable<E> {
        return Generate(initialState: initialState, condition: condition, iterate: iterate, resultSelector: { $0 }, scheduler: scheduler)
    }
}

final fileprivate class GenerateSink<S, O: ObserverType> : Sink<O> {
    typealias Parent = Generate<S, O.E>
    
    private let _parent: Parent
    
    private var _state: S
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        _state = parent._initialState
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        return _parent._scheduler.scheduleRecursive(true) { (isFirst, recurse) -> Void in
            do {
                if !isFirst {
                    self._state = try self._parent._iterate(self._state)
                }
                
                if try self._parent._condition(self._state) {
                    let result = try self._parent._resultSelector(self._state)
                    self.forwardOn(.next(result))
                    
                    recurse(false)
                }
                else {
                    self.forwardOn(.completed)
                    self.dispose()
                }
            }
            catch let error {
                self.forwardOn(.error(error))
                self.dispose()
            }
        }
    }
}

final fileprivate class Generate<S, E> : Producer<E> {
    fileprivate let _initialState: S
    fileprivate let _condition: (S) throws -> Bool
    fileprivate let _iterate: (S) throws -> S
    fileprivate let _resultSelector: (S) throws -> E
    fileprivate let _scheduler: ImmediateSchedulerType
    
    init(initialState: S, condition: @escaping (S) throws -> Bool, iterate: @escaping (S) throws -> S, resultSelector: @escaping (S) throws -> E, scheduler: ImmediateSchedulerType) {
        _initialState = initialState
        _condition = condition
        _iterate = iterate
        _resultSelector = resultSelector
        _scheduler = scheduler
        super.init()
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == E {
        let sink = GenerateSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
