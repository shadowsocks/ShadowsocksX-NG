//
//  Deprecated.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/5/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

extension Observable {
    /**
     Converts a optional to an observable sequence.
     
     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)
     
     - parameter optional: Optional element in the resulting observable sequence.
     - returns: An observable sequence containing the wrapped value or not from given optional.
     */
    @available(*, deprecated, message: "Implicit conversions from any type to optional type are allowed and that is causing issues with `from` operator overloading.", renamed: "from(optional:)")
    public static func from(_ optional: E?) -> Observable<E> {
        return Observable.from(optional: optional)
    }

    /**
     Converts a optional to an observable sequence.

     - seealso: [from operator on reactivex.io](http://reactivex.io/documentation/operators/from.html)

     - parameter optional: Optional element in the resulting observable sequence.
     - parameter: Scheduler to send the optional element on.
     - returns: An observable sequence containing the wrapped value or not from given optional.
     */
    @available(*, deprecated, message: "Implicit conversions from any type to optional type are allowed and that is causing issues with `from` operator overloading.", renamed: "from(optional:scheduler:)")
    public static func from(_ optional: E?, scheduler: ImmediateSchedulerType) -> Observable<E> {
        return Observable.from(optional: optional, scheduler: scheduler)
    }
}

extension Disposable {
    /// Deprecated in favor of `disposed(by:)`
    ///
    /// **@available(\*, deprecated, message="use disposed(by:) instead")**
    ///
    /// Adds `self` to `bag`.
    ///
    /// - parameter bag: `DisposeBag` to add `self` to.
    public func addDisposableTo(_ bag: DisposeBag) {
        disposed(by: bag)
    }
}
