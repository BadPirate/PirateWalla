//
//  SBPlace.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/6/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation
import CoreLocation

class SBPlace: SBObject {
    var itemCount : Int {
        get {
            return data["item_count"] as! Int
        }
    }
    
    func items(completion : (error : NSError?, items : [ SBItem ]?) -> Void) {
        if itemCount <= 0 {
            completion(error: nil, items: nil)
            return
        }
        bee.get("/places/\(self.id)/items") { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            var items : [ SBItem ]? = nil
            if let data = data, let itemsArray = data["items"] as? [ [ String : AnyObject ] ] {
                items = [SBItem]()
                for itemDictionary in itemsArray {
                    let item = SBItem(dictionary: itemDictionary, bee: s.bee)
                    items!.append(item)
                }
            }
            completion(error: error, items: items)
        }
    }
    
    var name : String {
        get {
            return data["name"] as? String ?? "Error"
        }
    }
    
    var location : CLLocationCoordinate2D {
        get {
            let lat = Double(data["lat"] as? String ?? "0") ?? 0
            let lng = Double(data["lng"] as? String ?? "0") ?? 0
            return CLLocationCoordinate2DMake(lat, lng)
        }
    }
    
    var radius : Double {
        get {
            return Double(data["radius"] as? String ?? "-1") ?? -1
        }
    }
}