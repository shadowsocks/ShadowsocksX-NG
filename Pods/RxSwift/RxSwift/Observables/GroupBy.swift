//
//  GroupBy.swift
//  RxSwift
//
//  Created by Tomi Koskinen on 01/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /*
     Groups the elements of an observable sequence according to a specified key selector function.

     - seealso: [groupBy operator on reactivex.io](http://reactivex.io/documentation/operators/groupby.html)

     - parameter keySelector: A function to extract the key for each element.
     - returns: A sequence of observable groups, each of which corresponds to a unique key value, containing all elements that share that same key value.
     */
    public func groupBy<Key: Hashable>(keySelector: @escaping (Element) throws -> Key)
        -> Observable<GroupedObservable<Key, Element>> {
        GroupBy(source: self.asObservable(), selector: keySelector)
    }
}

final private class GroupedObservableImpl<Element>: Observable<Element> {
    private var subject: PublishSubject<Element>
    private var refCount: RefCountDisposable
    
    init(subject: PublishSubject<Element>, refCount: RefCountDisposable) {
        self.subject = subject
        self.refCount = refCount
    }

    override public func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element {
        let release = self.refCount.retain()
        let subscription = self.subject.subscribe(observer)
        return Disposables.create(release, subscription)
    }
}


final private class GroupBySink<Key: Hashable, Element, Observer: ObserverType>
    : Sink<Observer>
    , ObserverType where Observer.Element == GroupedObservable<Key, Element> {
    typealias ResultType = Observer.Element 
    typealias Parent = GroupBy<Key, Element>

    private let parent: Parent
    private let subscription = SingleAssignmentDisposable()
    private var refCountDisposable: RefCountDisposable!
    private var groupedSubjectTable: [Key: PublishSubject<Element>]
    
    init(parent: Parent, observer: Observer, cancel: Cancelable) {
        self.parent = parent
        self.groupedSubjectTable = [Key: PublishSubject<Element>]()
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        self.refCountDisposable = RefCountDisposable(disposable: self.subscription)
        
        self.subscription.setDisposable(self.parent.source.subscribe(self))
        
        return self.refCountDisposable
    }
    
    private func onGroupEvent(key: Key, value: Element) {
        if let writer = self.groupedSubjectTable[key] {
            writer.on(.next(value))
        } else {
            let writer = PublishSubject<Element>()
            self.groupedSubjectTable[key] = writer
            
            let group = GroupedObservable(
                key: key,
                source: GroupedObservableImpl(subject: writer, refCount: refCountDisposable)
            )
            
            self.forwardOn(.next(group))
            writer.on(.next(value))
        }
    }

    final func on(_ event: Event<Element>) {
        switch event {
        case let .next(value):
            do {
                let groupKey = try self.parent.selector(value)
                self.onGroupEvent(key: groupKey, value: value)
            }
            catch let e {
                self.error(e)
                return
            }
        case let .error(e):
            self.error(e)
        case .completed:
            self.forwardOnGroups(event: .completed)
            self.forwardOn(.completed)
            self.subscription.dispose()
            self.dispose()
        }
    }

    final func error(_ error: Swift.Error) {
        self.forwardOnGroups(event: .error(error))
        self.forwardOn(.error(error))
        self.subscription.dispose()
        self.dispose()
    }
    
    final func forwardOnGroups(event: Event<Element>) {
        for writer in self.groupedSubjectTable.values {
            writer.on(event)
        }
    }
}

final private class GroupBy<Key: Hashable, Element>: Producer<GroupedObservable<Key,Element>> {
    typealias KeySelector = (Element) throws -> Key

    fileprivate let source: Observable<Element>
    fileprivate let selector: KeySelector
    
    init(source: Observable<Element>, selector: @escaping KeySelector) {
        self.source = source
        self.selector = selector
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == GroupedObservable<Key,Element> {
        let sink = GroupBySink(parent: self, observer: observer, cancel: cancel)
        return (sink: sink, subscription: sink.run())
    }
}
