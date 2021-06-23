//
//  Utils.swift
//  RxRelay
//
//  Created by Shai Mishali on 09/04/2019.
//  Copyright © 2019 Krunoslav Zaher. All rights reserved.
//

import Foundation

func rxFatalErrorInDebug(_ lastMessage: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) {
    #if DEBUG
    fatalError(lastMessage(), file: file, line: line)
    #else
    print("\(file):\(line): \(lastMessage())")
    #endif
}
