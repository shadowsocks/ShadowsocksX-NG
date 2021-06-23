//
//  PriorityQueue.swift
//  Platform
//
//  Created by Krunoslav Zaher on 12/27/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

struct PriorityQueue<Element> {
    private let hasHigherPriority: (Element, Element) -> Bool
    private let isEqual: (Element, Element) -> Bool

    private var elements = [Element]()

    init(hasHigherPriority: @escaping (Element, Element) -> Bool, isEqual: @escaping (Element, Element) -> Bool) {
        self.hasHigherPriority = hasHigherPriority
        self.isEqual = isEqual
    }

    mutating func enqueue(_ element: Element) {
        elements.append(element)
        bubbleToHigherPriority(elements.count - 1)
    }

    func peek() -> Element? {
        elements.first
    }

    var isEmpty: Bool {
        elements.count == 0
    }

    mutating func dequeue() -> Element? {
        guard let front = peek() else {
            return nil
        }

        removeAt(0)

        return front
    }

    mutating func remove(_ element: Element) {
        for i in 0 ..< elements.count {
            if self.isEqual(elements[i], element) {
                removeAt(i)
                return
            }
        }
    }

    private mutating func removeAt(_ index: Int) {
        let removingLast = index == elements.count - 1
        if !removingLast {
            elements.swapAt(index, elements.count - 1)
        }

        _ = elements.popLast()

        if !removingLast {
            bubbleToHigherPriority(index)
            bubbleToLowerPriority(index)
        }
    }

    private mutating func bubbleToHigherPriority(_ initialUnbalancedIndex: Int) {
        precondition(initialUnbalancedIndex >= 0)
        precondition(initialUnbalancedIndex < elements.count)

        var unbalancedIndex = initialUnbalancedIndex

        while unbalancedIndex > 0 {
            let parentIndex = (unbalancedIndex - 1) / 2
            guard self.hasHigherPriority(elements[unbalancedIndex], elements[parentIndex]) else { break }
            elements.swapAt(unbalancedIndex, parentIndex)
            unbalancedIndex = parentIndex
        }
    }

    private mutating func bubbleToLowerPriority(_ initialUnbalancedIndex: Int) {
        precondition(initialUnbalancedIndex >= 0)
        precondition(initialUnbalancedIndex < elements.count)

        var unbalancedIndex = initialUnbalancedIndex
        while true {
            let leftChildIndex = unbalancedIndex * 2 + 1
            let rightChildIndex = unbalancedIndex * 2 + 2

            var highestPriorityIndex = unbalancedIndex

            if leftChildIndex < elements.count && self.hasHigherPriority(elements[leftChildIndex], elements[highestPriorityIndex]) {
                highestPriorityIndex = leftChildIndex
            }

            if rightChildIndex < elements.count && self.hasHigherPriority(elements[rightChildIndex], elements[highestPriorityIndex]) {
                highestPriorityIndex = rightChildIndex
            }

            guard highestPriorityIndex != unbalancedIndex else { break }
            elements.swapAt(highestPriorityIndex, unbalancedIndex)

            unbalancedIndex = highestPriorityIndex
        }
    }
}

extension PriorityQueue : CustomDebugStringConvertible {
    var debugDescription: String {
        elements.debugDescription
    }
}
