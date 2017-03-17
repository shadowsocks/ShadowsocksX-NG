//
//  AsyncLock.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/**
In case nobody holds this lock, the work will be queued and executed immediately
on thread that is requesting lock.

In case there is somebody currently holding that lock, action will be enqueued.
When owned of the lock finishes with it's processing, it will also execute
and pending work.

That means that enqueued work could possibly be executed later on a different thread.
*/
class AsyncLock<I: InvocableType>
    : Disposable
    , Lock
    , SynchronizedDisposeType {
    typealias Action = () -> Void
    
    var _lock = SpinLock()
    
    private var _queue: Queue<I> = Queue(capacity: 0)

    private var _isExecuting: Bool = false
    private var _hasFaulted: Bool = false

    // lock {
    func lock() {
        _lock.lock()
    }

    func unlock() {
        _lock.unlock()
    }
    // }

    private func enqueue(_ action: I) -> I? {
        _lock.lock(); defer { _lock.unlock() } // {
            if _hasFaulted {
                return nil
            }

            if _isExecuting {
                _queue.enqueue(action)
                return nil
            }

            _isExecuting = true

            return action
        // }
    }

    private func dequeue() -> I? {
        _lock.lock(); defer { _lock.unlock() } // {
            if _queue.count > 0 {
                return _queue.dequeue()
            }
            else {
                _isExecuting = false
                return nil
            }
        // }
    }

    func invoke(_ action: I) {
        let firstEnqueuedAction = enqueue(action)
        
        if let firstEnqueuedAction = firstEnqueuedAction {
            firstEnqueuedAction.invoke()
        }
        else {
            // action is enqueued, it's somebody else's concern now
            return
        }
        
        while true {
            let nextAction = dequeue()

            if let nextAction = nextAction {
                nextAction.invoke()
            }
            else {
                return
            }
        }
    }
    
    func dispose() {
        synchronizedDispose()
    }

    func _synchronized_dispose() {
        _queue = Queue(capacity: 0)
        _hasFaulted = true
    }
}
