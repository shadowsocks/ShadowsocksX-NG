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
    public static func combineLatest<Collection: Swift.Collection>(_ collection: Collection, resultSelector: @escaping ([Collection.Element.Element]) throws -> Element) -> Observable<Element>
        where Collection.Element: ObservableType {
        CombineLatestCollectionType(sources: collection, resultSelector: resultSelector)
    }

    /**
     Merges the specified observable sequences into one observable sequence whenever any of the observable sequences produces an element.

     - seealso: [combinelatest operator on reactivex.io](http://reactivex.io/documentation/operators/combinelatest.html)

     - returns: An observable sequence containing the result of combining elements of the sources.
     */
    public static func combineLatest<Collection: Swift.Collection>(_ collection: Collection) -> Observable<[Element]>
        where Collection.Element: ObservableType, Collection.Element.Element == Element {
        CombineLatestCollectionType(sources: collection, resultSelector: { $0 })
    }
}

final private class CombineLatestCollectionTypeSink<Collection: Swift.Collection, Observer: ObserverType>
    : Sink<Observer> where Collection.Element: ObservableConvertibleType {
    typealias Result = Observer.Element 
    typealias Parent = CombineLatestCollectionType<Collection, Result>
    typealias SourceElement = Collection.Element.Element
    
    let parent: Parent
    
    let lock = RecursiveLock()

    // state
    var numberOfValues = 0
    var values: [SourceElement?]
    var isDone: [Bool]
    var numberOfDone = 0
    var subscriptions: [SingleAssignmentDisposable]
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        self.values = [SourceElement?](repeating: nil, count: parent.count)
        self.isDone = [Bool](repeating: false, count: parent.count)
        self.subscriptions = [SingleAssignmentDisposable]()
        self.subscriptions.reserveCapacity(parent.count)
        
        for _ in 0 ..< parent.count {
            self.subscriptions.append(SingleAssignmentDisposable())
        }
        
        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<SourceElement>, atIndex: Int) {
        self.lock.lock(); defer { self.lock.unlock() }
        switch event {
        case .next(let element):
            if self.values[atIndex] == nil {
                self.numberOfValues += 1
            }
            
            self.values[atIndex] = element
            
            if self.numberOfValues < self.parent.count {
                let numberOfOthersThatAreDone = self.numberOfDone - (self.isDone[atIndex] ? 1 : 0)
                if numberOfOthersThatAreDone == self.parent.count - 1 {
                    self.forwardOn(.completed)
                    self.dispose()
                }
                return
            }
            
            do {
                let result = try self.parent.resultSelector(self.values.map { $0! })
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
            if self.isDone[atIndex] {
                return
            }
            
            self.isDone[atIndex] = true
            self.numberOfDone += 1
            
            if self.numberOfDone == self.parent.count {
                self.forwardOn(.completed)
                self.dispose()
            }
            else {
                self.subscriptions[atIndex].dispose()
            }
        }
    }
    
    func run() -> Disposable {
        var j = 0
        for i in self.parent.sources {
            let index = j
            let source = i.asObservable()
            let disposable = source.subscribe(AnyObserver { event in
                self.on(event, atIndex: index)
            })

            self.subscriptions[j].setDisposable(disposable)
            
            j += 1
        }

        if self.parent.sources.isEmpty {
            do {
                let result = try self.parent.resultSelector([])
                self.forwardOn(.next(result))
                self.forwardOn(.completed)
                self.dispose()
            }
            catch let error {
                self.forwardOn(.error(error))
                self.dispose()
            }
        }
        
        return Disposables.create(subscriptions)
    }
}

final private class CombineLatestCollectionType<Collection: Swift.Collection, Result>: Producer<Result> where Collection.Element: ObservableConvertibleType {
    typealias ResultSelector = ([Collection.Element.Element]) throws -> Result
    
    let sources: Collection
    let resultSelector: ResultSelector
    let count: Int

    init(sources: Collection, resultSelector: @escaping ResultSelector) {
        self.sources = sources
        self.resultSelector = resultSelector
        self.count = self.sources.count
    }
    
    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == Result {
        let sink = CombineLatestCollectionTypeSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
