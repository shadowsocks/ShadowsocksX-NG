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
        _generators.append(sources)

        schedule(.moveNext)

        return _subscription
    }

    func invoke(_ command: TailRecursiveSinkCommand) {
        switch command {
        case .dispose:
            disposeCommand()
        case .moveNext:
            moveNextCommand()
        }
    }

    // simple implementation for now
    func schedule(_ command: TailRecursiveSinkCommand) {
        _gate.invoke(InvocableScheduledItem(invocable: self, state: command))
    }

    func done() {
        forwardOn(.completed)
        dispose()
    }

    func extract(_ observable: Observable<E>) -> SequenceGenerator? {
        rxAbstractMethod()
    }

    // should be done on gate locked

    private func moveNextCommand() {
        var next: Observable<E>? = nil

        repeat {
            guard let (g, left) = _generators.last else {
                break
            }
            
            if _isDisposed {
                return
            }

            _generators.removeLast()
            
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
                    _generators.append((e, knownOriginalLeft - 1))
                }
            }
            else {
                _generators.append((e, nil))
            }

            let nextGenerator = extract(nextCandidate)

            if let nextGenerator = nextGenerator {
                _generators.append(nextGenerator)
                #if DEBUG || TRACE_RESOURCES
                    if maxTailRecursiveSinkStackSize < _generators.count {
                        maxTailRecursiveSinkStackSize = _generators.count
                    }
                #endif
            }
            else {
                next = nextCandidate
            }
        } while next == nil

        guard let existingNext = next else  {
            done()
            return
        }

        let disposable = SingleAssignmentDisposable()
        _subscription.disposable = disposable
        disposable.setDisposable(subscribeToNext(existingNext))
    }

    func subscribeToNext(_ source: Observable<E>) -> Disposable {
        rxAbstractMethod()
    }

    func disposeCommand() {
        _isDisposed = true
        _generators.removeAll(keepingCapacity: false)
    }

    override func dispose() {
        super.dispose()
        
        _subscription.dispose()
        
        schedule(.dispose)
    }
}

