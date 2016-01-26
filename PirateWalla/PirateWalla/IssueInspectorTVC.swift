//
//  IssueInspectorTVC.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/24/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit

class IssueInspectorTVC : PWTVC {
    let bee = sharedBee
    var cancelled = false
    let savedSection = IIUserSection(title: "Saved")
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        sections = [savedSection]
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        reset()
    }

    deinit {
        bee.cancelAll()
    }
    
    func reset() {
        cancelled = false
        let alert = UIAlertController(title: "Issue Number", message: "Enter the issue number that you'd like to analyze", preferredStyle: .Alert)
        alert.addTextFieldWithConfigurationHandler { (textField) -> Void in
            textField.keyboardType = UIKeyboardType.NumberPad
            textField.placeholder = "Issue Number"
        }
        alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: { [weak self] (_) -> Void in
            guard let s = self else { return }
            if let text = alert.textFields![0].text, number = Int(text) {
                s.loadNumber(number)
            }
        }))
        presentViewController(alert, animated: true, completion: nil)
    }
    
    func loadNumber(number : Int)
    {
        let activity = "Getting Statistics"
        startedActivity(activity)
        bee.get("/items/status/\(number)") { [weak self] (error, data) -> Void in
            guard let s = self else { return }
            s.stoppedActivity(activity)
            if let error = error {
                AppDelegate.handleError(error, button: "Ok", title: "Error", completion: { () -> Void in })
                return
            }
            guard let status = data?["status"] as? [ String : AnyObject ] else {
                let error = AppDelegate.errorWithString("Invalid status format", code: .WallabeeError)
                AppDelegate.handleError(error, button: "OK", title: "Error", completion: { () -> Void in })
                return
            }
            let alert = UIAlertController(title: "Status - \(number)", message: "Saved - \(status["saved"])\nPouch - \(status["pouch"])\nMixed - \(status["mixed"])\nDropped - \(status["dropped"])\nMixing Pool - \(status["mixing_pool"])", preferredStyle: .Alert)
            alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
            s.presentViewController(alert, animated: true, completion: nil)
            let activity = "Getting Saved Stats"
            s.startedActivity(activity)
            s.getStatusDetail("saved", number: number, completion: { [weak s] (error, detail) -> Void in
                guard let s = s else { return }
                if let error = error {
                    AppDelegate.handleError(error, button: "OK", title: "Error", completion: nil)
                    return
                }
                if let saved = detail?["items"] as? [ Int ] {
                    dispatch_sync(s.activityLock, { () -> Void in
                        s.subActivityTotal = saved.count
                        s.subActivityRemaining = saved.count
                    })
                    s.parseSaved(saved, completion: { [weak s] (error) -> Void in
                        guard let s = s else { return }
                        s.stoppedActivity(activity)
                        if let error = error {
                            AppDelegate.handleError(error, button: "OK", title: "Error", completion: nil)
                            s.cancelled = true
                            s.bee.cancelAll()
                            return
                        }
                    })
                }
                else
                {
                    s.stoppedActivity(activity)
                }
            })
        }
    }
    
    func parseSaved(saved : [ Int ], completion : (error : NSError?) -> Void) {
        for itemID in saved {
            bee.item(itemID, completion: { [weak self] (error, item) -> Void in
                guard let s = self else { return }
                if s.cancelled { return }
                dispatch_sync(s.activityLock, { [weak s] () -> Void in
                    guard let s = s else { return }
                    s.subActivityRemaining--
                })
                if let error = error {
                    completion(error: error)
                    return
                }
                let item = item!
                dispatch_sync(s.savedSection.pendingRowLock, { [weak s] () -> Void in
                    let s = s!
                    s.savedSection.pendingItems.insert(item)
                    s.shouldUpdateSections()
                })
                var complete = false
                dispatch_sync(s.activityLock, { () -> Void in
                    complete = s.subActivityRemaining == 0
                })
                if complete {
                    completion(error: nil)
                }
            })
        }
    }
    
    func getStatusDetail(detail : String, number : Int, completion : (error : NSError?, detail : [ String : AnyObject ]?) -> Void) {
        bee.get("/items/status/\(number)/\(detail)", completion: completion)
    }
    
    override func updateSections() {
        var sectionOn = 0
        for section in sections {
            if let section = section as? IISection {
                section.updateSection(self.tableView, section: sectionOn)
            }
            sectionOn++
        }
        super.updateSections()
    }
}

class IISection : PWSection {
    func updateSection(tableView : UITableView, section : Int) { }
}


class IIUserSection : IISection {
    var pendingItems = Set<SBItem>()
    
    override func updateSection(tableView: UITableView, section : Int) {
        dispatch_sync(pendingRowLock) { () -> Void in
            for item in self.pendingItems {
                if item.userID == 0 { continue }
                var on = 0
                var marker = 0
                var markerOn = 0
                var found = false
                for row in self.rows {
                    let row = row as! IIUserRow
                    if row.userID == item.userID {
                        dispatch_sync(row.itemsLock, { () -> Void in
                            row.items.append(item)
                        })
                        if row.items.count > marker {
                            self.rows.removeAtIndex(on)
                            self.rows.insert(row, atIndex: markerOn)
                            let destination = NSIndexPath(forRow: markerOn, inSection: section)
                            tableView.moveRowAtIndexPath(NSIndexPath(forRow: on, inSection: section), toIndexPath: destination)
                            tableView.reloadRowsAtIndexPaths([destination], withRowAnimation: .None)
                        }
                        found = true
                        break
                    }
                    else
                    {
                        if row.items.count < marker || marker == 0 {
                            markerOn = on
                            marker = row.items.count
                        }
                    }
                    on++
                }
                if !found {
                    let row = IIUserRow(userID: item.userID, bee: item.bee, type: "saved")
                    dispatch_sync(row.itemsLock, { () -> Void in
                        row.items.append(item)
                    })
                    let indexPath = NSIndexPath(forRow: self.rows.count, inSection: section)
                    self.rows.insert(row, atIndex: self.rows.count)
                    if self.rows.count == 1 {
                        tableView.reloadSections(NSIndexSet(index: section), withRowAnimation: .None)
                    }
                    tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .None)
                }
            }
            self.pendingItems.removeAll()
        }
    }
}

class IIUserRow : ItemRow {
    let userID : Int
    
    var user : SBUser? {
        didSet {
            if let user = user, cell = cell as? ItemCell {
                loadImage()
                dispatch_async(dispatch_get_main_queue(), { [weak self, weak cell] () -> Void in
                    guard let s = self, cell = cell else { return }
                    if s.cell != cell { return }
                    cell.label!.text = user.name
                })
            }
        }
    }
    
    func loadImage() {
        guard let cell = cell as? ItemCell else { return }
        cell.setPlaceImage(user?.imageURL(Int(50*UIScreen.mainScreen().scale)))
    }
    
    init(userID : Int, bee : SwiftBee, type: String) {
        self.userID = userID
        super.init(items: [SBItem](), bee: bee)
        reuse = "saved"
        setup = { [weak self] (cell : UITableViewCell, _) in
            guard let s = self else { return }
            if let cell = cell as? ItemCell {
                cell.row = self
                if let user = s.user {
                    cell.label!.text = user.name
                }
                else
                {
                    cell.label!.text = "User ID - \(userID)"
                }
                s.loadImage()
                cell.detailLabel!.text = "\(s.items.count) item\(s.items.count != 1 ? "s" : "") \(type)"
            }
        }
        select = { (tableView : UITableView, indexPath) in
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://users/\(userID)")!)
        }
        bee.priorityMode = true
        bee.user("\(userID)") { [weak self] (error, user) -> Void in
            guard let s = self else { return }
            s.user = user
        }
        bee.priorityMode = false
    }
}

class SavedCell : ItemCell {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        maximumPercent = 0.35
    }
}