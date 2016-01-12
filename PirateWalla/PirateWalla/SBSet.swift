//
//  SBSet.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/11/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation

class SBSet : SBObject {
    class func errorSet(bee: SwiftBee) -> SBSet {
        return SBSet(dictionary: [ "name" : "Error" ], bee: bee)
    }
    
    func imageURL(size: Int) -> NSURL? {
        if let string = data["image_url_\(size)"] as? String {
            let secureString = string.stringByReplacingOccurrencesOfString("http:", withString: "https:")
            return NSURL(string: secureString)
        }
        return nil
    }
    
    var name : String {
        get {
            return data["name"] as? String ?? "Error"
        }
    }
}