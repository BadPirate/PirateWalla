//
//  SBItem.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/6/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation

class SBItem : SBSavedItem {
    init(dictionary: [String : AnyObject], bee: SwiftBee) {
        super.init(dictionary: dictionary, type: dictionary["item_type_id"]! as! String, bee: bee)
    }
    
    var name : String {
        get {
            return data["name"] as? String ?? "Error"
        }
    }
}

class SBSavedItem : SBObject {
    init(dictionary: [String : AnyObject], type: String, bee: SwiftBee) {
        var appended = dictionary
        appended["item_type_id"] = type
        super.init(dictionary: appended, bee: bee)
    }
    
    var itemTypeID : Int {
        get {
            return Int(data["item_type_id"] as! String)!
        }
    }
    
    func imageURL(size: Int) -> NSURL? {
        if let string = data["image_url_\(size)"] as? String {
            return NSURL(string: string)
        }
        return nil
    }
    
    var locked : Bool {
        get {
            if let status = data["status"] as? String {
                return status == "LOCKED"
            }
            return false
        }
    }
    
    var number : Int {
        get {
            return Int(data["number"] as? String ?? "-1") ?? -1
        }
    }
}