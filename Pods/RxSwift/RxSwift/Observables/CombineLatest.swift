//
//  CombineLatest.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

protocol CombineLatestProtocol: AnyObject {
    func next(_ index: Int)
    func fail(_ error: Swift.Error)
    func done(_ index: Int)
}

class CombineLatestSink<Observer: ObserverType>
    : Sink<Observer>
    , CombineLatestProtocol {
    typealias Element = Observer.Element 
   
    let lock = RecursiveLock()

    private let arity: Int
    private var numberOfValues = 0
    private var numberOfDone = 0
    private var hasValue: [Bool]
    private var isDone: [Bool]
   
    init(arity: Int, observer: Observer, cancel: Cancelable) {
        self.arity = arity
        self.hasValue = [Bool](repeating: false, count: arity)
        self.isDone = [Bool](repeating: false, count: arity)
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func getResult() throws -> Element {
        rxAbstractMethod()
    }
    
    func next(_ index: Int) {
        if !self.hasValue[index] {
            self.hasValue[index] = true
            self.numberOfValues += 1
        }

        if self.numberOfValues == self.arity {
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

            for i in 0 ..< self.arity {
                if i != index && !self.isDone[i] {
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
        if self.isDone[index] {
            return
        }

        self.isDone[index] = true
        self.numberOfDone += 1

        if self.numberOfDone == self.arity {
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
    
    private let parent: CombineLatestProtocol
    
    let lock: RecursiveLock
    private let index: Int
    private let this: Disposable
    private let setLatestValue: ValueSetter
    
    init(lock: RecursiveLock, parent: CombineLatestProtocol, index: Int, setLatestValue: @escaping ValueSetter, this: Disposable) {
        self.lock = lock
        self.parent = parent
        self.index = index
        self.this = this
        self.setLatestValue = setLatestValue
    }
    
    func on(_ event: Event<Element>) {
        self.synchronizedOn(event)
    }

    func synchronized_on(_ event: Event<Element>) {
        switch event {
        case .next(let value):
            self.setLatestValue(value)
            self.parent.next(self.index)
        case .error(let error):
            self.this.dispose()
            self.parent.fail(error)
        case .completed:
            self.this.dispose()
            self.parent.done(self.index)
        }
    }
}
