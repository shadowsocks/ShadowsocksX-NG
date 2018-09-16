//
//  SwiftSupport.swift
//  RxSwift
//
//  Created by Volodymyr  Gorbenko on 3/6/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

import Foundation

#if swift(>=4.0)
    typealias IntMax = Int64
    public typealias RxAbstractInteger = FixedWidthInteger
    
    extension SignedInteger {
        func toIntMax() -> IntMax {
            return IntMax(self)
        }
    }
#else
    public typealias RxAbstractInteger = SignedInteger
  
    extension Array {
        public mutating func swapAt(_ i: Int, _ j: Int) {
            swap(&self[i], &self[j])
        }
    }
  
#endif
