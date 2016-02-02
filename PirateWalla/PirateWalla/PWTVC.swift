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
    var appeared = false
    var animateTableChanges = true
    let activityLock : dispatch_queue_t
    var activities = [String]()
    let updatedSections = NSMutableIndexSet()
    
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
    
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        let row = sections[indexPath.section].rows[indexPath.row]
        if row.hidden { return 0 }
        return tableView.rowHeight
    }
    
    var subActivityTotal : Int = 0 {
        didSet {
            updateProgress()
        }
    }
    
    var subActivityRemaining : Int = 0 {
        didSet {
            updateProgress()
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        navigationController?.toolbarHidden = true
        appeared = false
        super.viewWillDisappear(animated)
    }
    
    override func viewWillAppear(animated: Bool) {
        navigationController?.toolbarHidden = progressView.text != nil
        appeared = true
        super.viewWillAppear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        progressView.textAlignment = .Center
        progressView.adjustsFontSizeToFitWidth = true
        toolbarItems = [UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil),UIBarButtonItem(customView: progressView),UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)]
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
        if var progressString = activities.first {
            if subActivityTotal > 0 {
                progressString += " (\(subActivityTotal+1-subActivityRemaining)/\(subActivityTotal))"
            }
            if progressView.text != progressString {
                print(progressString)
                progressView.text = progressString
            }
            navigationController?.toolbarHidden = !appeared
        }
        else
        {
            if progressView.text != nil {
                progressView.text = nil
            }
            navigationController?.toolbarHidden = true
            didCompleteAllActivities()
        }
    }
    
    func didCompleteAllActivities() {
        
    }
    
    func updateSections() {
        if animateTableChanges {
            tableView.beginUpdates()
        }
        var sectionOn = 0
        for section in sections {
            dispatch_sync(section.pendingRowLock, { () -> Void in
                while section.pendingRows.count > 0 {
                    let index = NSIndexPath(forRow: section.rows.count, inSection: sectionOn)
                    if self.animateTableChanges {
                        self.tableView.insertRowsAtIndexPaths([index], withRowAnimation: .Automatic)
                    }
                    else
                    {
                        self.updatedSections.addIndex(sectionOn)
                    }
                    if section.rows.count == 0 {
                        // First row, show header
                        if self.animateTableChanges {
                            self.tableView.reloadSections(NSIndexSet(index: sectionOn), withRowAnimation: .Automatic)
                        }
                    }
                    section.rows.append(section.pendingRows.first!)
                    section.pendingRows.removeFirst()
                }
            })
            sectionOn++
        }
        if animateTableChanges {
            tableView.endUpdates()
        }
        if updatedSections.count > 0 {
            tableView.reloadSections(updatedSections, withRowAnimation: .Automatic)
            updatedSections.removeAllIndexes()
        }
    }
    
    func shouldUpdateSections(animated : Bool) {
        animateTableChanges = animated
        shouldUpdateSections()
    }
    
    func shouldUpdateSections()
    {
        if willUpdateSections { return }
        willUpdateSections = true
        dispatch_async(dispatch_get_main_queue()) { [weak self] () -> Void in
            guard let s = self else { return }
            s.updateSections()
            s.willUpdateSections = false
            s.animateTableChanges = true
        }
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return sections.count
    }
    
    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let sectionObject = sections[section]
        let firstRowSpace : CGFloat = section == 0 ? 8 : 0
        if sectionObject.rows.count > 0 {
            return 20 + firstRowSpace
        }
        else
        {
            return 1 + firstRowSpace
        }
    }
    
    override func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let sectionObject = sections[section]
        if sectionObject.rows.count > 0 {
            return 8
        }
        else
        {
            return 1
        }
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let sectionObject = sections[section]
        if sectionObject.rows.count > 0 {
            return sectionObject.title
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
    let title : String?
    let pendingRowLock : dispatch_queue_t
    
    var rows : [ PWRow ] = [PWRow]()
    var pendingRows : [ PWRow ] = [PWRow]()
    init(title : String?) {
        self.title = title
        self.pendingRowLock = dispatch_queue_create("PWTVC.\(title)", nil)
    }
    var hashValue: Int {
        get {
            return title?.hashValue ?? 0
        }
    }
    func addPendingRow(row : PWRow) {
        dispatch_sync(pendingRowLock) { () -> Void in
            self.pendingRows.append(row)
        }
    }
}

func ==(lhs: PWSection, rhs: PWSection) -> Bool {
    return lhs.title == rhs.title
}

class PWRow : NSObject {
    var reuse : String = "basic"
    var hidden = false
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