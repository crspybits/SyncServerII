//
//  CacheTests.swift
//  SharedImagesTests
//
//  Created by Christopher Prince on 6/22/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SharedImages

class CacheTests: XCTestCase {
    var numberEvicted = 0
    var numberCached = 0
    var itemCached:Any?
    var evictedItem:Any?
    
    override func setUp() {
        super.setUp()
        numberEvicted = 0
        numberCached = 0
        itemCached = nil
        evictedItem = nil
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCacheCreationFailure() {
        let cache = LRUCache<CacheTests>(maxItems: 0)
        XCTAssert(cache == nil)
    }
    
    func testCacheFirstGet() {
        let cache = LRUCache<CacheTests>(maxItems: 1)
        XCTAssert(cache != nil)
        
        let valueToCache:Int = 132
        let result = cache?.getItem(from: self, with: valueToCache)
        XCTAssert(result == valueToCache)
        
        XCTAssert(numberCached == 1)
        XCTAssert(numberEvicted == 0)
    }
    
    func testCacheRepeatedGet() {
        let cache = LRUCache<CacheTests>(maxItems: 1)
        XCTAssert(cache != nil)
        
        let valueToCache:Int = 132
        var result = cache?.getItem(from: self, with: valueToCache)
        XCTAssert(result == valueToCache)
        XCTAssert(numberCached == 1)
        XCTAssert(numberEvicted == 0)
        
        result = cache?.getItem(from: self, with: valueToCache)
        XCTAssert(result == valueToCache)
        XCTAssert(numberCached == 1)
        XCTAssert(numberEvicted == 0)
    }
    
    func testCacheFirstEviction() {
        let cache = LRUCache<CacheTests>(maxItems: 1)
        XCTAssert(cache != nil)
        
        let firstValue:Int = 132
        var result = cache?.getItem(from: self, with: firstValue)
        XCTAssert(result == firstValue)
        XCTAssert(numberCached == 1)
        XCTAssert(numberEvicted == 0)
        
        let secondValue = 676
        result = cache?.getItem(from: self, with: secondValue)
        XCTAssert(result == secondValue)
        XCTAssert(numberCached == 2)
        XCTAssert(numberEvicted == 1)
        XCTAssert(evictedItem as! Int == firstValue)
    }
    
    func testCacheSecondGetNoEviction() {
        let cache = LRUCache<CacheTests>(maxItems: 2)
        XCTAssert(cache != nil)
        
        let firstValue:Int = 132
        var result = cache?.getItem(from: self, with: firstValue)
        XCTAssert(result == firstValue)
        XCTAssert(numberCached == 1)
        XCTAssert(numberEvicted == 0)
        
        let secondValue = 676
        result = cache?.getItem(from: self, with: secondValue)
        XCTAssert(result == secondValue)
        XCTAssert(numberCached == 2)
        XCTAssert(numberEvicted == 0)
    }

    func testCacheLRUPolicy() {
        let cache = LRUCache<CacheTests>(maxItems: 2)
        XCTAssert(cache != nil)
        
        let firstValue:Int = 132
        var result = cache?.getItem(from: self, with: firstValue)
        XCTAssert(result == firstValue)
        XCTAssert(numberCached == 1)
        XCTAssert(numberEvicted == 0)
        
        let secondValue = 676
        result = cache?.getItem(from: self, with: secondValue)
        XCTAssert(result == secondValue)
        XCTAssert(numberCached == 2)
        XCTAssert(numberEvicted == 0)
        
        let thirdValue = 22
        result = cache?.getItem(from: self, with: thirdValue)
        XCTAssert(result == thirdValue)
        XCTAssert(numberCached == 3)
        XCTAssert(numberEvicted == 1)
        XCTAssert(evictedItem as! Int == firstValue)
    }
    
    func testCacheLRUPolicyWithRecentGet() {
        let cache = LRUCache<CacheTests>(maxItems: 2)
        XCTAssert(cache != nil)
        
        let firstValue:Int = 132
        var result = cache?.getItem(from: self, with: firstValue)
        XCTAssert(result == firstValue)
        XCTAssert(numberCached == 1)
        XCTAssert(numberEvicted == 0)
        
        let secondValue = 676
        result = cache?.getItem(from: self, with: secondValue)
        XCTAssert(result == secondValue)
        XCTAssert(numberCached == 2)
        XCTAssert(numberEvicted == 0)
        
        result = cache?.getItem(from: self, with: firstValue)
        
        let thirdValue = 22
        result = cache?.getItem(from: self, with: thirdValue)
        XCTAssert(result == thirdValue)
        XCTAssert(numberCached == 3)
        XCTAssert(numberEvicted == 1)
        XCTAssert(evictedItem as! Int == secondValue)
    }
}

extension CacheTests : CacheDataSource {
    func keyFor(args:Any?) -> String {
        return "\(args as! Int)"
    }
    func cacheDataFor(args:Any?) -> Int {
        return args as! Int
    }
    
    func cachedItem(_ item:Any) {
        itemCached = item
        numberCached += 1
    }
    
    func evictedItemFromCache(_ item:Any) {
        evictedItem = item
        numberEvicted += 1
    }
    
    func costFor(_ item: Int) -> Int? {
        return nil
    }
}
