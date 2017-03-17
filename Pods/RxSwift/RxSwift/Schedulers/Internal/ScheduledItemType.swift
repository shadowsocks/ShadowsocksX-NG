//
//  ScheduledItemType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 11/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

protocol ScheduledItemType
    : Cancelable
    , InvocableType {
    func invoke()
}
