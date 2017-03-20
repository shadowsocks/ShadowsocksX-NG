//
//  OperationQueueScheduler.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/4/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import class Foundation.OperationQueue
import class Foundation.BlockOperation
import Dispatch

/// Abstracts the work that needs to be performed on a specific `NSOperationQueue`.
///
/// This scheduler is suitable for cases when there is some bigger chunk of work that needs to be performed in background and you want to fine tune concurrent processing using `maxConcurrentOperationCount`.
public class OperationQueueScheduler: ImmediateSchedulerType {
    public let operationQueue: OperationQueue
    
    /// Constructs new instance of `OperationQueueScheduler` that performs work on `operationQueue`.
    ///
    /// - parameter operationQueue: Operation queue targeted to perform work on.
    public init(operationQueue: OperationQueue) {
        self.operationQueue = operationQueue
    }
    
    /**
    Schedules an action to be executed recursively.
    
    - parameter state: State passed to the action to be executed.
    - parameter action: Action to execute recursively. The last parameter passed to the action is used to trigger recursive scheduling of the action, passing in recursive invocation state.
    - returns: The disposable object used to cancel the scheduled action (best effort).
    */
    public func schedule<StateType>(_ state: StateType, action: @escaping (StateType) -> Disposable) -> Disposable {
        let cancel = SingleAssignmentDisposable()

        let operation = BlockOperation {
            if cancel.isDisposed {
                return
            }


            cancel.setDisposable(action(state))
        }

        self.operationQueue.addOperation(operation)
        
        return cancel
    }

}
