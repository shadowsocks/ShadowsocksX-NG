//
//  CombineLatest+Collection.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/29/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension Observable {
    /**
     Merges the specified observable sequences into one observable sequence by using the selector function whenever any of the observable sequences produces an element.

     - seealso: [combinelatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)

     - parameter resultSelector: Function to invoke whenever any of the sources produces an element.
     - returns: An observable sequence containing the result of combining elements of the sources using the specified result selector function.
     */
    public static func combineLatest<C: Collection>(_ collection: C, _ resultSelector: @escaping ([C.Iterator.Element.E]) throws -> Element) -> Observable<Element>
        where C.Iterator.Element: ObservableType {
        return CombineLatestCollectionType(sources: collection, resultSelector: resultSelector)
    }

    /**
     Merges the specified observable sequences into one observable sequence whenever any of the observable sequences produces an element.

     - seealso: [combinelatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)

     - returns: An observable sequence containing the result of combining elements of the sources.
     */
    public static func combineLatest<C: Collection>(_ collection: C) -> Observable<[Element]>
        where C.Iterator.Element: ObservableType, C.Iterator.Element.E == Element {
        return CombineLatestCollectionType(sources: collection, resultSelector: { $0 })
    }
}

final fileprivate class CombineLatestCollectionTypeSink<C: Collection, O: ObserverType>
    : Sink<O> where C.Iterator.Element : ObservableConvertibleType {
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
        _parent = parent
        _values = [SourceElement?](repeating: nil, count: parent._count)
        _isDone = [Bool](repeating: false, count: parent._count)
        _subscriptions = Array<SingleAssignmentDisposable>()
        _subscriptions.reserveCapacity(parent._count)
        
        for _ in 0 ..< parent._count {
            _subscriptions.append(SingleAssignmentDisposable())
        }
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<SourceElement>, atIndex: Int) {
        _lock.lock(); defer { _lock.unlock() } // {
            switch event {
            case .next(let element):
                if _values[atIndex] == nil {
                   _numberOfValues += 1
                }
                
                _values[atIndex] = element
                
                if _numberOfValues < _parent._count {
                    let numberOfOthersThatAreDone = self._numberOfDone - (_isDone[atIndex] ? 1 : 0)
                    if numberOfOthersThatAreDone == self._parent._count - 1 {
                        forwardOn(.completed)
                        dispose()
                    }
                    return
                }
                
                do {
                    let result = try _parent._resultSelector(_values.map { $0! })
                    forwardOn(.next(result))
                }
                catch let error {
                    forwardOn(.error(error))
                    dispose()
                }
                
            case .error(let error):
                forwardOn(.error(error))
                dispose()
            case .completed:
                if _isDone[atIndex] {
                    return
                }
                
                _isDone[atIndex] = true
                _numberOfDone += 1
                
                if _numberOfDone == self._parent._count {
                    forwardOn(.completed)
                    dispose()
                }
                else {
                    _subscriptions[atIndex].dispose()
                }
            }
        // }
    }
    
    func run() -> Disposable {
        var j = 0
        for i in _parent._sources {
            let index = j
            let source = i.asObservable()
            let disposable = source.subscribe(AnyObserver { event in
                self.on(event, atIndex: index)
            })

            _subscriptions[j].setDisposable(disposable)
            
            j += 1
        }

        if _parent._sources.isEmpty {
            self.forwardOn(.completed)
        }
        
        return Disposables.create(_subscriptions)
    }
}

final fileprivate class CombineLatestCollectionType<C: Collection, R> : Producer<R> where C.Iterator.Element : ObservableConvertibleType {
    typealias ResultSelector = ([C.Iterator.Element.E]) throws -> R
    
    let _sources: C
    let _resultSelector: ResultSelector
    let _count: Int

    init(sources: C, resultSelector: @escaping ResultSelector) {
        _sources = sources
        _resultSelector = resultSelector
        _count = Int(self._sources.count.toIntMax())
    }
    
    override func run<O : ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == R {
        let sink = CombineLatestCollectionTypeSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
