//
//  SwiftBee.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/5/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation
import CoreLocation
typealias emptyHandler = (cancelled : Bool) -> Void

class SwiftBee {
    let gateTime : NSTimeInterval = 0.25
    let session : NSURLSession
    var activeGates = Set<NSDate>()
    var pendingGates = [emptyHandler]()
    let gateLock : dispatch_queue_t
    
    init() {
        session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
        gateLock = dispatch_queue_create("BeeGateLock", nil)
    }
    
    func cancelAll() {
        dispatch_sync(gateLock) { [weak self] () -> Void in
            guard let s = self else { return }
            while let pending = s.pendingGates.first {
                let _ = s.pendingGates.removeFirst()
                pending(cancelled: true)
            }
        }
    }
    
    func setList(completion : (error : NSError?, sets : [SBSetBase]?) -> Void) {
        get("/sets") { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            var sets = [SBSetBase]()
            if let data = data, setDictionaries = data["sets"] as? [ [ String : AnyObject ] ] {
                for setDictionary in setDictionaries {
                    let set = SBSetBase(dictionary: setDictionary, bee: s)
                    sets.append(set)
                }
            }
            completion(error: error, sets: sets)
        }
    }
    
    func place(id : Int, completion : (error : NSError?, place : SBPlace?) -> Void) {
        get("/places/\(id)") { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            var place : SBPlace? = nil
            if let data = data {
                place = SBPlace(dictionary: data, bee: s)
            }
            completion(error: error, place: place)
        }
    }
    
    func user(identifier : String, completion : (error: NSError?, user: SBUser?) -> Void) {
        get("/users/\(identifier.URLEncodedString()!)") { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            var user : SBUser? = nil
            if let data = data {
                user = SBUser(dictionary: data, bee: s)
            }
            completion(error: error, user: user)
        }
    }
    
    func set(id : Int, completion : (error : NSError?, set : SBSet?) -> Void) {
        var path : String? = nil
        switch id {
        case 20:
            path = "/branded"
        case 25:
            path = "/uniqueitems"
        default:
            path = "/sets/\(id)"
        }
        get(path!) { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            if let error = error {
                print("Error retrieving set - \(id) - \(error)")
                let set = SBSet.errorSet(id, bee: s)
                completion(error: nil, set: set)
                return
            }
            guard var data = data else {
                completion(error: AppDelegate.errorWithString("No data in response", code: .WallabeeError), set: nil)
                return
            }
            data["id"] = "\(id)"
            let set = SBSet(dictionary: data, bee: s)
            completion(error: nil, set: set)
        }
    }
    
    func itemType(type : Int, completion : (error : NSError?, type : SBItemType?) -> Void) {
        get("/itemtypes/\(type)") { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            if let error = error {
                completion(error: error, type: nil)
                return
            }
            guard let data = data else {
                completion(error: AppDelegate.errorWithString("No data in response", code: .WallabeeError), type: nil)
                return
            }
            let itemType = SBItemType(dictionary: data, bee: s)
            completion(error: nil, type: itemType)
        }
    }
    
    func market(completion : (error: NSError?, items : [SBMarketItem]?) -> Void) {
        fetchMarket([SBMarketItem](), page: 1, completion: completion)
    }
    
    func fetchMarket(existing : [SBMarketItem], page : Int, completion : (error: NSError?, items : [SBMarketItem]?) -> Void) {
        var existingMutable = existing
        get("/market", parameters: [ "page" : "\(page)"]) { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            if let error = error {
                completion(error: error, items: nil)
                return
            }
            guard let data = data else {
                completion(error: AppDelegate.errorWithString("No data in response", code: .WallabeeError), items: nil)
                return
            }
            if let itemsDictionary = data["items"] as? [ [String : AnyObject] ] {
                for itemDictionary in itemsDictionary {
                    existingMutable.append(SBMarketItem(dictionary: itemDictionary, bee: s))
                }
            }
            if let paging = data["paging"] as? [ String : AnyObject ] {
                if let totalPages = paging["total_pages"] as? Int {
                    if totalPages > page {
                        s.fetchMarket(existingMutable, page: page+1, completion: completion)
                        return
                    }
                }
            }
            completion(error: nil, items: existingMutable)
        }
    }
    
    func nearby(location : CLLocation, completion : (error : NSError?, places : [ SBPlace ]?) -> Void)
    {
        get("/places", parameters: [ "lat" : String(location.coordinate.latitude), "lng" : String(location.coordinate.longitude) ]) { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            var places : [ SBPlace ]? = nil
            if let data = data, placesDictionary = data["places"] as? [ [ String : AnyObject ] ] {
                places = [ SBPlace ]()
                for placeDictionary in placesDictionary {
                    places!.append(SBPlace(dictionary: placeDictionary, bee: s))
                }
            }
            completion(error: error, places: places)
        }
    }
    
    func get(path : String, parameters : [ String : String ], completion : (error: NSError?, data : [ String : AnyObject ]?) -> Void) {
        let fullPath = path + String.queryStringFromParameters(parameters)!
        get(fullPath, completion: completion)
    }
    
    func get(path : String, completion : (error: NSError?, data : [ String : AnyObject ]?) -> Void) {
        gate { [weak self] (cancelled) -> Void in
            guard let s = self
                else { return }
            if (cancelled) {
                let error = AppDelegate.errorWithString("Cancelled", code: .Cancelled)
                completion(error: error, data: nil)
                return
            }
            print("GET - \(path)")
            let request = NSMutableURLRequest(URL: NSURL(string: "https://api.wallab.ee/\(path)")!)
            request.addValue("4f92cb2f-c9f4-4af6-b648-493b4d4902ab", forHTTPHeaderField: "X-WallaBee-API-Key")
            let task = s.session.dataTaskWithRequest(request, completionHandler: { (data : NSData?, response : NSURLResponse?, error : NSError?) -> Void in
                var result : [ String : AnyObject ]? = nil
                if let error = error {
                    completion(error: error, data: nil)
                    return
                }
                var e : NSError? = nil;
                if let data = data {
                    do {
                        let parsed = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        guard let tryResult = parsed as? [ String : AnyObject ] else {
                            let error = AppDelegate.errorWithString("Result wrong format, expecting [ String : AnyObject ] got - \(parsed.dynamicType)", code: .WallabeeError)
                            completion(error: error, data: nil)
                            return
                        }
                        result = tryResult
                    } catch let error as NSError {
                        print("JSON error: \(error) -- Data - \(data)")
                        e = error
                    }
                }
                if let r = result, errorString = r["error"] as? String {
                    result = nil
                    e = AppDelegate.errorWithString(errorString, code: .WallabeeError)
                }
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    completion(error: e, data: result)
                })
            })
            task.resume()
        }
    }
    
    func startGate(completion : emptyHandler) {
        // Expected to be protected in gate lock when called.
        let date = NSDate()
        activeGates.insert(date)
        delay(1, closure: { [weak self] () -> () in
            guard let s = self else { return }
            dispatch_sync(s.gateLock, { () -> Void in
                s.activeGates.remove(date)
                if let next = s.pendingGates.first {
                    let _ = s.pendingGates.removeFirst()
                    s.startGate(next)
                }
            })
            completion(cancelled: false)
            })
    }
    
    func gate(completion : emptyHandler) {
        dispatch_sync(gateLock) { [weak self] () -> Void in
            guard let s = self else { return }
            if s.activeGates.count < 5 {
                s.startGate(completion)
                return
            }
            s.pendingGates.append(completion)
        }
    }
    
    func synced(lock: AnyObject, closure: () -> ()) {
        objc_sync_enter(lock)
        closure()
        objc_sync_exit(lock)
    }
}

class SBObject : CustomStringConvertible, Hashable {
    let data : [ String : AnyObject ]
    let bee : SwiftBee
    init(dictionary : [ String : AnyObject ], bee: SwiftBee) {
        data = dictionary
        self.bee = bee
    }
    
    var error : String? {
        get {
            return data["error"] as? String
        }
    }
    
    var id : Int {
        get {
            if let idString = data["id"] as? String, id = Int(idString) {
                return id
            }
            else {
                print("Object has no ID Set - \(self)")
                return 0
            }
        }
    }
    
    var description : String {
        get {
            return data.description
        }
    }
    
    var hashValue: Int {
        get {
            return self.id + object_getClassName(self).hashValue
        }
    }
    
    var shortDescription : String {
        get {
            return "\(self.dynamicType) - \(self.id)"
        }
    }
}

func ==(lhs: SBObject, rhs: SBObject) -> Bool {
    return object_getClassName(lhs) == object_getClassName(rhs) && lhs.id == rhs.id
}

func ==(lhs: SBObject, rhs: Int) -> Bool {
    return lhs.id == rhs
}

extension String {
    func URLEncodedString() -> String? {
        let customAllowedSet : NSMutableCharacterSet =  NSCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as! NSMutableCharacterSet
        customAllowedSet.removeCharactersInString("&?")
        let escapedString = self.stringByAddingPercentEncodingWithAllowedCharacters(customAllowedSet)
        return escapedString
    }
    
    
    static func queryStringFromParameters(parameters: Dictionary<String,String>) -> String? {
        if (parameters.count == 0)
        {
            return nil
        }
        var queryString : String? = nil
        for (key, value) in parameters {
            if let encodedKey = key.URLEncodedString() {
                if let encodedValue = value.URLEncodedString() {
                    if queryString == nil
                    {
                        queryString = "?"
                    }
                    else
                    {
                        queryString! += "&"
                    }
                    queryString! += encodedKey + "=" + encodedValue
                }
            }
        }
        return queryString
    }
}