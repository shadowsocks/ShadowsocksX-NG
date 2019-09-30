//
//  TailRecursiveSink.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

enum TailRecursiveSinkCommand {
    case moveNext
    case dispose
}

#if DEBUG || TRACE_RESOURCES
    public var maxTailRecursiveSinkStackSize = 0
#endif

/// This class is usually used with `Generator` version of the operators.
class TailRecursiveSink<S: Sequence, O: ObserverType>
    : Sink<O>
    , InvocableWithValueType where S.Iterator.Element: ObservableConvertibleType, S.Iterator.Element.E == O.E {
    typealias Value = TailRecursiveSinkCommand
    typealias E = O.E
    typealias SequenceGenerator = (generator: S.Iterator, remaining: IntMax?)

    var _generators: [SequenceGenerator] = []
    var _isDisposed = false
    var _subscription = SerialDisposable()

    // this is thread safe object
    var _gate = AsyncLock<InvocableScheduledItem<TailRecursiveSink<S, O>>>()

    override init(observer: O, cancel: Cancelable) {
        super.init(observer: observer, cancel: cancel)
    }

    func run(_ sources: SequenceGenerator) -> Disposable {
        self._generators.append(sources)

        self.schedule(.moveNext)

        return self._subscription
    }

    func invoke(_ command: TailRecursiveSinkCommand) {
        switch command {
        case .dispose:
            self.disposeCommand()
        case .moveNext:
            self.moveNextCommand()
        }
    }

    // simple implementation for now
    func schedule(_ command: TailRecursiveSinkCommand) {
        self._gate.invoke(InvocableScheduledItem(invocable: self, state: command))
    }

    func done() {
        self.forwardOn(.completed)
        self.dispose()
    }

    func extract(_ observable: Observable<E>) -> SequenceGenerator? {
        rxAbstractMethod()
    }

    // should be done on gate locked

    private func moveNextCommand() {
        var next: Observable<E>?

        repeat {
            guard let (g, left) = self._generators.last else {
                break
            }
            
            if self._isDisposed {
                return
            }

            self._generators.removeLast()
            
            var e = g

            guard let nextCandidate = e.next()?.asObservable() else {
                continue
            }

            // `left` is a hint of how many elements are left in generator.
            // In case this is the last element, then there is no need to push
            // that generator on stack.
            //
            // This is an optimization used to make sure in tail recursive case
            // there is no memory leak in case this operator is used to generate non terminating
            // sequence.

            if let knownOriginalLeft = left {
                // `- 1` because generator.next() has just been called
                if knownOriginalLeft - 1 >= 1 {
                    self._generators.append((e, knownOriginalLeft - 1))
                }
            }
            else {
                self._generators.append((e, nil))
            }

            let nextGenerator = self.extract(nextCandidate)

            if let nextGenerator = nextGenerator {
                self._generators.append(nextGenerator)
                #if DEBUG || TRACE_RESOURCES
                    if maxTailRecursiveSinkStackSize < self._generators.count {
                        maxTailRecursiveSinkStackSize = self._generators.count
                    }
                #endif
            }
            else {
                next = nextCandidate
            }
        } while next == nil

        guard let existingNext = next else {
            self.done()
            return
        }

        let disposable = SingleAssignmentDisposable()
        self._subscription.disposable = disposable
        disposable.setDisposable(self.subscribeToNext(existingNext))
    }

    func subscribeToNext(_ source: Observable<E>) -> Disposable {
        rxAbstractMethod()
    }

    func disposeCommand() {
        self._isDisposed = true
        self._generators.removeAll(keepingCapacity: false)
    }

    override func dispose() {
        super.dispose()
        
        self._subscription.dispose()
        self._gate.dispose()
        
        self.schedule(.dispose)
    }
}

