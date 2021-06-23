//
//  Zip.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/23/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

protocol ZipSinkProtocol: AnyObject {
    func next(_ index: Int)
    func fail(_ error: Swift.Error)
    func done(_ index: Int)
}

class ZipSink<Observer: ObserverType> : Sink<Observer>, ZipSinkProtocol {
    typealias Element = Observer.Element
    
    let arity: Int

    let lock = RecursiveLock()

    // state
    private var isDone: [Bool]
    
    init(arity: Int, observer: Observer, cancel: Cancelable) {
        self.isDone = [Bool](repeating: false, count: arity)
        self.arity = arity
        
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
        
        for i in 0 ..< self.arity {
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
    }
    
    func fail(_ error: Swift.Error) {
        self.forwardOn(.error(error))
        self.dispose()
    }
    
    func done(_ index: Int) {
        self.isDone[index] = true
        
        var allDone = true
        
        for done in self.isDone where !done {
            allDone = false
            break
        }
        
        if allDone {
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final class ZipObserver<Element>
    : ObserverType
    , LockOwnerType
    , SynchronizedOnType {
    typealias ValueSetter = (Element) -> Void

    private var parent: ZipSinkProtocol?
    
    let lock: RecursiveLock
    
    // state
    private let index: Int
    private let this: Disposable
    private let setNextValue: ValueSetter
    
    init(lock: RecursiveLock, parent: ZipSinkProtocol, index: Int, setNextValue: @escaping ValueSetter, this: Disposable) {
        self.lock = lock
        self.parent = parent
        self.index = index
        self.this = this
        self.setNextValue = setNextValue
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        if self.parent != nil {
            switch event {
            case .next:
                break
            case .error:
                self.this.dispose()
            case .completed:
                self.this.dispose()
            }
        }
        
        if let parent = self.parent {
            switch event {
            case .next(let value):
                self.setNextValue(value)
                parent.next(self.index)
            case .error(let error):
                parent.fail(error)
            case .completed:
                parent.done(self.index)
            }
        }
    }
}
