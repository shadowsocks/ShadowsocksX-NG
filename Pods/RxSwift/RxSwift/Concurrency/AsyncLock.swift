//
//  AsyncLock.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/**
In case nobody holds this lock, the work will be queued and executed immediately
on thread that is requesting lock.

In case there is somebody currently holding that lock, action will be enqueued.
When owned of the lock finishes with it's processing, it will also execute
and pending work.

That means that enqueued work could possibly be executed later on a different thread.
*/
final class AsyncLock<I: InvocableType>
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
        self._lock.lock()
    }

    func unlock() {
        self._lock.unlock()
    }
    // }

    private func enqueue(_ action: I) -> I? {
        self._lock.lock(); defer { self._lock.unlock() } // {
            if self._hasFaulted {
                return nil
            }

            if self._isExecuting {
                self._queue.enqueue(action)
                return nil
            }

            self._isExecuting = true

            return action
        // }
    }

    private func dequeue() -> I? {
        self._lock.lock(); defer { self._lock.unlock() } // {
            if !self._queue.isEmpty {
                return self._queue.dequeue()
            }
            else {
                self._isExecuting = false
                return nil
            }
        // }
    }

    func invoke(_ action: I) {
        let firstEnqueuedAction = self.enqueue(action)
        
        if let firstEnqueuedAction = firstEnqueuedAction {
            firstEnqueuedAction.invoke()
        }
        else {
            // action is enqueued, it's somebody else's concern now
            return
        }
        
        while true {
            let nextAction = self.dequeue()

            if let nextAction = nextAction {
                nextAction.invoke()
            }
            else {
                return
            }
        }
    }
    
    func dispose() {
        self.synchronizedDispose()
    }

    func _synchronized_dispose() {
        self._queue = Queue(capacity: 0)
        self._hasFaulted = true
    }
}
