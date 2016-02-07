//
//  IssueInspectorTVC.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/24/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit
import CloudKit

class IssueInspectorTVC : PWTVC {
    let bee = sharedBee
    let cloud = CloudCache(bee: sharedBee)
    var cancelled = false
    var statusAlerted = false, savedParsed = false, userAdded = false
    var users = [ Int : SBUser ]()
    let savedSection = IIUserSection(title: "Saved")
    var finalStats : [String:AnyObject]?
    var record : CKRecord?
    var number : Int = -1
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        savedSection.inspector = self
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
        statusAlerted = false
        savedParsed = false
        
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
        self.number = number
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.navigationItem.title = "\(number)"
        }
        let recordID = CKRecordID(recordName: "IssueInspector-\(number)")
        let activity = "Retrieving Cloud Data"
        startedActivity(activity)
        cloud.publicDatabase.fetchRecordWithID(recordID) { [weak self] (record, error) -> Void in
            guard let s = self else { return }
            s.stoppedActivity(activity)
            if let error = error {
                switch error.code {
                case 11:
                    break
                default:
                    print("Error code - \(error.code)")
                    AppDelegate.handleError(error, button: "OK", title: "Error", completion: nil)
                    return
                }
            }
            dispatch_async(dispatch_get_main_queue(), { [weak s] () -> Void in
                guard let s = s else { return }
                if let record = record, modDate = record.modificationDate {
                    if -modDate.timeIntervalSinceNow > s.cloud.issueInspectorRefresh {
                        print("Timed out issue data - \(number)")
                        s.updateRecordData(record, data: [String:AnyObject](), number: number)
                    }
                    else
                    {
                        s.updateRecord(record, number: number)
                    }
                }
                else
                {
                    s.updateRecord(CKRecord(recordType: "NumberStatus", recordID: recordID), number: number)
                }
            })
        }
    }
    
    func updateRecord(record : CKRecord, number : Int) {
        self.record = record
        var stats = [ String : AnyObject ]()
        if let data = record["data"] as? CKAsset, path = data.fileURL.path, retrieved = NSKeyedUnarchiver.unarchiveObjectWithFile(path) as? [ String : AnyObject ] {
            stats = retrieved
        }
        
        // Status
        if let status = stats["status"] as? [ String : AnyObject ] {
            if !statusAlerted {
                statusAlerted = true
                let alert = UIAlertController(title: "Status - \(number)", message: "Saved - \(status["saved"])\nPouch - \(status["pouch"])\nMixed - \(status["mixed"])\nDropped - \(status["dropped"])\nMixing Pool - \(status["mixing_pool"])", preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                presentViewController(alert, animated: true, completion: nil)
                if let existingUsers = stats["users"] as? [ [String:AnyObject] ] {
                    for userDictionary in existingUsers {
                        let user = SBUser(dictionary: userDictionary, bee: bee)
                        users[user.id] = user
                    }
                }
            }
        }
        else
        {
            getStatus(record, existing: stats, number: number)
            return
        }
        
        // Status Saved
        if !savedParsed {
            savedParsed = true
            if let saved = stats["saved"] as? [ [ String : AnyObject ] ] {
                dispatch_sync(savedSection.pendingRowLock, { [weak self] () -> Void in
                    guard let s = self else { return }
                    for dictionary in saved {
                        s.savedSection.pendingItems.insert(SBItem(dictionary: dictionary, bee: s.bee))
                    }
                    s.shouldUpdateSections(false)
                })
            }
            else {
                getSavedStatus(record, number: number, existing: stats)
                return
            }
        }
        
        // Complete
        finalStats = stats
    }
    
    func updateRecordData(record : CKRecord, data : [ String : AnyObject ], number : Int)
    {
        let tempURL = cloud.temporaryFileURL()
        var data = data
        if userAdded {
            var userDictionaries = [ [String:AnyObject] ]()
            users.forEach({ (_,user) -> () in
                userDictionaries.append(user.data)
            })
            data["users"] = userDictionaries
        }
        NSKeyedArchiver.archiveRootObject(data, toFile: tempURL.path!)
        record["data"] = CKAsset(fileURL: tempURL)
        cloud.publicDatabase.saveRecord(record) { (_, error) -> Void in
            if let error = error {
                print("Error updating insector data - \(error)")
            }
        }
        updateRecord(record, number: number)
    }
    
    func getStatus(record : CKRecord, existing : [String : AnyObject], number : Int) {
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
            var existing = existing
            existing["status"] = status
            s.updateRecordData(record, data: existing, number: number)
        }
    }
    
    func getSavedStatus(record : CKRecord, number : Int, existing : [ String : AnyObject ]) {
        let activity = "Getting Saved Stats"
        startedActivity(activity)
        getStatusDetail("saved", number: number, completion: { [weak self] (error, detail) -> Void in
            guard let s = self else { return }
            if let error = error {
                AppDelegate.handleError(error, button: "OK", title: "Error", completion: nil)
                s.stoppedActivity(activity)
                return
            }
            if let saved = detail?["items"] as? [ Int ] {
                s.startedSubActivities(saved.count)
                s.parseSaved(saved, completion: { [weak s] (error) -> Void in
                    guard let s = s else { return }
                    s.stoppedActivity(activity)
                    if let error = error {
                        AppDelegate.handleError(error, button: "OK", title: "Error", completion: nil)
                        s.cancelled = true
                        s.bee.cancelAll()
                        return
                    }
                    var existing = existing
                    var dictionaries = [ [ String : AnyObject ] ]()
                    s.savedSection.items.forEach({ (item : SBItem) -> () in
                        dictionaries.append(item.data)
                    })
                    existing["saved"] = dictionaries
                    s.updateRecordData(record, data: existing, number: number)
                })
            }
            else
            {
                s.stoppedActivity(activity)
            }
        })
    }
    
    override func didCompleteAllActivities() {
        super.didCompleteAllActivities()
        guard let finalStats = finalStats, record = record else { return }
        if userAdded {
            updateRecordData(record, data: finalStats, number: number)
        }
    }

    func parseSaved(saved : [ Int ], completion : (error : NSError?) -> Void) {
        for itemID in saved {
            bee.item(itemID, completion: { [weak self] (error, item) -> Void in
                guard let s = self else { return }
                if s.cancelled { return }
                s.stoppedSubActivity()
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
                    complete = (s.subActivityRemaining == 0 || (s.subActivityRemaining == 1 && s.activities.count == 2))
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
                section.updateSection(self.tableView, section: sectionOn, animate: self.animateTableChanges, updatedSections: self.updatedSections)
            }
            sectionOn++
        }
        super.updateSections()
    }
}

class IISection : PWSection {
    weak var inspector : IssueInspectorTVC? = nil
    func updateSection(tableView : UITableView, section : Int, animate : Bool, updatedSections : NSMutableIndexSet) { }
}


class IIUserSection : IISection {
    var pendingItems = Set<SBItem>()
    var sortedItems = Set<SBItem>()
    var items : Set<SBItem> {
        get {
            return pendingItems.union(sortedItems)
        }
    }
    override func updateSection(tableView: UITableView, section : Int, animate : Bool, updatedSections : NSMutableIndexSet) {
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
                            if animate {
                                tableView.moveRowAtIndexPath(NSIndexPath(forRow: on, inSection: section), toIndexPath: destination)
                                tableView.reloadRowsAtIndexPaths([destination], withRowAnimation: .None)
                            }
                            else {
                                updatedSections.addIndex(section)
                            }

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
                    let row =  IIUserRow(userID: item.userID, bee: item.bee, type: "saved", inspector: self.inspector)
                    row.items.append(item)
                    let indexPath = NSIndexPath(forRow: self.rows.count, inSection: section)
                    self.rows.insert(row, atIndex: self.rows.count)
                    if animate {
                        if self.rows.count == 1 {
                            tableView.reloadSections(NSIndexSet(index: section), withRowAnimation: .None)
                        }
                        else
                        {
                            tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .None)
                        }
                    }
                    else
                    {
                        updatedSections.addIndex(section)
                    }
                }
            }
            self.sortedItems.unionInPlace(self.pendingItems)
            self.pendingItems.removeAll()
        }
    }
}

class IIUserRow : ItemRow {
    let userID : Int
    weak var inspector : IssueInspectorTVC?
    
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
    
    init(userID : Int, bee : SwiftBee, type: String, inspector : IssueInspectorTVC?) {
        self.userID = userID
        self.inspector = inspector
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
                    cell.label!.text = "User ID - \(s.userID)"
                }
                s.loadImage()
                cell.detailLabel!.text = "\(s.items.count) item\(s.items.count != 1 ? "s" : "") \(type)"
            }
        }
        select = { (tableView : UITableView, indexPath) in
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://users/\(userID)")!)
        }
        
        if let inspector = inspector, aUser = inspector.users[userID] {
            user = aUser
        }
        else
        {
            let activity = "Getting User Info"
            if let inspector = inspector {
                inspector.startedActivity(activity)
                inspector.startedSubActivities(1)
            }
            bee.priorityMode = true
            bee.user("\(userID)") { [weak self] (error, user) -> Void in
                guard let s = self else { return }
                if let inspector = s.inspector {
                    inspector.stoppedActivity(activity)
                    inspector.stoppedSubActivity()
                    if let user = user {
                        inspector.userAdded = true
                        inspector.users[user.id] = user
                    }
                }
                s.user = user
            }
            bee.priorityMode = false
        }
    }
}

class SavedCell : ItemCell {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        maximumPercent = 0.35
    }
}