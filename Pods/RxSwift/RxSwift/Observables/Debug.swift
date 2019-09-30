//
//  Debug.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/2/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import struct Foundation.Date
import class Foundation.DateFormatter

extension ObservableType {

    /**
     Prints received events for all observers on standard output.

     - seealso: [do operator on reactivex.io](http://reactivex.io/documentation/operators/do.html)

     - parameter identifier: Identifier that is printed together with event description to standard output.
     - parameter trimOutput: Should output be trimmed to max 40 characters.
     - returns: An observable sequence whose events are printed to standard output.
     */
    public func debug(_ identifier: String? = nil, trimOutput: Bool = false, file: String = #file, line: UInt = #line, function: String = #function)
        -> Observable<E> {
            return Debug(source: self, identifier: identifier, trimOutput: trimOutput, file: file, line: line, function: function)
    }
}

fileprivate let dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

fileprivate func logEvent(_ identifier: String, dateFormat: DateFormatter, content: String) {
    print("\(dateFormat.string(from: Date())): \(identifier) -> \(content)")
}

final private class DebugSink<Source: ObservableType, O: ObserverType>: Sink<O>, ObserverType where O.E == Source.E {
    typealias Element = O.E
    typealias Parent = Debug<Source>
    
    private let _parent: Parent
    private let _timestampFormatter = DateFormatter()
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        self._parent = parent
        self._timestampFormatter.dateFormat = dateFormat

        logEvent(self._parent._identifier, dateFormat: self._timestampFormatter, content: "subscribed")

        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        let maxEventTextLength = 40
        let eventText = "\(event)"

        let eventNormalized = (eventText.count > maxEventTextLength) && self._parent._trimOutput
            ? String(eventText.prefix(maxEventTextLength / 2)) + "..." + String(eventText.suffix(maxEventTextLength / 2))
            : eventText

        logEvent(self._parent._identifier, dateFormat: self._timestampFormatter, content: "Event \(eventNormalized)")

        self.forwardOn(event)
        if event.isStopEvent {
            self.dispose()
        }
    }
    
    override func dispose() {
        if !self.disposed {
            logEvent(self._parent._identifier, dateFormat: self._timestampFormatter, content: "isDisposed")
        }
        super.dispose()
    }
}

final private class Debug<Source: ObservableType>: Producer<Source.E> {
    fileprivate let _identifier: String
    fileprivate let _trimOutput: Bool
    fileprivate let _source: Source

    init(source: Source, identifier: String?, trimOutput: Bool, file: String, line: UInt, function: String) {
        self._trimOutput = trimOutput
        if let identifier = identifier {
            self._identifier = identifier
        }
        else {
            let trimmedFile: String
            if let lastIndex = file.lastIndexOf("/") {
                trimmedFile = String(file[file.index(after: lastIndex) ..< file.endIndex])
            }
            else {
                trimmedFile = file
            }
            self._identifier = "\(trimmedFile):\(line) (\(function))"
        }
        self._source = source
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Source.E {
        let sink = DebugSink(parent: self, observer: observer, cancel: cancel)
        let subscription = self._source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
