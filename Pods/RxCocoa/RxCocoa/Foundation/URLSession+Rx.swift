//
//  URLSession+Rx.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 3/23/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import struct Foundation.URL
import struct Foundation.URLRequest
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.TimeInterval
import class Foundation.HTTPURLResponse
import class Foundation.URLSession
import class Foundation.URLResponse
import class Foundation.JSONSerialization
import class Foundation.NSError
import var Foundation.NSURLErrorCancelled
import var Foundation.NSURLErrorDomain

#if os(Linux)
    // don't know why
    import Foundation
#endif

#if !RX_NO_MODULE
import RxSwift
#endif

/// RxCocoa URL errors.
public enum RxCocoaURLError
    : Swift.Error {
    /// Unknown error occurred.
    case unknown
    /// Response is not NSHTTPURLResponse
    case nonHTTPResponse(response: URLResponse)
    /// Response is not successful. (not in `200 ..< 300` range)
    case httpRequestFailed(response: HTTPURLResponse, data: Data?)
    /// Deserialization error.
    case deserializationError(error: Swift.Error)
}

extension RxCocoaURLError
    : CustomDebugStringConvertible {
    /// A textual representation of `self`, suitable for debugging.
    public var debugDescription: String {
        switch self {
        case .unknown:
            return "Unknown error has occurred."
        case let .nonHTTPResponse(response):
            return "Response is not NSHTTPURLResponse `\(response)`."
        case let .httpRequestFailed(response, _):
            return "HTTP request failed with `\(response.statusCode)`."
        case let .deserializationError(error):
            return "Error during deserialization of the response: \(error)"
        }
    }
}

fileprivate func escapeTerminalString(_ value: String) -> String {
    return value.replacingOccurrences(of: "\"", with: "\\\"", options:[], range: nil)
}

fileprivate func convertURLRequestToCurlCommand(_ request: URLRequest) -> String {
    let method = request.httpMethod ?? "GET"
    var returnValue = "curl -X \(method) "

    if let httpBody = request.httpBody, request.httpMethod == "POST" {
        let maybeBody = String(data: httpBody, encoding: String.Encoding.utf8)
        if let body = maybeBody {
            returnValue += "-d \"\(escapeTerminalString(body))\" "
        }
    }

    for (key, value) in request.allHTTPHeaderFields ?? [:] {
        let escapedKey = escapeTerminalString(key as String)
        let escapedValue = escapeTerminalString(value as String)
        returnValue += "\n    -H \"\(escapedKey): \(escapedValue)\" "
    }

    let URLString = request.url?.absoluteString ?? "<unknown url>"

    returnValue += "\n\"\(escapeTerminalString(URLString))\""

    returnValue += " -i -v"

    return returnValue
}

fileprivate func convertResponseToString(_ response: URLResponse?, _ error: NSError?, _ interval: TimeInterval) -> String {
    let ms = Int(interval * 1000)

    if let response = response as? HTTPURLResponse {
        if 200 ..< 300 ~= response.statusCode {
            return "Success (\(ms)ms): Status \(response.statusCode)"
        }
        else {
            return "Failure (\(ms)ms): Status \(response.statusCode)"
        }
    }

    if let error = error {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            return "Cancelled (\(ms)ms)"
        }
        return "Failure (\(ms)ms): NSError > \(error)"
    }

    return "<Unhandled response from server>"
}

extension Reactive where Base: URLSession {
    /**
    Observable sequence of responses for URL request.
    
    Performing of request starts after observer is subscribed and not after invoking this method.
    
    **URL requests will be performed per subscribed observer.**
    
    Any error during fetching of the response will cause observed sequence to terminate with error.
    
    - parameter request: URL request.
    - returns: Observable sequence of URL responses.
    */
    public func response(request: URLRequest) -> Observable<(HTTPURLResponse, Data)> {
        return Observable.create { observer in

            // smart compiler should be able to optimize this out
            let d: Date?

            if Logging.URLRequests(request) {
                d = Date()
            }
            else {
               d = nil
            }

            let task = self.base.dataTask(with: request) { (data, response, error) in

                if Logging.URLRequests(request) {
                    let interval = Date().timeIntervalSince(d ?? Date())
                    print(convertURLRequestToCurlCommand(request))
                    print(convertResponseToString(response, error.map { $0 as NSError }, interval))
                }
                
                guard let response = response, let data = data else {
                    observer.on(.error(error ?? RxCocoaURLError.unknown))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    observer.on(.error(RxCocoaURLError.nonHTTPResponse(response: response)))
                    return
                }

                observer.on(.next(httpResponse, data))
                observer.on(.completed)
            }

            task.resume()

            return Disposables.create(with: task.cancel)
        }
    }

    /**
    Observable sequence of response data for URL request.
    
    Performing of request starts after observer is subscribed and not after invoking this method.
    
    **URL requests will be performed per subscribed observer.**
    
    Any error during fetching of the response will cause observed sequence to terminate with error.
    
    If response is not HTTP response with status code in the range of `200 ..< 300`, sequence
    will terminate with `(RxCocoaErrorDomain, RxCocoaError.NetworkError)`.
    
    - parameter request: URL request.
    - returns: Observable sequence of response data.
    */
    public func data(request: URLRequest) -> Observable<Data> {
        return response(request: request).map { (response, data) -> Data in
            if 200 ..< 300 ~= response.statusCode {
                return data
            }
            else {
                throw RxCocoaURLError.httpRequestFailed(response: response, data: data)
            }
        }
    }

    /**
    Observable sequence of response JSON for URL request.
    
    Performing of request starts after observer is subscribed and not after invoking this method.
    
    **URL requests will be performed per subscribed observer.**
    
    Any error during fetching of the response will cause observed sequence to terminate with error.
    
    If response is not HTTP response with status code in the range of `200 ..< 300`, sequence
    will terminate with `(RxCocoaErrorDomain, RxCocoaError.NetworkError)`.
    
    If there is an error during JSON deserialization observable sequence will fail with that error.
    
    - parameter request: URL request.
    - returns: Observable sequence of response JSON.
    */
    public func json(request: URLRequest, options: JSONSerialization.ReadingOptions = []) -> Observable<Any> {
        return data(request: request).map { (data) -> Any in
            do {
                return try JSONSerialization.jsonObject(with: data, options: options)
            } catch let error {
                throw RxCocoaURLError.deserializationError(error: error)
            }
        }
    }

    /**
    Observable sequence of response JSON for GET request with `URL`.
     
    Performing of request starts after observer is subscribed and not after invoking this method.
    
    **URL requests will be performed per subscribed observer.**
    
    Any error during fetching of the response will cause observed sequence to terminate with error.
    
    If response is not HTTP response with status code in the range of `200 ..< 300`, sequence
    will terminate with `(RxCocoaErrorDomain, RxCocoaError.NetworkError)`.
    
    If there is an error during JSON deserialization observable sequence will fail with that error.
    
    - parameter url: URL of `NSURLRequest` request.
    - returns: Observable sequence of response JSON.
    */
    public func json(url: Foundation.URL) -> Observable<Any> {
        return json(request: URLRequest(url: url))
    }
}

