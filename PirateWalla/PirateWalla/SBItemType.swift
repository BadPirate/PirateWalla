//
//  SBItemType.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/11/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation
import UIKit

class SBItemType : SBObject {
    var typeID : Int {
        get {
            return Int(data["item_type_id"] as! String)!
        }
    }
    override var id : Int {
        get {
            return typeID
        }
    }
    
    var name : String {
        get {
            return data["name"] as? String ?? "Error"
        }
    }
    
    override var shortDescription : String {
        get {
            return super.shortDescription + " - \(name)"
        }
    }
    
    var mix : Set<Int> {
        get {
            var mix = Set<Int>()
            if let mixItems = data["mix"] as? [String] {
                for mixItem in mixItems {
                    mix.insert(Int(mixItem) ?? -1)
                }
            }
            return mix
        }
    }
}