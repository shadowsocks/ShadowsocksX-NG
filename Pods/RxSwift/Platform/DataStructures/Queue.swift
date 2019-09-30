//
//  Queue.swift
//  Platform
//
//  Created by Krunoslav Zaher on 3/21/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/**
Data structure that represents queue.

Complexity of `enqueue`, `dequeue` is O(1) when number of operations is
averaged over N operations.

Complexity of `peek` is O(1).
*/
struct Queue<T>: Sequence {
    /// Type of generator.
    typealias Generator = AnyIterator<T>

    private let _resizeFactor = 2
    
    private var _storage: ContiguousArray<T?>
    private var _count = 0
    private var _pushNextIndex = 0
    private let _initialCapacity: Int

    /**
    Creates new queue.
    
    - parameter capacity: Capacity of newly created queue.
    */
    init(capacity: Int) {
        _initialCapacity = capacity

        _storage = ContiguousArray<T?>(repeating: nil, count: capacity)
    }
    
    private var dequeueIndex: Int {
        let index = _pushNextIndex - count
        return index < 0 ? index + _storage.count : index
    }
    
    /// - returns: Is queue empty.
    var isEmpty: Bool {
        return count == 0
    }
    
    /// - returns: Number of elements inside queue.
    var count: Int {
        return _count
    }
    
    /// - returns: Element in front of a list of elements to `dequeue`.
    func peek() -> T {
        precondition(count > 0)
        
        return _storage[dequeueIndex]!
    }
    
    mutating private func resizeTo(_ size: Int) {
        var newStorage = ContiguousArray<T?>(repeating: nil, count: size)
        
        let count = _count
        
        let dequeueIndex = self.dequeueIndex
        let spaceToEndOfQueue = _storage.count - dequeueIndex
        
        // first batch is from dequeue index to end of array
        let countElementsInFirstBatch = Swift.min(count, spaceToEndOfQueue)
        // second batch is wrapped from start of array to end of queue
        let numberOfElementsInSecondBatch = count - countElementsInFirstBatch
        
        newStorage[0 ..< countElementsInFirstBatch] = _storage[dequeueIndex ..< (dequeueIndex + countElementsInFirstBatch)]
        newStorage[countElementsInFirstBatch ..< (countElementsInFirstBatch + numberOfElementsInSecondBatch)] = _storage[0 ..< numberOfElementsInSecondBatch]
        
        _count = count
        _pushNextIndex = count
        _storage = newStorage
    }
    
    /// Enqueues `element`.
    ///
    /// - parameter element: Element to enqueue.
    mutating func enqueue(_ element: T) {
        if count == _storage.count {
            resizeTo(Swift.max(_storage.count, 1) * _resizeFactor)
        }
        
        _storage[_pushNextIndex] = element
        _pushNextIndex += 1
        _count += 1
        
        if _pushNextIndex >= _storage.count {
            _pushNextIndex -= _storage.count
        }
    }
    
    private mutating func dequeueElementOnly() -> T {
        precondition(count > 0)
        
        let index = dequeueIndex

        defer {
            _storage[index] = nil
            _count -= 1
        }

        return _storage[index]!
    }

    /// Dequeues element or throws an exception in case queue is empty.
    ///
    /// - returns: Dequeued element.
    mutating func dequeue() -> T? {
        if self.count == 0 {
            return nil
        }

        defer {
            let downsizeLimit = _storage.count / (_resizeFactor * _resizeFactor)
            if _count < downsizeLimit && downsizeLimit >= _initialCapacity {
                resizeTo(_storage.count / _resizeFactor)
            }
        }

        return dequeueElementOnly()
    }
    
    /// - returns: Generator of contained elements.
    func makeIterator() -> AnyIterator<T> {
        var i = dequeueIndex
        var count = _count

        return AnyIterator {
            if count == 0 {
                return nil
            }

            defer {
                count -= 1
                i += 1
            }

            if i >= self._storage.count {
                i -= self._storage.count
            }

            return self._storage[i]
        }
    }
}
