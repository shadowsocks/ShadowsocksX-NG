//
//  DispatchQueueConfiguration.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 7/23/16.
//  Copyright © 2016 Krunoslav Zaher. All rights reserved.
//

import Dispatch
import Foundation

struct DispatchQueueConfiguration {
    let queue: DispatchQueue
    let leeway: DispatchTimeInterval
}

extension DispatchQueueConfiguration {
    func schedule<StateType>(_ state: StateType, action: @escaping (StateType) -> Disposable) -> Disposable {
        let cancel = SingleAssignmentDisposable()

        self.queue.async {
            if cancel.isDisposed {
                return
            }


            cancel.setDisposable(action(state))
        }

        return cancel
    }

    func scheduleRelative<StateType>(_ state: StateType, dueTime: RxTimeInterval, action: @escaping (StateType) -> Disposable) -> Disposable {
        let deadline = DispatchTime.now() + dueTime

        let compositeDisposable = CompositeDisposable()

        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: deadline, leeway: self.leeway)

        // TODO:
        // This looks horrible, and yes, it is.
        // It looks like Apple has made a conceputal change here, and I'm unsure why.
        // Need more info on this.
        // It looks like just setting timer to fire and not holding a reference to it
        // until deadline causes timer cancellation.
        var timerReference: DispatchSourceTimer? = timer
        let cancelTimer = Disposables.create {
            timerReference?.cancel()
            timerReference = nil
        }

        timer.setEventHandler(handler: {
            if compositeDisposable.isDisposed {
                return
            }
            _ = compositeDisposable.insert(action(state))
            cancelTimer.dispose()
        })
        timer.resume()

        _ = compositeDisposable.insert(cancelTimer)

        return compositeDisposable
    }

    func schedulePeriodic<StateType>(_ state: StateType, startAfter: RxTimeInterval, period: RxTimeInterval, action: @escaping (StateType) -> StateType) -> Disposable {
        let initial = DispatchTime.now() + startAfter

        var timerState = state

        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: initial, repeating: period, leeway: self.leeway)
        
        // TODO:
        // This looks horrible, and yes, it is.
        // It looks like Apple has made a conceputal change here, and I'm unsure why.
        // Need more info on this.
        // It looks like just setting timer to fire and not holding a reference to it
        // until deadline causes timer cancellation.
        var timerReference: DispatchSourceTimer? = timer
        let cancelTimer = Disposables.create {
            timerReference?.cancel()
            timerReference = nil
        }

        timer.setEventHandler(handler: {
            if cancelTimer.isDisposed {
                return
            }
            timerState = action(timerState)
        })
        timer.resume()
        
        return cancelTimer
    }
}
