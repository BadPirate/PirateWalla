//
//  ActionList.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/6/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation



class ActionTVC : UITableViewController, CLLocationManagerDelegate {
    lazy var bee : SwiftBee = SwiftBee()
    let locationManager = CLLocationManager()
    let progressView  = UIProgressView(progressViewStyle: .Bar)
    
    // Sections
    let sections : [ActionSection]
    let missingSection : ActionSection
    let improveSection : ActionSection
    
    var willUpdateSections : Bool = false
    var willUpdateProgress : Bool = false
    var finishedActivities : Int = 0
    var totalActivities : Int = 0
    
    // State Variables
    var user : SBUser?
    var nearby : [ SBPlace ]?
    var savedItems : [ Int : SBSavedItem ]?
    var refreshing = false
    
    required init?(coder aDecoder: NSCoder) {
        missingSection = ActionSection(title: "Missing Items")
        improveSection = ActionSection(title: "Improved Items")
        sections = [missingSection, improveSection]
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        self.navigationItem.title = "Log in"
        locationManager.delegate = self
        if let navigationController = navigationController {
            navigationController.toolbarHidden = false
        }
        toolbarItems = [UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil),UIBarButtonItem(customView: progressView),UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)]
        login()
        getNearby()
    }
    
    func startedActivity() {
        totalActivities++
        updateProgress()
    }
    
    func stoppedActivity() {
        finishedActivities++
        if finishedActivities == totalActivities {
            finishedActivities = 0
            totalActivities = 0
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
        progressView.progress = totalActivities == 0 ? Float(0) : Float(finishedActivities) / Float(totalActivities)
    }
    
    @IBAction func reload() {
        clearRows()
        nearby = nil
        savedItems = nil
        refreshing = false
        getNearby()
        getSavedItems()
    }
    
    
    
    func login() {
        if let id = NSUserDefaults.standardUserDefaults().stringForKey("id")
        {
            startedActivity()
            bee.user(id) { [weak self] (error, user) -> Void in
                guard let s = self else { return }
                s.stoppedActivity()
                if let error = error {
                    AppDelegate.handleError(error, completion: { () -> Void in
                        NSUserDefaults.standardUserDefaults().removeObjectForKey("id")
                        NSUserDefaults.standardUserDefaults().synchronize()
                        s.login()
                    })
                    return
                }
                let user = user!
                if user.id != Int(id) {
                    NSUserDefaults.standardUserDefaults().setObject("\(user.id)", forKey: "id")
                    NSUserDefaults.standardUserDefaults().synchronize()
                }
                s.didLogin(user)
            }
            return
        }
        
        let alert = UIAlertController(title: "Wallab.ee User", message: nil, preferredStyle: .Alert)
        alert.addTextFieldWithConfigurationHandler { (textField) -> Void in
            textField.placeholder = "Wallabee user name"
        }
        alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: { (action) -> Void in
            NSUserDefaults.standardUserDefaults().setObject(alert.textFields![0].text, forKey: "id")
            NSUserDefaults.standardUserDefaults().synchronize()
            self.login()
        }))
        presentViewController(alert, animated: true, completion: nil)
    }
    
    func locationRequired() {
        AppDelegate.handleInternalError(.LocationRequired, description: "Location required to use PirateWalla.  Please enable in settings.") { [weak self] () -> Void in
            guard let s = self else { return }
            s.locationManager.startUpdatingLocation()
        }
    }
    
    func getNearby() {
        switch CLLocationManager.authorizationStatus() {
        case .AuthorizedAlways:
            break;
        case .AuthorizedWhenInUse:
            break;
        case .Denied:
            locationRequired()
            return
        case .NotDetermined:
            locationManager.requestAlwaysAuthorization()
            return
        case .Restricted:
            locationRequired()
            return
        }
        
        locationManager.startUpdatingLocation()
    }
    
    func clearRows()
    {
        var rowsRemoved = false
        for section in sections {
            if section.rows.count > 0 {
                section.rows.removeAll()
                rowsRemoved = true
            }
            section.pendingRows.removeAll()
        }
        if rowsRemoved {
            tableView.reloadData()
        }
    }
    
    func refreshList() {
        if !NSThread.isMainThread() {
            dispatch_sync(dispatch_get_main_queue(), { [weak self] () -> Void in
                guard let s = self else { return }
                s.refreshList()
            })
            return
        }
        
        guard let user = user, nearby = nearby, savedItems = savedItems
            else { return }
        
        if refreshing { return }
        refreshing = true
        
        clearRows()

        print("Refreshing list User - \(user.id) - Nearby \(nearby.count) - Saved Items \(savedItems.count)")
        for place in nearby {
            startedActivity()
            place.items({ [weak self] (error, items) -> Void in
                self?.stoppedActivity()
                guard let s = self, let snb = s.nearby else { return }
                if snb != nearby { return }
                if let error = error {
                    AppDelegate.handleError(error, completion: { () -> Void in })
                    return
                }
                if let items = items {
                    var missingItems = [SBItem]()
                    var improvedItems = [SBItem]()
                    for item in items {
                        // Missing?
                        if savedItems[item.itemTypeID] == nil {
                            if item.locked {
                                print("Missing but locked - \(item.name)")
                                continue
                            }
                            else
                            {
                                print("Missing - \(item.name)")
                                missingItems.append(item)
                            }
                        }
                        
                        // Improved?
                        if let savedItem = savedItems[item.itemTypeID] {
                            if item.number < savedItem.number {
                                if item.locked {
                                    print("Improved but locked - \(item.name)")
                                    continue
                                }
                                else
                                {
                                    print("Improved - \(item.name)")
                                    improvedItems.append(item)
                                }
                            }
                        }
                    }
                    if missingItems.count > 0 {
                        let pickupRow = PickupRow(place: place, items: missingItems, kindLabel: "missing")
                        s.missingSection.pendingRows.append(pickupRow)
                        s.shouldUpdateSections()
                    }
                    if improvedItems.count > 0 {
                        let pickupRow = PickupRow(place: place, items: improvedItems, kindLabel: "improved")
                        s.improveSection.pendingRows.append(pickupRow)
                        s.shouldUpdateSections()
                    }
                }
            })
        }
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
    
    func updateSections() {
        tableView.beginUpdates()
        var sectionOn = 0
        for section in sections {
            while section.pendingRows.count > 0 {
                let index = NSIndexPath(forRow: section.rows.count, inSection: sectionOn)
                tableView.insertRowsAtIndexPaths([index], withRowAnimation: .Automatic)
                section.rows.append(section.pendingRows.first!)
                section.pendingRows.removeFirst()
            }
            sectionOn++
        }
        tableView.endUpdates()
    }
    
    func didLogin(user : SBUser) {
        print("Logged in - \(user.name) #\(user.id)")
        self.navigationItem.title = user.name
        self.user = user
        self.getSavedItems()
    }
    
    func getSavedItems() {
        guard let user = user else { login(); return }
        user.savedItems { [weak self] (error, savedItems) -> Void in
            guard let s = self else { return }
            if let error = error {
                AppDelegate.handleError(error, completion: { () -> Void in
                    s.login()
                })
                return
            }
            s.savedItems = [ Int : SBSavedItem ]()
            if let savedItems = savedItems {
                for savedItem in savedItems {
                    s.savedItems![savedItem.itemTypeID] = savedItem
                }
            }
            s.addUniqueItems()
        }
    }
    
    func addUniqueItems() {
        guard let user = user else { login(); return }
        user.uniqueItems { [weak self] (error, uniqueItems) -> Void in
            guard let s = self else { return }
            if let error = error {
                AppDelegate.handleError(error, completion: { () -> Void in
                    s.login()
                })
                return
            }
            if let uniqueItems = uniqueItems {
                for uniqueItem in uniqueItems {
                    s.savedItems![uniqueItem.itemTypeID] = uniqueItem
                }
            }
            s.refreshList()
        }
    }
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        getNearby()
    }
    
    func locationManager(manager: CLLocationManager, didUpdateToLocation newLocation: CLLocation, fromLocation oldLocation: CLLocation) {
        locationManager.stopUpdatingLocation()
        nearbyForLocation(newLocation)
    }
    
    func nearbyForLocation(location : CLLocation) {
        startedActivity()
        bee.nearby(location) { [weak self] (error, places) -> Void in
            guard let s = self else { return }
            s.stoppedActivity()
            if let error = error {
                AppDelegate.handleError(error, completion: { [weak s] () -> Void in
                    guard let s = s else { return }
                    s.nearbyForLocation(location)
                })
                return
            }
            s.nearby = places
            s.refreshList()
        }
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return sections.count
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
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

class ActionSection {
    let title : String
    var rows : [ ActionRow ] = [ActionRow]()
    var pendingRows : [ ActionRow ] = [ActionRow]()
    init(title : String) {
        self.title = title
    }
}

class ActionRow {
    var reuse : String = "basic"
    var setup : (cell : UITableViewCell, table : UITableView) -> Void = { _,_ in }
    var select : (tableView : UITableView, indexPath : NSIndexPath) -> Void = { tableView, indexPath in
        tableView.deselectRowAtIndexPath(indexPath, animated: false)
    }
}

class PickupRow : ActionRow {
    let place : SBPlace
    let items : [SBItem]
    init(place : SBPlace, items : [SBItem], kindLabel : String) {
        self.place = place
        self.items = items
        super.init()
        reuse = "pickup"
        setup = { cell,_ in
            if let cell = cell as? PickupCell {
                cell.row = self
                cell.detailLabel!.text = "\(items.count) \(kindLabel) item\(items.count == 1 ? "" : "s")"
            }
        }
        select = { tableView, indexPath in
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://places/\(place.id)")!)
        }
    }
}

class PickupCell : UITableViewCell {
    @IBOutlet var itemsStack : UIStackView?
    @IBOutlet var placeImageView : UIImageView?
    @IBOutlet var label : UILabel?
    @IBOutlet var detailLabel : UILabel?
    
    var row : PickupRow? {
        didSet {
            // Cleanup
            itemsStack!.subviews.forEach { (view) -> () in
                view.removeFromSuperview()
            }
            if let row = row {
                var imageSize = 100
                if UIScreen.mainScreen().scale == 1.0 {
                    imageSize = 50
                }
                let scale = CGFloat(imageSize) / CGFloat(50)
                for item in row.items {
                    let imageView = UIImageView(frame: CGRectMake(0, 0, 50, 50))
                    if let url = item.imageURL(imageSize) {
                        item.bee.session.dataTaskWithURL(url, completionHandler: { [weak self] (data, _, error) -> Void in
                            guard let s = self else { return }
                            if s.row !== row { return }
                            if let error = error {
                                print("Error loading image - \(error)")
                                return
                            }
                            if let data = data {
                                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                    imageView.image = UIImage(data: data, scale: scale)
                                })
                            }
                        }).resume()
                    }
                    itemsStack!.addArrangedSubview(imageView)
                }
                itemsStack!.sizeToFit()
                if let url = row.place.imageURL(imageSize) {
                    row.place.bee.session.dataTaskWithURL(url, completionHandler: { [weak self] (data, _, error) -> Void in
                        guard let s = self else { return }
                        if s.row !== row { return }
                        if let error = error {
                            print("Error loading image - \(error)")
                            return
                        }
                        if let data = data {
                            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                s.placeImageView!.image = UIImage(data: data, scale: scale)
                            })
                        }
                    }).resume()
                }
                label!.text = row.place.name
            }
        }
    }
}