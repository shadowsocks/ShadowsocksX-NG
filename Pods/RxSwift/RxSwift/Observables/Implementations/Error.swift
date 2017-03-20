//
//  Error.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/30/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

final class ErrorProducer<Element> : Producer<Element> {
    private let _error: Swift.Error
    
    init(error: Swift.Error) {
        _error = error
    }
    
    override func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == Element {
        observer.on(.error(_error))
        return Disposables.create()
    }
}
