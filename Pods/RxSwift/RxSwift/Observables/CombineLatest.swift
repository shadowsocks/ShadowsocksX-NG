//
//  CombineLatest.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

protocol CombineLatestProtocol : class {
    func next(_ index: Int)
    func fail(_ error: Swift.Error)
    func done(_ index: Int)
}

class CombineLatestSink<Observer: ObserverType>
    : Sink<Observer>
    , CombineLatestProtocol {
    typealias Element = Observer.Element 
   
    let _lock = RecursiveLock()

    private let _arity: Int
    private var _numberOfValues = 0
    private var _numberOfDone = 0
    private var _hasValue: [Bool]
    private var _isDone: [Bool]
   
    init(arity: Int, observer: Observer, cancel: Cancelable) {
        self._arity = arity
        self._hasValue = [Bool](repeating: false, count: arity)
        self._isDone = [Bool](repeating: false, count: arity)
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func getResult() throws -> Element {
        rxAbstractMethod()
    }
    
    func next(_ index: Int) {
        if !self._hasValue[index] {
            self._hasValue[index] = true
            self._numberOfValues += 1
        }

        if self._numberOfValues == self._arity {
            do {
                let result = try self.getResult()
                self.forwardOn(.next(result))
            }
            catch let e {
                self.forwardOn(.error(e))
                self.dispose()
            }
        }
        else {
            var allOthersDone = true

            for i in 0 ..< self._arity {
                if i != index && !self._isDone[i] {
                    allOthersDone = false
                    break
                }
            }
            
            if allOthersDone {
                self.forwardOn(.completed)
                self.dispose()
            }
        }
    }
    
    func fail(_ error: Swift.Error) {
        self.forwardOn(.error(error))
        self.dispose()
    }
    
    func done(_ index: Int) {
        if self._isDone[index] {
            return
        }

        self._isDone[index] = true
        self._numberOfDone += 1

        if self._numberOfDone == self._arity {
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final class CombineLatestObserver<Element>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias ValueSetter = (Element) -> Void
    
    private let _parent: CombineLatestProtocol
    
    let _lock: RecursiveLock
    private let _index: Int
    private let _this: Disposable
    private let _setLatestValue: ValueSetter
    
    init(lock: RecursiveLock, parent: CombineLatestProtocol, index: Int, setLatestValue: @escaping ValueSetter, this: Disposable) {
        self._lock = lock
        self._parent = parent
        self._index = index
        self._this = this
        self._setLatestValue = setLatestValue
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            self._setLatestValue(value)
            self._parent.next(self._index)
        case .error(let error):
            self._this.dispose()
            self._parent.fail(error)
        case .completed:
            self._this.dispose()
            self._parent.done(self._index)
        }
    }
}
