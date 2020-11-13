//
//  Errors.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/28/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

let RxErrorDomain       = "RxErrorDomain"
let RxCompositeFailures = "RxCompositeFailures"

/// Generic Rx error codes.
public enum RxError
    : Swift.Error
    , CustomDebugStringConvertible {
    /// Unknown error occurred.
    case unknown
    /// Performing an action on disposed object.
    case disposed(object: AnyObject)
    /// Arithmetic overflow error.
    case overflow
    /// Argument out of range error.
    case argumentOutOfRange
    /// Sequence doesn't contain any elements.
    case noElements
    /// Sequence contains more than one element.
    case moreThanOneElement
    /// Timeout error.
    case timeout
}

extension RxError {
    /// A textual representation of `self`, suitable for debugging.
    public var debugDescription: String {
        switch self {
        case .unknown:
            return "Unknown error occurred."
        case .disposed(let object):
            return "Object `\(object)` was already disposed."
        case .overflow:
            return "Arithmetic overflow occurred."
        case .argumentOutOfRange:
            return "Argument out of range."
        case .noElements:
            return "Sequence doesn't contain any elements."
        case .moreThanOneElement:
            return "Sequence contains more than one element."
        case .timeout:
            return "Sequence timeout."
        }
    }
}
