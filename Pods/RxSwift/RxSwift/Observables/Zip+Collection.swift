//
//  Zip+Collection.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/30/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Merges the specified observable sequences into one observable sequence by using the selector function whenever all of the observable sequences have produced an element at a corresponding index.

     - seealso: [zip operator on reactivex.io](http://reactivex.io/documentation/operators/zip.html)

     - parameter resultSelector: Function to invoke for each series of elements at corresponding indexes in the sources.
     - returns: An observable sequence containing the result of combining elements of the sources using the specified result selector function.
     */
    public static func zip<Collection: Swift.Collection>(_ collection: Collection, resultSelector: @escaping ([Collection.Element.Element]) throws -> Element) -> Observable<Element>
        where Collection.Element: ObservableType {
        ZipCollectionType(sources: collection, resultSelector: resultSelector)
    }

    /**
     Merges the specified observable sequences into one observable sequence whenever all of the observable sequences have produced an element at a corresponding index.

     - seealso: [zip operator on reactivex.io](http://reactivex.io/documentation/operators/zip.html)

     - returns: An observable sequence containing the result of combining elements of the sources.
     */
    public static func zip<Collection: Swift.Collection>(_ collection: Collection) -> Observable<[Element]>
        where Collection.Element: ObservableType, Collection.Element.Element == Element {
        ZipCollectionType(sources: collection, resultSelector: { $0 })
    }
    
}

final private class ZipCollectionTypeSink<Collection: Swift.Collection, Observer: ObserverType>
    : Sink<Observer> where Collection.Element: ObservableConvertibleType {
    typealias Result = Observer.Element 
    typealias Parent = ZipCollectionType<Collection, Result>
    typealias SourceElement = Collection.Element.Element
    
    private let parent: Parent
    
    private let lock = RecursiveLock()
    
    // state
    private var numberOfValues = 0
    private var values: [Queue<SourceElement>]
    private var isDone: [Bool]
    private var numberOfDone = 0
    private var subscriptions: [SingleAssignmentDisposable]
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        self.values = [Queue<SourceElement>](repeating: Queue(capacity: 4), count: parent.count)
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
            self.values[atIndex].enqueue(element)
            
            if self.values[atIndex].count == 1 {
                self.numberOfValues += 1
            }
            
            if self.numberOfValues < self.parent.count {
                if self.numberOfDone == self.parent.count - 1 {
                    self.forwardOn(.completed)
                    self.dispose()
                }
                return
            }
            
            do {
                var arguments = [SourceElement]()
                arguments.reserveCapacity(self.parent.count)
                
                // recalculate number of values
                self.numberOfValues = 0
                
                for i in 0 ..< self.values.count {
                    arguments.append(self.values[i].dequeue()!)
                    if !self.values[i].isEmpty {
                        self.numberOfValues += 1
                    }
                }
                
                let result = try self.parent.resultSelector(arguments)
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
            self.forwardOn(.completed)
        }
        
        return Disposables.create(subscriptions)
    }
}

final private class ZipCollectionType<Collection: Swift.Collection, Result>: Producer<Result> where Collection.Element: ObservableConvertibleType {
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
        let sink = ZipCollectionTypeSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}
