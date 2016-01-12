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
    
    var setID : Int {
        get {
            return Int(data["set_id"] as? String ?? "-1") ?? -1
        }
    }
}

class SBMarketItem : SBItemBase {
    var cost : Int {
        get {
            return Int(data["cost"] as? String ?? "0") ?? 0
        }
    }
}

class SBEnhancedMarketItem : SBItem {
    var cost : Int {
        get {
            return Int(data["cost"] as? String ?? "0") ?? 0
        }
    }
}

class SBSavedItem : SBItemBase {
    init(dictionary: [String : AnyObject], type: String, bee: SwiftBee) {
        var appended = dictionary
        appended["item_type_id"] = type
        super.init(dictionary: appended, bee: bee)
    }
    
    var locked : Bool {
        get {
            if let status = data["status"] as? String {
                return status == "LOCKED"
            }
            return false
        }
    }
    
    func imageURL(size: Int) -> NSURL? {
        if let string = data["image_url_\(size)"] as? String {
            return NSURL(string: string)
        }
        return nil
    }
}

class SBItemBase : SBObject {
    var itemTypeID : Int {
        get {
            return Int(data["item_type_id"] as! String)!
        }
    }
    
    var number : Int {
        get {
            return Int(data["number"] as? String ?? "-1") ?? -1
        }
    }
    
    func enhance(completion : (error : NSError?, enhancedItem : SBEnhancedMarketItem?) -> Void) {
        bee.itemType(itemTypeID) { [weak self] (error, type) -> Void in
            guard let s = self else { return }
            if let error = error {
                completion(error: error, enhancedItem: nil)
                return
            }
            let type = type!
            var enhancedData = type.data
            for (key, value) in s.data {
                enhancedData[key] = value
            }
            completion(error: nil, enhancedItem: SBEnhancedMarketItem(dictionary: enhancedData, bee: s.bee))
        }
    }
}