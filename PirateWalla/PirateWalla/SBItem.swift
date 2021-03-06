//
//  SBItem.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/6/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation
import UIKit

class SBItem : SBSavedItem {
    init(dictionary: [String : AnyObject], bee: SwiftBee) {
        super.init(dictionary: dictionary, type: dictionary["item_type_id"]! as! String, bee: bee)
    }
    
    override var name : String {
        get {
            return data["name"] as? String ?? "Error"
        }
    }
    
    var setID : Int {
        get {
            return Int(data["set_id"] as? String ?? "-1") ?? -1
        }
    }
    
    var userID : Int {
        get {
            return Int(data["user_id"] as! String)!
        }
    }
}

class SBMarketItem : SBItemBase {
    var cost : Int {
        get {
            return Int(data["cost"] as? String ?? "0") ?? 0
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
            let enhanced = s.enhanceWithItemType(type)
            completion(error: nil, enhancedItem: enhanced)
        }
    }
    
    override var shortDescription : String {
        get {
            return "\(self.dynamicType) - type \(itemTypeID)"
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
    
    override var locked : Bool {
        get {
            if let status = data["status"] as? String {
                return status == "LOCKED"
            }
            return false
        }
    }
}

enum NumberClass : Int {
    case SD = 1, DD, TD, OneXXX, None
}

class SBItemBase : SBObject {
    var itemTypeID : Int {
        get {
            return Int(data["item_type_id"] as! String)!
        }
    }
    
    var numberClass : NumberClass {
        get {
            if number < 10 { return .SD }
            if number < 100 { return .DD }
            if number < 1000 { return .TD }
            if number < 2000 { return .OneXXX }
            return .None
        }
    }
    
    var name : String {
        get {
            return shortDescription
        }
    }
    
    var locked : Bool {
        get {
            return false
        }
    }
    
    var number : Int {
        get {
            return Int(data["number"] as? String ?? "-1") ?? -1
        }
    }
    
    var itemID : Int {
        get {
            return Int(data["item_id"] as! String)!
        }
    }
    
    override var id : Int {
        get {
            if let idString = data["id"] as? String {
                return Int(idString)!
            }
            return itemID
        }
    }
    
    func enhanceWithItemType(itemType : SBItemType) -> SBEnhancedMarketItem {
        var enhancedData = itemType.data
        for (key, value) in data {
            enhancedData[key] = value
        }
        return SBEnhancedMarketItem(dictionary: enhancedData, bee: bee)
    }
}