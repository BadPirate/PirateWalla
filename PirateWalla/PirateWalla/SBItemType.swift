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
    
    func image(size: Int, completion : (error: NSError?, image : UIImage?) -> Void) {
        let scale = UIScreen.mainScreen().scale
        let size = Int(CGFloat(size) * scale)
        if let url = imageURL(size) {
            bee.session.dataTaskWithURL(url, completionHandler: { (data, _, error) -> Void in
                var image : UIImage? = nil
                if let data = data {
                    image = UIImage(data: data, scale: scale)
                }
                completion(error: error, image: image)
            }).resume()
        }
        else
        {
            completion(error: nil, image: nil)
        }
    }
    
    func imageURL(size: Int) -> NSURL? {
        if let string = data["image_url_\(size)"] as? String {
            return NSURL(string: string)
        }
        return nil
    }
}