//
//  CombineLatest+Collection.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Merges the specified observable sequences into one observable sequence by using the selector function whenever any of the observable sequences produces an element.

     - seealso: [combinelatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)

     - parameter resultSelector: Function to invoke whenever any of the sources produces an element.
     - returns: An observable sequence containing the result of combining elements of the sources using the specified result selector function.
     */
    public static func combineLatest<C: Collection>(_ collection: C, _ resultSelector: @escaping ([C.Iterator.Element.E]) throws -> E) -> Observable<E>
        where C.Iterator.Element: ObservableType {
        return CombineLatestCollectionType(sources: collection, resultSelector: resultSelector)
    }

    /**
     Merges the specified observable sequences into one observable sequence whenever any of the observable sequences produces an element.

     - seealso: [combinelatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)

     - returns: An observable sequence containing the result of combining elements of the sources.
     */
    public static func combineLatest<C: Collection>(_ collection: C) -> Observable<[E]>
        where C.Iterator.Element: ObservableType, C.Iterator.Element.E == E {
        return CombineLatestCollectionType(sources: collection, resultSelector: { $0 })
    }
}

final private class CombineLatestCollectionTypeSink<C: Collection, O: ObserverType>
    : Sink<O> where C.Iterator.Element: ObservableConvertibleType {
    typealias R = O.E
    typealias Parent = CombineLatestCollectionType<C, R>
    typealias SourceElement = C.Iterator.Element.E
    
    let _parent: Parent
    
    let _lock = RecursiveLock()

    // state
    var _numberOfValues = 0
    var _values: [SourceElement?]
    var _isDone: [Bool]
    var _numberOfDone = 0
    var _subscriptions: [SingleAssignmentDisposable]
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        self._values = [SourceElement?](repeating: nil, count: parent._count)
        self._isDone = [Bool](repeating: false, count: parent._count)
        self._subscriptions = [SingleAssignmentDisposable]()
        self._subscriptions.reserveCapacity(parent._count)
        
        for _ in 0 ..< parent._count {
            self._subscriptions.append(SingleAssignmentDisposable())
        }
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<SourceElement>, atIndex: Int) {
        self._lock.lock(); defer { self._lock.unlock() } // {
            switch event {
            case .next(let element):
                if self._values[atIndex] == nil {
                   self._numberOfValues += 1
                }
                
                self._values[atIndex] = element
                
                if self._numberOfValues < self._parent._count {
                    let numberOfOthersThatAreDone = self._numberOfDone - (self._isDone[atIndex] ? 1 : 0)
                    if numberOfOthersThatAreDone == self._parent._count - 1 {
                        self.forwardOn(.completed)
                        self.dispose()
                    }
                    return
                }
                
                do {
                    let result = try self._parent._resultSelector(self._values.map { $0! })
                    self.forwardOn(.next(result))
                }
                catch let error {
                    self.forwardOn(.error(error))
                    self.dispose()
                }
                
            case .error(let error):
                self.forwardOn(.error(error))
                self.dispose()
            case .completed:
                if self._isDone[atIndex] {
                    return
                }
                
                self._isDone[atIndex] = true
                self._numberOfDone += 1
                
                if self._numberOfDone == self._parent._count {
                    self.forwardOn(.completed)
                    self.dispose()
                }
                else {
                    self._subscriptions[atIndex].dispose()
                }
            }
        // }
    }
    
    func run() -> Disposable {
        var j = 0
        for i in self._parent._sources {
            let index = j
            let source = i.asObservable()
            let disposable = source.subscribe(AnyObserver { event in
                self.on(event, atIndex: index)
            })

            self._subscriptions[j].setDisposable(disposable)
            
            j += 1
        }

        if self._parent._sources.isEmpty {
            self.forwardOn(.completed)
        }
        
        return Disposables.create(_subscriptions)
    }
}

final private class CombineLatestCollectionType<C: Collection, R>: Producer<R> where C.Iterator.Element: ObservableConvertibleType {
    typealias ResultSelector = ([C.Iterator.Element.E]) throws -> R
    
    let _sources: C
    let _resultSelector: ResultSelector
    let _count: Int

    init(sources: C, resultSelector: @escaping ResultSelector) {
        self._sources = sources
        self._resultSelector = resultSelector
        self._count = Int(Int64(self._sources.count))
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == R {
        let sink = CombineLatestCollectionTypeSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
