//
//  String+Rx.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 12/25/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension String {
    /// This is needed because on Linux Swift doesn't have `rangeOfString(..., options: .BackwardsSearch)`
    func lastIndexOf(_ character: Character) -> Index? {
        var index = endIndex
        while index > startIndex {
            index = self.index(before: index)
            if self[index] == character {
                return index
            }
        }

        return nil
    }
}
