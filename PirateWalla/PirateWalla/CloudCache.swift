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
        let cache = self.itemTypeCache as [Int : SBObject]
        objectsWithIdentifiers(missing, recordType: recordType, cache: cache) { (error, objects, cache) -> Void in
            if let cache = cache as? [Int : SBItemType] {
                var enhancedItems = Set<SBItem>()
                for baseItem in baseItems {
                    let enhancedItem = baseItem.enhanceWithItemType(cache[baseItem.itemTypeID]!)
                    enhancedItems.insert(enhancedItem)
                }
                self.itemTypeCache = cache
                completion(error: nil, enhancedItems)
                return
            }
            completion(error: error, nil)
        }
    }
    
    func objectsWithIdentifiers(identifiers: Set<Int>, recordType: String, cache : [ Int : SBObject ], completion : (error : NSError?, objects : Set<SBObject>?, updateCache: [Int : SBObject]?) -> Void)
    {
        var cache = cache
        var retrieved = Set<SBObject>()
        var missing = identifiers
        
        // Check the cache
        for identifier in identifiers {
            if let object = cache[identifier] {
                retrieved.insert(object)
                missing.remove(identifier)
            }
        }
        
        if missing.count == 0 {
            // Great, they were all cached!
            completion(error: nil, objects: retrieved, updateCache: cache)
            return
        }
        
        // Fooey, check the cloud
        publicQueryIdIn(missing, recordType: recordType) { [weak self] (records, error) -> Void in
            guard let s = self else { return }
            if let error = error {
                completion(error: error, objects: nil, updateCache: nil)
                return
            }
            
            var activities = 0
            
            var updatedRecords = Set<Int>()
            
            if let records = records {
                for record in records {
                    guard let asset = record["data"] as? CKAsset, dictionary = NSKeyedUnarchiver.unarchiveObjectWithFile(asset.fileURL.path!) as? [ String : AnyObject ] else { fatalError("Record data corrupted") }
                    var temp : SBObject?
                    
                    switch recordType {
                    case "Set":
                        temp = SBSet(dictionary: dictionary, bee: s.bee)
                    case "ItemType":
                        temp = SBItemType(dictionary: dictionary, bee: s.bee)
                    default:
                        fatalError("Unhandled record type objectsWithIdentifiers \(recordType)")
                    }
                    let object = temp!
                    cache[object.id] = object // Cache it for next time
                    let recordName = "\(object.dynamicType)-\(object.id)"
                    if recordName != record.recordID.recordName {
                        if !updatedRecords.contains(object.id) {
                            updatedRecords.insert(object.id)
                            print("Updating record name - \(record.recordID.recordName) != \(recordName)")
                            let updated = CKRecord(recordType: recordType, recordID: CKRecordID(recordName: recordName))
                            let updatedAsset = CKAsset(fileURL: (record["data"] as! CKAsset).fileURL)
                            updated["data"] = updatedAsset
                            updated["id"] = record["id"]
                            s.publicDatabase.saveRecord(updated, completionHandler: { (_,error) -> Void in
                                if let error = error {
                                    print("Error creating updated record \(recordName) - \(error)")
                                }
                            })
                        }
                        else
                        {
                            print("Deleting duplicate record - \(record.recordID.recordName)")
                        }
                        s.publicDatabase.deleteRecordWithID(record.recordID, completionHandler: { (_, error) -> Void in
                            if let error = error {
                                print("Error deleting updated record \(record.recordID.recordName) - \(error)")
                            }
                        })
                    }
                    missing.remove(object.id)
                    retrieved.insert(object)
                }
            }
            
            if missing.count == 0 {
                // We got them all from the cloud! Yay!
                completion(error: nil, objects: retrieved, updateCache: cache)
                return
            }
            
            // Okay, go and get them from Wallabee I guess
            let retrievalLock = dispatch_queue_create("Object Retrieval", nil)
            var cancel = false
            
            let handler = { [weak self] (error : NSError?, object: SBObject?) in
                guard let s = self else { return }
                dispatch_sync(retrievalLock, { () -> Void in
                    if cancel { return }
                    if let error = error {
                        cancel = true
                        completion(error: error, objects: nil, updateCache: nil)
                        return
                    }
                    let object = object!
                    retrieved.insert(object)
                    cache[object.id] = object
                    s.saveObject(object, recordType: recordType, completion: { (error) -> Void in
                        if let error = error {
                            print("Error saving \(object) - \(error)")
                            return
                        }
                    })
                    activities--
                    if activities == 0 {
                        completion(error: nil, objects: retrieved, updateCache: cache)
                    }
                })
            }
            
            activities++ // So that there isn't a race where completion can get called twice.
            for identifier in missing {
                // retrieve(identifier : Int, bee : SwiftBee, completion : (error : NSError?, object : SBObject?) -> Void
                switch recordType {
                case "Set":
                    dispatch_sync(retrievalLock, { () -> Void in
                        activities++
                    })
                    s.bee.set(identifier, completion: { (error, set) -> Void in
                        handler(error, set)
                    })
                case "ItemType":
                    dispatch_sync(retrievalLock, { () -> Void in
                        activities++
                    })
                    s.bee.itemType(identifier, completion: { (error, type) -> Void in
                        handler(error, type)
                    })
                default:
                    fatalError("Object retrival doesn't support \(recordType)")
                }
            }
            
            dispatch_sync(retrievalLock, { () -> Void in
                if activities == 0 {
                    completion(error: nil, objects: retrieved, updateCache: cache)
                }
            })
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
    
    func publicQueryIdIn(identifiers : Set<Int>, recordType : String, completion : ([CKRecord]?, NSError?) -> Void) {
        let queryResolutionLock = dispatch_queue_create("ID Query Lock", nil)
        
        var array = Array(identifiers)
        var result = [CKRecord]()
        var activities = 0
        var cancel = false
        
        let perRequest = 50
        let parts = Int(ceil(Float(array.count)/Float(perRequest)))
        
        for head in 0..<parts {
            let start = head*perRequest
            let end = min(array.count,start+perRequest)
            let partial = array[start..<end]
            let predicate = NSPredicate(format: "id in %@", Array(partial))
            let query = CKQuery(recordType: recordType, predicate: predicate)
            
            dispatch_sync(queryResolutionLock, { () -> Void in
                print("Beginning ID Query request \(start) -> \(end-1)")
                activities++
            })
            publicQuery(query, completionHandler: { (records, error) -> Void in
                dispatch_sync(queryResolutionLock, { () -> Void in
                    if cancel { return }
                    if let error = error {
                        completion(nil, error)
                        cancel = true
                        return
                    }
                    if let records = records {
                        print("Query for \(start) -> \(end-1) returned \(records.count) records")
                        result.appendContentsOf(records)
                    }
                    activities--
                    if activities == 0 {
                        print("Completed ID Query - \(result.count) records retrieved")
                        completion(result,nil)
                    }
                })
            })
        }
    }
    
    func cloudSwap(missing : Set<Int>, recordType : String, refresh : NSTimeInterval, objectInit : (dictionary : [ String : AnyObject], bee: SwiftBee) -> SBObject, retrieve : (identifier : Int, completion: (error : NSError?, object : SBObject?) -> Void) -> Void, cache : (object : SBObject) -> Void, completion : (error : NSError?) -> Void) {
        // Retrieve from Public Cloud and store any missing sets into memcache and then call again
        publicQueryIdIn(missing, recordType: recordType, completion:  { [weak self] (records, error) -> Void in
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
        let cache = setsCache as [Int : SBObject]
        objectsWithIdentifiers(setIdentifiers, recordType: "Set", cache: cache) { [weak self] (error, objects, cache) -> Void in
            guard let s = self else { return }
            var result : Set<SBSet>?
            if let objects = objects as? Set<SBSet> {
                result = objects
            }
            if let cache = cache as? [Int : SBSet] {
                s.setsCache = cache
            }
            completion(error: error, result)
        }
    }
    
    func saveObject(object : SBObject, recordType: String, completion: (error : NSError?) -> Void) {
        let path = temporaryFileURL()
        if NSKeyedArchiver.archiveRootObject(object.data, toFile: path.path!) {
            let recordName = "\(object.dynamicType)-\(object.id)"
            let record = CKRecord(recordType: recordType, recordID: CKRecordID(recordName: recordName))
            record["data"] = CKAsset(fileURL: path)
            record["id"] = object.id
            if object.id == 0 {
                print("Object expected to respond to id - \(object)")
                return
            }
            print("Updating record to cloud - \(object.shortDescription)")
            publicDatabase.saveRecord(record, completionHandler: { (_, error) -> Void in
                if let error = error {
                    print("Error saving record \(record) to cloud - \(error)")
                }
                completion(error: error)
            })
        }
        else
        {
            let error = AppDelegate.errorWithString("Unable to save cloudkit data file", code: .FileSystemError)
            completion(error: error)
            return
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
                s.saveObject(object, recordType: recordType, completion: { error in
                    completion(error: error, object: object)
                })
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