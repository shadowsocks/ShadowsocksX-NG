//
//  Decode.swift
//  RxSwift
//
//  Created by Shai Mishali on 24/07/2020.
//  Copyright © 2020 Krunoslav Zaher. All rights reserved.
//

import Foundation

public extension ObservableType where Element == Data {
  /// Attempt to decode the emitted `Data` using a provided decoder.
  ///
  /// - parameter type: A `Decodable`-conforming type to attempt to decode to
  /// - parameter decoder: A capable decoder, e.g. `JSONDecoder` or `PropertyListDecoder`
  ///
  /// - note: If using a custom decoder, it must conform to the `DataDecoder` protocol.
  ///
  /// - returns: An `Observable` of the decoded type
  func decode<Item: Decodable,
              Decoder: DataDecoder>(type: Item.Type,
                                    decoder: Decoder) -> Observable<Item> {
    map { try decoder.decode(type, from: $0) }
  }
}

/// Represents an entity capable of decoding raw `Data`
/// into a concrete `Decodable` type
public protocol DataDecoder {
  func decode<Item: Decodable>(_ type: Item.Type, from data: Data) throws -> Item
}

extension JSONDecoder: DataDecoder {}
extension PropertyListDecoder: DataDecoder {}
