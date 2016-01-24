//
//  PWTVC.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/23/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit

class PWTVC : UITableViewController {
    var sections = [PWSection]()
    let progressView  = UILabel(frame: CGRectMake(0,0,200,40))
    var willUpdateSections : Bool = false
    var willUpdateProgress : Bool = false
    let activityLock : dispatch_queue_t
    var activities = [String]()
    
    required init?(coder aDecoder: NSCoder) {
        activityLock = dispatch_queue_create("ActivityLock", nil)
        super.init(coder: aDecoder)
    }
    
    func startedActivity(activity : String) {
        dispatch_sync(activityLock) { () -> Void in
            self.activities.append(activity)
        }
        updateProgress()
    }
    
    func stoppedActivity(activity : String) {
        dispatch_sync(activityLock) { () -> Void in
            for on in 0..<self.activities.count {
                let someActivity = self.activities[on]
                if someActivity == activity {
                    self.activities.removeAtIndex(on)
                    break
                }
            }
        }
        updateProgress()
    }
    
    func updateProgress() {
        if !NSThread.isMainThread() {
            if willUpdateProgress { return }
            willUpdateProgress = true;
            dispatch_async(dispatch_get_main_queue(), { [weak self] () -> Void in
                self?.updateProgress()
                })
            return
        }
        willUpdateProgress = false
        if let progressString = activities.first {
            if progressView.text != progressString {
                progressView.text = progressString
            }
            navigationController!.toolbarHidden = false
        }
        else
        {
            if progressView.text != nil {
                progressView.text = nil
            }
            navigationController!.toolbarHidden = true
        }
    }
    
    func updateSections() {
        tableView.beginUpdates()
        var sectionOn = 0
        for section in sections {
            dispatch_sync(section.pendingRowLock, { () -> Void in
                while section.pendingRows.count > 0 {
                    let index = NSIndexPath(forRow: section.rows.count, inSection: sectionOn)
                    self.tableView.insertRowsAtIndexPaths([index], withRowAnimation: .Automatic)
                    if section.rows.count == 0 {
                        // First row, show header
                        self.tableView.reloadSections(NSIndexSet(index: sectionOn), withRowAnimation: .Automatic)
                    }
                    section.rows.append(section.pendingRows.first!)
                    section.pendingRows.removeFirst()
                }
            })
            sectionOn++
        }
        tableView.endUpdates()
    }
    
    func shouldUpdateSections() {
        if willUpdateSections { return }
        willUpdateSections = true
        dispatch_async(dispatch_get_main_queue()) { [weak self] () -> Void in
            guard let s = self else { return }
            s.updateSections()
            s.willUpdateSections = false
        }
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return sections.count
    }
    
    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = sections[section]
        if section.rows.count > 0 {
            return UITableViewAutomaticDimension
        }
        else
        {
            return 1
        }
    }
    
    override func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let section = sections[section]
        if section.rows.count > 0 {
            return UITableViewAutomaticDimension
        }
        else
        {
            return 1
        }
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section = sections[section]
        if section.rows.count > 0 {
            return section.title
        }
        else
        {
            return nil
        }
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let cell = tableView.dequeueReusableCellWithIdentifier(row.reuse)!
        row.setup(cell: cell, table: tableView)
        return cell
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let row = sections[indexPath.section].rows[indexPath.row]
        row.select(tableView: tableView, indexPath: indexPath)
    }
}

class PWSection : Hashable {
    let title : String
    let pendingRowLock : dispatch_queue_t
    
    var rows : [ PWRow ] = [PWRow]()
    var pendingRows : [ PWRow ] = [PWRow]()
    init(title : String) {
        self.title = title
        self.pendingRowLock = dispatch_queue_create("PWTVC.\(title)", nil)
    }
    var hashValue: Int {
        get {
            return title.hashValue
        }
    }
}

func ==(lhs: PWSection, rhs: PWSection) -> Bool {
    return lhs.title == rhs.title
}

class PWRow : NSObject {
    var reuse : String = "basic"
    var setup : (cell : UITableViewCell, table : UITableView) -> Void = { _,_ in }
    var select : (tableView : UITableView, indexPath : NSIndexPath) -> Void = { tableView, indexPath in
        tableView.deselectRowAtIndexPath(indexPath, animated: false)
    }
    weak var cell : PWCell?
}

class PWCell : UITableViewCell {
    var row : PWRow? {
        didSet {
            if let oldValue = oldValue {
                oldValue.cell = nil
            }
            if let row = row {
                row.cell = self
            }
        }
    }
    var enabled : Bool = true
}