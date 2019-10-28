//
//  Zip.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/23/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

protocol ZipSinkProtocol : class
{
    func next(_ index: Int)
    func fail(_ error: Swift.Error)
    func done(_ index: Int)
}

class ZipSink<O: ObserverType> : Sink<O>, ZipSinkProtocol {
    typealias Element = O.E
    
    let _arity: Int

    let _lock = RecursiveLock()

    // state
    private var _isDone: [Bool]
    
    init(arity: Int, observer: O, cancel: Cancelable) {
        self._isDone = [Bool](repeating: false, count: arity)
        self._arity = arity
        
        super.init(observer: observer, cancel: cancel)
    }

    func getResult() throws -> Element {
        rxAbstractMethod()
    }
    
    func hasElements(_ index: Int) -> Bool {
        rxAbstractMethod()
    }
    
    func next(_ index: Int) {
        var hasValueAll = true
        
        for i in 0 ..< self._arity {
            if !self.hasElements(i) {
                hasValueAll = false
                break
            }
        }
        
        if hasValueAll {
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
            
            let arity = self._isDone.count
            for i in 0 ..< arity {
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
        self._isDone[index] = true
        
        var allDone = true
        
        for done in self._isDone where !done {
            allDone = false
            break
        }
        
        if allDone {
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final class ZipObserver<ElementType>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias E = ElementType
    typealias ValueSetter = (ElementType) -> Void

    private var _parent: ZipSinkProtocol?
    
    let _lock: RecursiveLock
    
    // state
    private let _index: Int
    private let _this: Disposable
    private let _setNextValue: ValueSetter
    
    init(lock: RecursiveLock, parent: ZipSinkProtocol, index: Int, setNextValue: @escaping ValueSetter, this: Disposable) {
        self._lock = lock
        self._parent = parent
        self._index = index
        self._this = this
        self._setNextValue = setNextValue
    }
    
    func on(_ event: Event<E>) {
        self.synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        if self._parent != nil {
            switch event {
            case .next:
                break
            case .error:
                self._this.dispose()
            case .completed:
                self._this.dispose()
            }
        }
        
        if let parent = self._parent {
            switch event {
            case .next(let value):
                self._setNextValue(value)
                parent.next(self._index)
            case .error(let error):
                parent.fail(error)
            case .completed:
                parent.done(self._index)
            }
        }
    }
}
