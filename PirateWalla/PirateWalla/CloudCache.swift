//
//  CloudCache.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/12/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation
import CloudKit

class CloudCache {
    let publicDatabase = CKContainer.defaultContainer().publicCloudDatabase
    var setsCache = [ Int : SBSet ]()
    var itemTypeCache = [ Int : SBItemType ]()
    let setRecordType = "Set"
    let itemTypeRecordType = "ItemType"
    let bee : SwiftBee
    let setRefresh = NSTimeInterval(8*60*60) // 8 hours
    let itemTypeRefresh = NSTimeInterval(24*60*60) // 24 hours
    
    init(bee : SwiftBee) {
        self.bee = bee
    }
    
    func enhance(baseItems : Set<SBMarketItem>, completion : (error : NSError?, Set<SBItem>?) -> Void)
    {
        var missingItemTypes = Set<Int>()
        
        for baseItem in baseItems {
            if itemTypeCache[baseItem.itemTypeID] == nil {
                missingItemTypes.insert(baseItem.itemTypeID)
            }
        }
        if missingItemTypes.count == 0 {
            var enhancedItems = Set<SBItem>()
            for baseItem in baseItems {
                let enhancedItem = baseItem.enhanceWithItemType(itemTypeCache[baseItem.itemTypeID]!)
                enhancedItems.insert(enhancedItem)
            }
            completion(error: nil, enhancedItems)
            return
        }
        
        // missingSets, setRecordType, initializer
        
        let missing = missingItemTypes
        let recordType = itemTypeRecordType
        let refresh = itemTypeRefresh
        let objectInit = { (dictionary : [ String : AnyObject], bee: SwiftBee) -> SBObject in
            return SBItemType(dictionary: dictionary, bee: bee)
        }
        let cache = { (object : SBObject) -> Void in
            guard let itemType = object as? SBItemType else { return }
            self.itemTypeCache[itemType.id] = itemType
        }
        let retrieve = { [weak self] (identifier : Int, completion : (error : NSError?, SBObject?) -> Void) -> Void in
            self?.bee.itemType(identifier, completion: { (error, type) -> Void in
                completion(error: error, type)
            })
        }
        cloudSwap(missing, recordType: recordType, refresh: refresh, objectInit: objectInit, retrieve: retrieve, cache: cache) { [weak self] (error) -> Void in
            if let error = error {
                completion(error: error, nil)
                return
            }
            self?.enhance(baseItems, completion: completion)
        }
    }
    
    func publicQuery(query: CKQuery, completionHandler: ([CKRecord]?, NSError?) -> Void) {
        publicDatabase.performQuery(query, inZoneWithID: nil) { (record, error) -> Void in
            if let error = error {
                switch CKErrorCode(rawValue: error.code) ?? CKErrorCode.InternalError {
                case .RequestRateLimited:
                    let retryAfter = error.userInfo[CKErrorRetryAfterKey] as! Double
                    print("Error - publicQuery - rate limited, retry after delay - \(retryAfter)")
                    delay(retryAfter, closure: { [weak self] () -> () in
                        self?.publicQuery(query, completionHandler: completionHandler)
                        return
                    })
                default:
                    print("Error - publicQuery - unhandled code \(error.code) - \(error) for query - \(query)")
                }
            }
            completionHandler(record, error)
        }
    }
    
    func publicQueryIdIn(identifiers : Set<Int>, recordType : String, existing : [CKRecord]?, completion : ([CKRecord]?, NSError?) -> Void) {
        var array = Array(identifiers)
        var result = existing != nil ? existing! : [CKRecord]()
        
        let end : Int = min(array.count,50)
        let partial = array[0..<end]
        let predicate = NSPredicate(format: "id in %@", Array(partial))
        let query = CKQuery(recordType: recordType, predicate: predicate)
        print("Querying DB for \(partial.count) \(recordType) records")
        publicQuery(query, completionHandler: { [weak self] (records, error) -> Void in
            guard let s = self else { return }
            if let error = error {
                completion(nil, error)
                return
            }
            let records = records!
            print("Query returned \(records.count) results for \(recordType)")
            result.appendContentsOf(records)
            if array.count == end {
                completion(result,nil)
            }
            else
            {
                let remainder = Set(array[end..<array.count])
                s.publicQueryIdIn(remainder, recordType: recordType, existing: result, completion: completion)
            }
        })
    }
    
    func cloudSwap(missing : Set<Int>, recordType : String, refresh : NSTimeInterval, objectInit : (dictionary : [ String : AnyObject], bee: SwiftBee) -> SBObject, retrieve : (identifier : Int, completion: (error : NSError?, object : SBObject?) -> Void) -> Void, cache : (object : SBObject) -> Void, completion : (error : NSError?) -> Void) {
        // Retrieve from Public Cloud and store any missing sets into memcache and then call again
        publicQueryIdIn(missing, recordType: recordType, existing: nil, completion:  { [weak self] (records, error) -> Void in
            guard let s = self else { return }
            if let error = error {
                print("Error performing cloudkit query -  \(error)")
                completion(error: error)
                return
            }
            var stillMissing = missing
            for record in records! {
                if let asset = record["data"] as? CKAsset, data = NSKeyedUnarchiver.unarchiveObjectWithFile(asset.fileURL.path!) as? [ String : AnyObject ] {
                    let object = objectInit(dictionary: data, bee: s.bee)
                    stillMissing.remove(object.id)
                    cache(object: object)
                    if let updated = record.modificationDate {
                        var errorPresent = false
                        if let set = object as? SBSet {
                            if set.data["name"] == nil {
                                errorPresent = true
                            }
                        }
                        if -updated.timeIntervalSinceNow > refresh || errorPresent {
                            s.updateObject(object.id, record: record, recordType: recordType, retrieve: retrieve, cache: cache, completion: { _,_ -> Void in })
                        }
                    }
                    else {
                        s.updateObject(object.id, record: record, recordType: recordType, retrieve: retrieve, cache: cache, completion: { _,_ -> Void in })
                    }
                }
            }
            if stillMissing.count > 0 {
                s.updateObjects(stillMissing, recordType: recordType, retrieve: retrieve, cache: cache, iterate: { (object) ->Void in }, objects: nil, completion: { [weak self] (error, objects) -> Void in
                    self?.cloudSwap(missing, recordType: recordType, refresh: refresh, objectInit: objectInit, retrieve: retrieve, cache: cache, completion: completion)
                })
            }
            else
            {
                completion(error: nil)
            }
        })
    }
    
    func updateObjects(objectIdentifiers : Set<Int>, recordType: String, retrieve : (identifier : Int, completion: (error : NSError?, object : SBObject?) -> Void) -> Void, cache : (object : SBObject) -> Void, iterate : (object : SBObject) -> Void, objects : Set<SBObject>?, completion : (error : NSError?, objects : Set<SBObject>?) -> Void) {
        if objectIdentifiers.count == 0 {
            completion(error: nil, objects: nil)
            return
        }
        let next = objectIdentifiers.first!
        updateObject(next, record: nil, recordType: recordType,  retrieve: retrieve, cache: cache, completion: { [weak self] (error, object) -> Void in
            guard let s = self else { return }
            if let error = error {
                completion(error: error, objects: nil)
                return
            }
            let object = object!
            iterate(object: object)
            var existing = objects == nil ? Set<SBObject>() : objects!
            existing.insert(object)
            var mutableIdentifiers = objectIdentifiers
            mutableIdentifiers.remove(next)
            s.updateObjects(mutableIdentifiers, recordType: recordType, retrieve: retrieve, cache: cache, iterate: iterate, objects: existing, completion: completion)
        })
    }
    
    func sets(setIdentifiers : Set<Int>, completion : (error : NSError?, Set<SBSet>?) -> Void)
    {
        var missingSets = Set<Int>()
        var sets = Set<SBSet>()
        
        // Check memory cache
        for setIdentifier in setIdentifiers {
            if let set = setsCache[setIdentifier] {
                sets.insert(set)
            }
            else
            {
                missingSets.insert(setIdentifier)
            }
        }
        if missingSets.count == 0 {
            completion(error: nil, sets)
            return
        }
        
        let objectInit = { (dictionary : [ String : AnyObject], bee: SwiftBee) -> SBObject in
            return SBSet(dictionary: dictionary, bee: bee)
        }
        let cache = { (object : SBObject) -> Void in
            guard let set = object as? SBSet else { return }
            self.setsCache[set.id] = set
        }
        let retrieve = { [weak self] (identifier : Int, completion : (error : NSError?, SBObject?) -> Void) -> Void in
            self?.bee.set(identifier, completion: { (error, set) -> Void in
                completion(error: error, set)
            })
        }
        cloudSwap(missingSets, recordType: setRecordType, refresh: setRefresh, objectInit: objectInit, retrieve: retrieve, cache: cache) { [weak self] (error) -> Void in
            self?.sets(setIdentifiers, completion: completion)
        }
    }
    
    func updateObject(objectIdentifier : Int, record : CKRecord?, recordType: String, retrieve : (identifier : Int, completion: (error : NSError?, object : SBObject?) -> Void) -> Void, cache : (object : SBObject) -> Void, completion : (error : NSError?, object : SBObject?) -> Void)
    {
        print("Updating object - \(recordType) - \(objectIdentifier)")
        retrieve(identifier: objectIdentifier, completion: { [weak self] (error, object) -> Void in
            guard let s = self else { return }
            if let error = error {
                completion(error: error, object: nil)
                return
            }
            if let object = object {
                cache(object: object)
                let path = s.temporaryFileURL()
                if NSKeyedArchiver.archiveRootObject(object.data, toFile: path.path!) {
                    let record = record != nil ? record! : CKRecord(recordType: recordType)
                    record["data"] = CKAsset(fileURL: path)
                    record["id"] = object.id
                    if object.id == 0 {
                        print("Object expected to respond to id - \(object)")
                        return
                    }
                    print("Updating record to cloud - \(object.shortDescription)")
                    s.publicDatabase.saveRecord(record, completionHandler: { (_, error) -> Void in
                        if let error = error {
                            print("Error saving record \(record) to cloud - \(error)")
                        }
                    })
                }
                else
                {
                    let error = AppDelegate.errorWithString("Unable to save cloudkit data file", code: .FileSystemError)
                    completion(error: error, object: nil)
                    return
                }
                completion(error: nil, object: object)
            }
            else
            {
                completion(error: AppDelegate.errorWithString("No set returned", code: .WallabeeError), object: nil)
            }
        })
    }
    
    func temporaryFileURL() -> NSURL {
        let directory = NSTemporaryDirectory()
        let fileName = NSUUID().UUIDString
        return NSURL.fileURLWithPathComponents([directory, fileName])!
    }
}