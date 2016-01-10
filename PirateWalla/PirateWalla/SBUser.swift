//
//  SBUser.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/5/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation

class SBUser : SBObject {    
    var name : String {
        get {
            return data["name"] as? String ?? "Error"
        }
    }
    
    func savedItems(completion : (error : NSError?, savedItems : Set<SBSavedItem>?) -> Void) {
        bee.get("/users/\(self.id)/saveditems") { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            var savedItems : Set<SBSavedItem>? = nil
            if let data = data, savedItemsDictionary = data["saveditems"] as? [ String : [ String : AnyObject ] ] {
                savedItems = Set<SBSavedItem>()
                for (itemType, savedItemDictionary) in savedItemsDictionary {
                    let item = SBSavedItem(dictionary: savedItemDictionary, type: itemType, bee: s.bee)
                    savedItems!.insert(item)
                }
            }
            completion(error: error, savedItems: savedItems)
        }
    }
    
    func uniqueItems(completion : (error : NSError?, uniqueItems : Set<SBItem>?) -> Void) {
        bee.get("/users/\(self.id)/unique") { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            var uniqueItems : Set<SBItem>? = nil
            if let data = data, uniqueItemsArray = data["items"] as? [ [String : AnyObject] ] {
                uniqueItems = Set<SBItem>()
                for uniqueItemDictionary in uniqueItemsArray {
                    uniqueItems!.insert(SBItem(dictionary: uniqueItemDictionary, bee: s.bee))
                }
            }
            completion(error: error, uniqueItems: uniqueItems)
        }
    }
}