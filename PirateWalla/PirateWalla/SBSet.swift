//
//  SBSet.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/11/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation

class SBSet : SBSetBase {
    var itemTypes : [SBItemType] {
        get {
            if let itemDictionaries = data["items"] as? [[ String : AnyObject ]] {
                var items = [SBItemType]()
                for itemDictionary in itemDictionaries {
                    let item = SBItemType(dictionary: itemDictionary, bee: bee)
                    items.append(item)
                }
                return items
            }
            else
            {
                return [SBItemType]()
            }
        }
    }
}

class SBSetBase : SBObject {
    class func errorSet(identifier : Int, bee: SwiftBee) -> SBSet {
        print("Error set - \(identifier)")
        return SBSet(dictionary: [ "id" : "\(identifier)", "name" : "Error" ], bee: bee)
    }
    
    var name : String {
        get {
            if id == 25 {
                return "Unique Items"
            }
            if let name = data["name"] as? String {
                return name
            }
            else
            {
                print("Set has no name - \(id)")
                return "Error"
            }
        }
    }
    
    var setID : Int {
        if let idString = data["id"] as? String {
            return Int(idString)!
        }
        return Int(data["set_id"] as! String)!
    }
    
    override var id : Int {
        get {
            return setID
        }
    }
    
    override var shortDescription : String {
        get {
            return super.shortDescription + " - \(name)"
        }
    }
}