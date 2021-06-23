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
    
    private var _lock = SpinLock()
    
    private var queue: Queue<I> = Queue(capacity: 0)

    private var isExecuting: Bool = false
    private var hasFaulted: Bool = false

    // lock {
    func lock() {
        self._lock.lock()
    }

    func unlock() {
        self._lock.unlock()
    }
    // }

    private func enqueue(_ action: I) -> I? {
        self.lock(); defer { self.unlock() }
        if self.hasFaulted {
            return nil
        }
        
        if self.isExecuting {
            self.queue.enqueue(action)
            return nil
        }
        
        self.isExecuting = true
        
        return action
    }

    private func dequeue() -> I? {
        self.lock(); defer { self.unlock() }
        if !self.queue.isEmpty {
            return self.queue.dequeue()
        }
        else {
            self.isExecuting = false
            return nil
        }
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

    func synchronized_dispose() {
        self.queue = Queue(capacity: 0)
        self.hasFaulted = true
    }
}
