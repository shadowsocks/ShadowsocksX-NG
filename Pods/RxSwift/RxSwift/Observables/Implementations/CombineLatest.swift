//
//  CombineLatest.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

protocol CombineLatestProtocol : class {
    func next(_ index: Int)
    func fail(_ error: Swift.Error)
    func done(_ index: Int)
}

class CombineLatestSink<O: ObserverType>
    : Sink<O>
    , CombineLatestProtocol {
    typealias Element = O.E
   
    let _lock = NSRecursiveLock()

    private let _arity: Int
    private var _numberOfValues = 0
    private var _numberOfDone = 0
    private var _hasValue: [Bool]
    private var _isDone: [Bool]
   
    init(arity: Int, observer: O, cancel: Cancelable) {
        _arity = arity
        _hasValue = [Bool](repeating: false, count: arity)
        _isDone = [Bool](repeating: false, count: arity)
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func getResult() throws -> Element {
        abstractMethod()
    }
    
    func next(_ index: Int) {
        if !_hasValue[index] {
            _hasValue[index] = true
            _numberOfValues += 1
        }

        if _numberOfValues == _arity {
            do {
                let result = try getResult()
                forwardOn(.next(result))
            }
            catch let e {
                forwardOn(.error(e))
                dispose()
            }
        }
        else {
            var allOthersDone = true

            for i in 0 ..< _arity {
                if i != index && !_isDone[i] {
                    allOthersDone = false
                    break
                }
            }
            
            if allOthersDone {
                forwardOn(.completed)
                dispose()
            }
        }
    }
    
    func fail(_ error: Swift.Error) {
        forwardOn(.error(error))
        dispose()
    }
    
    func done(_ index: Int) {
        if _isDone[index] {
            return
        }

        _isDone[index] = true
        _numberOfDone += 1

        if _numberOfDone == _arity {
            forwardOn(.completed)
            dispose()
        }
    }
}

class CombineLatestObserver<ElementType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias Element = ElementType
    typealias ValueSetter = (Element) -> Void
    
    private let _parent: CombineLatestProtocol
    
    let _lock: NSRecursiveLock
    private let _index: Int
    private let _this: Disposable
    private let _setLatestValue: ValueSetter
    
    init(lock: NSRecursiveLock, parent: CombineLatestProtocol, index: Int, setLatestValue: @escaping ValueSetter, this: Disposable) {
        _lock = lock
        _parent = parent
        _index = index
        _this = this
        _setLatestValue = setLatestValue
    }
    
    func on(_ event: Event<Element>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            _setLatestValue(value)
            _parent.next(_index)
        case .error(let error):
            _this.dispose()
            _parent.fail(error)
        case .completed:
            _this.dispose()
            _parent.done(_index)
        }
    }
}
