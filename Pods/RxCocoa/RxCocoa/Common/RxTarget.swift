//
//  RxTarget.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 7/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

import RxSwift

class RxTarget : NSObject
               , Disposable {
    
    private var retainSelf: RxTarget?
    
    override init() {
        super.init()
        self.retainSelf = self

#if TRACE_RESOURCES
        _ = Resources.incrementTotal()
#endif

#if DEBUG
        MainScheduler.ensureRunningOnMainThread()
#endif
    }
    
    func dispose() {
#if DEBUG
        MainScheduler.ensureRunningOnMainThread()
#endif
        self.retainSelf = nil
    }

#if TRACE_RESOURCES
    deinit {
        _ = Resources.decrementTotal()
    }
#endif
}
