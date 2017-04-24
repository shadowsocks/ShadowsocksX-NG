//
//  Debug.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 5/2/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import struct Foundation.Date
import class Foundation.DateFormatter

let dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

func logEvent(_ identifier: String, dateFormat: DateFormatter, content: String) {
    print("\(dateFormat.string(from: Date())): \(identifier) -> \(content)")
}

final class DebugSink<Source: ObservableType, O: ObserverType> : Sink<O>, ObserverType where O.E == Source.E {
    typealias Element = O.E
    typealias Parent = Debug<Source>
    
    private let _parent: Parent
    private let _timestampFormatter = DateFormatter()
    
    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        _timestampFormatter.dateFormat = dateFormat

        logEvent(_parent._identifier, dateFormat: _timestampFormatter, content: "subscribed")

        super.init(observer: observer, cancel: cancel)
    }
    
    func on(_ event: Event<Element>) {
        let maxEventTextLength = 40
        let eventText = "\(event)"

        let eventNormalized = (eventText.characters.count > maxEventTextLength) && _parent._trimOutput
            ? String(eventText.characters.prefix(maxEventTextLength / 2)) + "..." + String(eventText.characters.suffix(maxEventTextLength / 2))
            : eventText

        logEvent(_parent._identifier, dateFormat: _timestampFormatter, content: "Event \(eventNormalized)")

        forwardOn(event)
        if event.isStopEvent {
            dispose()
        }
    }
    
    override func dispose() {
        if !self.disposed {
            logEvent(_parent._identifier, dateFormat: _timestampFormatter, content: "isDisposed")
        }
        super.dispose()
    }
}

final class Debug<Source: ObservableType> : Producer<Source.E> {
    fileprivate let _identifier: String
    fileprivate let _trimOutput: Bool
    fileprivate let _source: Source

    init(source: Source, identifier: String?, trimOutput: Bool, file: String, line: UInt, function: String) {
        _trimOutput = trimOutput
        if let identifier = identifier {
            _identifier = identifier
        }
        else {
            let trimmedFile: String
            if let lastIndex = file.lastIndexOf("/") {
                trimmedFile = file[file.index(after: lastIndex) ..< file.endIndex]
            }
            else {
                trimmedFile = file
            }
            _identifier = "\(trimmedFile):\(line) (\(function))"
        }
        _source = source
    }
    
    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Source.E {
        let sink = DebugSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
