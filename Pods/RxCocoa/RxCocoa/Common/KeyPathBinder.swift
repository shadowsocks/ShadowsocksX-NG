//
//  KeyPathBinder.swift
//  RxCocoa
//
//  Created by Ryo Aoyama on 2/7/18.
//  Copyright © 2018 Krunoslav Zaher. All rights reserved.
//

import RxSwift

extension Reactive where Base: AnyObject {
    
    /// Bindable sink for arbitrary property using the given key path.
    /// Binding runs on the MainScheduler.
    ///
    /// - parameter keyPath: Key path to write to the property.
    public subscript<Value>(keyPath: ReferenceWritableKeyPath<Base, Value>) -> Binder<Value> {
        return Binder(self.base) { base, value in
            base[keyPath: keyPath] = value
        }
    }
    
    /// Bindable sink for arbitrary property using the given key path.
    /// Binding runs on the specified scheduler.
    ///
    /// - parameter keyPath: Key path to write to the property.
    /// - parameter scheduler: Scheduler to run bindings on.
    public subscript<Value>(keyPath: ReferenceWritableKeyPath<Base, Value>, on scheduler: ImmediateSchedulerType) -> Binder<Value> {
        return Binder(self.base, scheduler: scheduler) { base, value in
            base[keyPath: keyPath] = value
        }
    }
    
}
