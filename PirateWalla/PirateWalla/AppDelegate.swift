//
//  AppDelegate.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/5/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit

enum ErrorCode : Int {
    case LocationRequired = 1, WallabeeError, FileSystemError, Cancelled
}

typealias EmptyCompletion = () -> Void

func delay(delay:Double, closure:()->()) {
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            Int64(delay * Double(NSEC_PER_SEC))
        ),
        dispatch_get_main_queue(), closure)
}

@UIApplicationMain

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
        
    class func handleError(error : NSError, completion : EmptyCompletion) {
        if !NSThread.isMainThread() {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.handleError(error, completion: completion)
            })
            return
        }
        
        let message = error.localizedDescription ?? "Unknown Error"
        switch error.domain {
        default:
            break
        }
        let alert = UIAlertController(title: "Error :(", message: message, preferredStyle: .Alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .Default, handler: { (_action) -> Void in
            completion()
        }))
        
        if let rootVC = (UIApplication.sharedApplication().delegate as? AppDelegate)?.window?.rootViewController {
            rootVC.presentViewController(alert, animated: true, completion: nil)
        }
    }
    
    class func handleInternalError(code : ErrorCode, description : String, completion : EmptyCompletion) {
        self.handleError(self.errorWithString(description, code: code), completion: completion)
    }
    
    class func errorWithString(description : String, code: ErrorCode) -> NSError {
        return NSError(domain: "piratewalla", code: code.rawValue, userInfo: [ NSLocalizedDescriptionKey : description ])
    }
}

