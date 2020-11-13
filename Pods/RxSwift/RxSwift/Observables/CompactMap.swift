//
//  CompactMap.swift
//  RxSwift
//
//  Created by Michael Long on 04/09/2019.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {

    /**
     Projects each element of an observable sequence into an optional form and filters all optional results.

     Equivalent to:

     func compactMap<Result>(_ transform: @escaping (Self.E) throws -> Result?) -> RxSwift.Observable<Result> {
        return self.map { try? transform($0) }.filter { $0 != nil }.map { $0! }
     }

     - parameter transform: A transform function to apply to each source element and which returns an element or nil.
     - returns: An observable sequence whose elements are the result of filtering the transform function for each element of the source.

     */
    public func compactMap<Result>(_ transform: @escaping (Element) throws -> Result?)
        -> Observable<Result> {
            return CompactMap(source: self.asObservable(), transform: transform)
    }
}

final private class CompactMapSink<SourceType, Observer: ObserverType>: Sink<Observer>, ObserverType {
    typealias Transform = (SourceType) throws -> ResultType?

    typealias ResultType = Observer.Element 
    typealias Element = SourceType

    private let _transform: Transform

    init(transform: @escaping Transform, observer: Observer, cancel: Cancelable) {
        self._transform = transform
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<SourceType>) {
        switch event {
        case .next(let element):
            do {
                if let mappedElement = try self._transform(element) {
                    self.forwardOn(.next(mappedElement))
                }
            }
            catch let e {
                self.forwardOn(.error(e))
                self.dispose()
            }
        case .error(let error):
            self.forwardOn(.error(error))
            self.dispose()
        case .completed:
            self.forwardOn(.completed)
            self.dispose()
        }
    }
}

final private class CompactMap<SourceType, ResultType>: Producer<ResultType> {
    typealias Transform = (SourceType) throws -> ResultType?

    private let _source: Observable<SourceType>

    private let _transform: Transform

    init(source: Observable<SourceType>, transform: @escaping Transform) {
        self._source = source
        self._transform = transform
    }

    override func run<Observer: ObserverType>(_ observer: Observer, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where Observer.Element == ResultType {
        let sink = CompactMapSink(transform: self._transform, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
