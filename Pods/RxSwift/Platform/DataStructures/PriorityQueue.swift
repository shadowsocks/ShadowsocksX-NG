//
//  PriorityQueue.swift
//  Platform
//
//  Created by Krunoslav Zaher on 12/27/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

struct PriorityQueue<Element> {
    private let _hasHigherPriority: (Element, Element) -> Bool
    private let _isEqual: (Element, Element) -> Bool

    fileprivate var _elements = [Element]()

    init(hasHigherPriority: @escaping (Element, Element) -> Bool, isEqual: @escaping (Element, Element) -> Bool) {
        _hasHigherPriority = hasHigherPriority
        _isEqual = isEqual
    }

    mutating func enqueue(_ element: Element) {
        _elements.append(element)
        bubbleToHigherPriority(_elements.count - 1)
    }

    func peek() -> Element? {
        return _elements.first
    }

    var isEmpty: Bool {
        return _elements.count == 0
    }

    mutating func dequeue() -> Element? {
        guard let front = peek() else {
            return nil
        }

        removeAt(0)

        return front
    }

    mutating func remove(_ element: Element) {
        for i in 0 ..< _elements.count {
            if _isEqual(_elements[i], element) {
                removeAt(i)
                return
            }
        }
    }

    private mutating func removeAt(_ index: Int) {
        let removingLast = index == _elements.count - 1
        if !removingLast {
            _elements.swapAt(index, _elements.count - 1)
        }

        _ = _elements.popLast()

        if !removingLast {
            bubbleToHigherPriority(index)
            bubbleToLowerPriority(index)
        }
    }

    private mutating func bubbleToHigherPriority(_ initialUnbalancedIndex: Int) {
        precondition(initialUnbalancedIndex >= 0)
        precondition(initialUnbalancedIndex < _elements.count)

        var unbalancedIndex = initialUnbalancedIndex

        while unbalancedIndex > 0 {
            let parentIndex = (unbalancedIndex - 1) / 2
            guard _hasHigherPriority(_elements[unbalancedIndex], _elements[parentIndex]) else { break }
            _elements.swapAt(unbalancedIndex, parentIndex)
            unbalancedIndex = parentIndex
        }
    }

    private mutating func bubbleToLowerPriority(_ initialUnbalancedIndex: Int) {
        precondition(initialUnbalancedIndex >= 0)
        precondition(initialUnbalancedIndex < _elements.count)

        var unbalancedIndex = initialUnbalancedIndex
        while true {
            let leftChildIndex = unbalancedIndex * 2 + 1
            let rightChildIndex = unbalancedIndex * 2 + 2

            var highestPriorityIndex = unbalancedIndex

            if leftChildIndex < _elements.count && _hasHigherPriority(_elements[leftChildIndex], _elements[highestPriorityIndex]) {
                highestPriorityIndex = leftChildIndex
            }

            if rightChildIndex < _elements.count && _hasHigherPriority(_elements[rightChildIndex], _elements[highestPriorityIndex]) {
                highestPriorityIndex = rightChildIndex
            }

            guard highestPriorityIndex != unbalancedIndex else { break }
            _elements.swapAt(highestPriorityIndex, unbalancedIndex)

            unbalancedIndex = highestPriorityIndex
        }
    }
}

extension PriorityQueue : CustomDebugStringConvertible {
    var debugDescription: String {
        return _elements.debugDescription
    }
}
