//
//  ImageCache.swift
//  SharedImages
//
//  Created by Christopher Prince on 6/22/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

protocol CacheDataSource {
    associatedtype CachedData
    func keyFor(args:Any?) -> String
    func cacheDataFor(args:Any?) -> CachedData
    
    // If you have given a maxCost in the init method of `LRUCache`, then this method must return non-nil.
    func costFor(_ item: CachedData) -> Int?
    
    // 6/22/17; Getting compiler crash here if I use (_ item:CachedData) as parameter below. Very odd. Seems related the `#if DEBUG` usage.
#if DEBUG
    // Item was freshly cached on call to `get`
    func cachedItem(_ item:Any)
    
    // An item had to be evicted when `get` was called.
    func evictedItemFromCache(_ item:Any)
#endif
}

// Had some problems figuring out this generic technique: https://stackoverflow.com/questions/44714627/in-swift-how-do-i-use-an-associatedtype-in-a-generic-class-where-the-type-param#44714782
class LRUCache<DataSource:CacheDataSource> {
    typealias CacheData = DataSource.CachedData
    private var lruKeys = NSMutableOrderedSet()
    private var contents = [String: CacheData]()
    private var currentCost:Int64 = 0
    let maxItems:UInt!
    let maxCost:Int64?
    
    // Items are evicted from the cache when the max number of items is exceeded, or if the maxCost is given when the maxCost is exceeded.
    init?(maxItems:UInt, maxCost:Int64? = nil) {
        guard maxItems > 0 else {
            return nil
        }

        self.maxItems = maxItems
        self.maxCost = maxCost
    }
    
    // If data is cached, returns it. If data is not cached obtains, caches, and returns it.
    func getItem(from dataSource:DataSource, with args:Any? = nil) -> CacheData {
        let key = dataSource.keyFor(args: args)
        
        if let cachedData = contents[key] {
            // Remove key from lruKeys and put it at start-- gotta keep that LRU property.
            lruKeys.remove(key)
            lruKeys.insert(key, at: 0)
            return cachedData
        }
        
        // Check if we've exceed item limit in the cache.
        if lruKeys.count == Int(maxItems) {
            // Evict LRU key and data
            let lruKey = lruKeys.object(at: lruKeys.count-1) as! String
#if DEBUG
            dataSource.evictedItemFromCache(contents[lruKey]!)
#endif
            lruKeys.removeObject(at: lruKeys.count-1)
            contents[lruKey] = nil
            
            if maxCost != nil {
                let item = contents[lruKey]!
                currentCost -= Int64(dataSource.costFor(item)!)
            }
        }
        
        // Add new data in.
        lruKeys.insert(key, at: 0)
        contents[key] = dataSource.cacheDataFor(args: args)
        
        // We may have to evict due to cost.
        if maxCost != nil {
            let extraCost = dataSource.costFor(contents[key]!)!
            if Int64(extraCost) + currentCost > maxCost! {
                // Need to bring the cost of the current items down, in LRU manner.
                // Requires iteration.
            }
        }
        
#if DEBUG
        dataSource.cachedItem(contents[key]!)
#endif

        return contents[key]!
    }
}
