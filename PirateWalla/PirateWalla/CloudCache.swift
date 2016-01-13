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
            self?.enhance(baseItems, completion: completion)
        }
    }
    
    func cloudSwap(missing : Set<Int>, recordType : String, refresh : NSTimeInterval, objectInit : (dictionary : [ String : AnyObject], bee: SwiftBee) -> SBObject, retrieve : (identifier : Int, completion: (error : NSError?, object : SBObject?) -> Void) -> Void, cache : (object : SBObject) -> Void, completion : (error : NSError?) -> Void) {
        // Retrieve from Public Cloud and store any missing sets into memcache and then call again
        let predicate = NSPredicate(format:  "id in %@", missing)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        publicDatabase.performQuery(query, inZoneWithID: nil) { [weak self] (records, error) -> Void in
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
                        if -updated.timeIntervalSinceNow > refresh {
                            s.updateObject(object.id, record: record, recordType: recordType, retrieve: retrieve, cache: cache, completion: { _,_ -> Void in })
                        }
                    }
                    else {
                        s.updateObject(object.id, record: record, recordType: recordType, retrieve: retrieve, cache: cache, completion: { _,_ -> Void in })
                    }
                }
            }
            if let next = stillMissing.first {
                s.updateObject(next, record: nil, recordType: recordType,  retrieve: retrieve, cache: cache, completion: { [weak s] (error, set) -> Void in
                    guard let s = s else { return }
                    if set == nil {
                        print("Error updating set \(next) - Skipping")
                        cache(object: SBSet.errorSet(next, bee: s.bee))
                    }
                    completion(error: nil)
                    })
            }
            else
            {
                completion(error: nil)
            }
        }
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