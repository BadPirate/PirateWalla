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

let helicarrierID = 1728050

class ActionTVC : UITableViewController, CLLocationManagerDelegate {
    let bee : SwiftBee
    let cloudCache : CloudCache
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
        let bee = SwiftBee()
        self.bee = bee
        self.cloudCache = CloudCache(bee: bee)
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
    
    func addNumericalSetting(alert : UIAlertController, key : String, zero : String, title : String, description : String) {
        let value = NSUserDefaults.standardUserDefaults().integerForKey(key) == 0 ? zero : "\(NSUserDefaults.standardUserDefaults().integerForKey(key))"
        alert.addAction(UIAlertAction(title: "\(title) - \(value)", style: .Default, handler: { [weak self] (_) -> Void in
            let alert = UIAlertController(title: title, message: description, preferredStyle: .Alert)
            alert.addTextFieldWithConfigurationHandler({ (textField) -> Void in
                textField.keyboardType = .NumberPad
                textField.text = "\(NSUserDefaults.standardUserDefaults().integerForKey(key))"
            })
            alert.addAction(UIAlertAction(title: "Set", style: .Default, handler: { _ -> Void in
                if let value = Int(alert.textFields![0].text ?? "0")
                {
                    NSUserDefaults.standardUserDefaults().setInteger(value, forKey: key)
                    NSUserDefaults.standardUserDefaults().synchronize()
                    self?.reload()
                }
            }))
            self?.presentViewController(alert, animated: true, completion: nil)
            }))
    }
    
    @IBAction func settings() {
        let alert = UIAlertController(title: "Settings", message: nil, preferredStyle: .ActionSheet)
        alert.addAction(UIAlertAction(title: "Logout", style: .Default, handler: { [weak self] _ -> Void in
            self?.logout()
            self?.login()
            self?.reload()
        }))
        addNumericalSetting(alert, key: "minImprovement", zero: "0", title: "Min Improvement", description: "Minimum amount items should be improved before showing in list, 0 for no minimum")
        addNumericalSetting(alert, key: "maxPrice", zero: "No Max", title: "Max Market", description: "Maximum market price per item, 0 for no maximum")
        alert.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
        self.presentViewController(alert, animated: true, completion: nil)
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
    
    func logout() {
        NSUserDefaults.standardUserDefaults().removeObjectForKey("id")
        NSUserDefaults.standardUserDefaults().synchronize()
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
                        s.logout()
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
            if let userLocation = s.locationManager.location {
                if userLocation.timestamp.timeIntervalSinceNow < -5 {
                    s.locationManager.startUpdatingLocation()
                }
                else
                {
                    s.nearbyForLocation(userLocation)
                }
            }
            else {
                s.locationManager.startUpdatingLocation()
            }
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
    
    func parseItems(items: [SBItemBase], place : SBPlace?)
    {
        guard let savedItems = savedItems else { return }
        var missingItems = [SBItem]()
        var improvedItems = [SBItem]()
        var missingMarket = Set<SBMarketItem>()
        var improvedMarket = Set<SBMarketItem>()
        
        let minImprovement = NSUserDefaults.standardUserDefaults().integerForKey("minImprovement")
        for item in items {
            // Missing?
            if savedItems[item.itemTypeID] == nil {
                if let item = item as? SBItem {
                    if item.locked {
                        print("Missing but locked - \(item.name)")
                        continue
                    }
                    print("Missing - \(item.name)")
                    missingItems.append(item)
                }
                else if let item = item as? SBMarketItem {
                    print("Missing market - \(item)")
                    missingMarket.insert(item)
                }
            }
            
            // Improved?
            if let savedItem = savedItems[item.itemTypeID] {
                if item.number + minImprovement < savedItem.number {
                    if let item = item as? SBItem {
                        if item.locked {
                            print("Improved but locked - \(item.name)")
                            continue
                        }
                        print("Improved - \(item.name)")
                        improvedItems.append(item)
                    }
                    else if let item = item as? SBMarketItem {
                        print("Improved market - \(item.shortDescription)")
                        improvedMarket.insert(item)
                    }
                }
            }
        }
        if let place = place {
            if missingItems.count > 0 {
                let pickupRow = PickupRow(place: place, items: missingItems, kindLabel: "missing")
                missingSection.pendingRows.append(pickupRow)
                shouldUpdateSections()
            }
            if improvedItems.count > 0 {
                let pickupRow = PickupRow(place: place, items: improvedItems, kindLabel: "improved")
                improveSection.pendingRows.append(pickupRow)
                shouldUpdateSections()
            }
        }
        if missingMarket.count > 0 {
            startedActivity()
            groupItemsBySet(missingMarket, completion: { [weak self] (error, groups) -> Void in
                self?.stoppedActivity()
                guard let s = self, groups = groups else { return }
                if let _ = error { return }
                for (set, items) in groups {
                    s.missingSection.pendingRows.append(MarketRow(set: set, items: Array(items), kindLabel: "missing"))
                    s.shouldUpdateSections()
                }
            })
        }
        if improvedMarket.count > 0 {
            startedActivity()
            groupItemsBySet(improvedMarket, completion: { [weak self] (error, groups) -> Void in
                self?.stoppedActivity()
                if let _ = error { return }
                guard let s = self, groups = groups else { return }
                for (set, items) in groups {
                    s.improveSection.pendingRows.append(MarketRow(set: set, items: Array(items), kindLabel: "improved"))
                    s.shouldUpdateSections()
                }
            })
        }
    }
    
    func groupItemsBySet(items: Set<SBMarketItem>, completion : (error : NSError?, groups : [ SBSet : Set<SBItem> ]?) -> Void)
    {
        startedActivity()
        cloudCache.enhance(items) { [weak self] (error, items) -> Void in
            guard let s = self else { return }
            s.stoppedActivity()
            if let error = error {
                completion(error: error, groups: nil)
                return
            }
            let items = items!
            var groupedBySetIdentifier = [ Int : Set<SBItem> ]()
            for item in items {
                if let group = groupedBySetIdentifier[item.setID] {
                    var mutableGroup = group
                    var found = false
                    for groupItem in group {
                        if groupItem.itemTypeID == item.itemTypeID {
                            found = true
                            break
                        }
                    }
                    if found { continue }
                    mutableGroup.insert(item)
                    groupedBySetIdentifier[item.setID] = mutableGroup
                }
                else
                {
                    var group = Set<SBItem>()
                    group.insert(item)
                    groupedBySetIdentifier[item.setID] = group
                }
            }

            s.cloudCache.sets(Set(groupedBySetIdentifier.keys), completion: { [weak s] (error, sets) -> Void in
                guard let s = s else { return }
                s.stoppedActivity()
                if let error = error {
                    completion(error: error, groups: nil)
                    return
                }
                var groups = [ SBSet : Set<SBItem> ]()
                let sets = sets!
                for set in sets {
                    groups[set] = groupedBySetIdentifier[set.id]
                }
                completion(error: nil, groups: groups)
            })
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

        // Check the Helicarrier
        startedActivity()
        bee.place(helicarrierID) { [weak self] (error, place) -> Void in
            self?.stoppedActivity()
            guard let s = self else { return }
            if let place = place {
                s.startedActivity()
                place.items({ [weak s] (error, items) -> Void in
                    s?.stoppedActivity()
                    guard let s = s, items = items else { return }
                    s.parseItems(items, place: place)
                })
            }
        }
        
        // Check Nearby
        print("Refreshing list User - \(user.id) - Nearby \(nearby.count) - Saved Items \(savedItems.count)")
        for place in nearby {
            startedActivity()
            place.items({ [weak self] (error, items) -> Void in
                self?.stoppedActivity()
                guard let s = self, let snb = s.nearby, items = items else { return }
                if snb != nearby { return }
                if let error = error {
                    AppDelegate.handleError(error, completion: { () -> Void in })
                    return
                }
                s.parseItems(items, place: place)
            })
        }
        
        // Check the Market
        startedActivity()
        bee.market { [weak self] (error, items) -> Void in
            self?.stoppedActivity()
            guard let s = self else { return }
            if error != nil { return }
            if let items = items {
                let maxPrice = NSUserDefaults.standardUserDefaults().integerForKey("maxPrice")
                var foundItems = [SBMarketItem]()
                for item in items {
                    if maxPrice > 0 && item.cost > maxPrice {
                        print("Market item found, but overpriced \(item)")
                        continue
                    }
                    foundItems.append(item)
                }
                s.parseItems(foundItems, place: nil)
            }
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

class ItemRow : ActionRow {
    let items : [SBItem]
    let bee : SwiftBee
    init(items : [SBItem], bee: SwiftBee) {
        self.items = items
        self.bee = bee
    }
}

class MarketRow : ItemRow {
    let set : SBSet
    init(set : SBSet, items : [SBItem], kindLabel : String) {
        self.set = set
        super.init(items: items, bee: set.bee)
        reuse = "market"
        setup = { cell,_ in
            if let cell = cell as? MarketCell {
                cell.row = self
                cell.detailLabel!.text = "\(items.count) \(kindLabel) item\(items.count == 1 ? "" : "s")"
            }
        }
        select = { tableView, indexPath in
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            if NSUserDefaults.standardUserDefaults().boolForKey("marketWarned") != true {
                let alert = UIAlertController(title: "Market Items", message: "Piratewalla can't jump you right into the Market view at this time (Yet), you'll need to manually go into the appropriate part of the market on your own for now", preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "Got it", style: .Default, handler: { (_) -> Void in
                    UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://inbox")!)
                }))
                if let rootVC = (UIApplication.sharedApplication().delegate as? AppDelegate)?.window?.rootViewController {
                    rootVC.presentViewController(alert, animated: true, completion: nil)
                }
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: "marketWarned")
                NSUserDefaults.standardUserDefaults().synchronize()
                return
            }
            UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://inbox")!)
        }
    }
}

class PickupRow : ItemRow {
    let place : SBPlace
    init(place : SBPlace, items : [SBItem], kindLabel : String) {
        self.place = place
        super.init(items: items, bee: place.bee)
        reuse = "pickup"
        setup = { cell,_ in
            if let cell = cell as? PickupCell {
                cell.row = self
                cell.detailLabel!.text = "\(items.count) \(kindLabel) item\(items.count == 1 ? "" : "s")"
            }
        }
        select = { tableView, indexPath in
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            if place.id == helicarrierID {
                if NSUserDefaults.standardUserDefaults().boolForKey("helicarrierWarned") != true {
                    let alert = UIAlertController(title: "Helicarrier", message: "Piratewalla can't jump you right into the Helicarrier view at this time, you'll need to manually go into, Places -> Foragers Helicarrier to collect these", preferredStyle: .Alert)
                    alert.addAction(UIAlertAction(title: "Got it", style: .Default, handler: { (_) -> Void in
                        UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://inbox")!)
                    }))
                    if let rootVC = (UIApplication.sharedApplication().delegate as? AppDelegate)?.window?.rootViewController {
                        rootVC.presentViewController(alert, animated: true, completion: nil)
                    }
                    NSUserDefaults.standardUserDefaults().setBool(true, forKey: "helicarrierWarned")
                    NSUserDefaults.standardUserDefaults().synchronize()
                }
                else
                {
                    UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://inbox")!)
                }
            }
            else
            {
                UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://places/\(place.id)")!)
            }
        }
    }
}

class ItemCell : UITableViewCell {
    @IBOutlet var itemsStack : UIStackView?
    @IBOutlet var placeImageView : UIImageView?
    @IBOutlet var label : UILabel?
    @IBOutlet var detailLabel : UILabel?
    
    func cleanup() {
        itemsStack!.subviews.forEach { (view) -> () in
            view.removeFromSuperview()
        }
        placeImageView!.image = nil
        label!.text = nil
        detailLabel!.text = nil
    }
    
    var imageSize : Int {
        get {
            return UIScreen.mainScreen().scale == 1.0 ? 50 : 100
        }
    }
    
    var scale : CGFloat {
        get {
            return CGFloat(imageSize) / CGFloat(50)
        }
    }
    
    var row : ItemRow?
    
    func updateItemStack() {
        guard let row = row else { return }
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
                            imageView.image = UIImage(data: data, scale: s.scale)
                        })
                    }
                    }).resume()
            }
            itemsStack!.addArrangedSubview(imageView)
        }
        itemsStack!.sizeToFit()
    }
    
    func setPlaceImage(url : NSURL) {
        guard let row = row else { return }
        row.bee.session.dataTaskWithURL(url, completionHandler: { [weak self] (data, _, error) -> Void in
            guard let s = self else { return }
            if s.row !== row { return }
            if let error = error {
                print("Error loading image - \(error)")
                return
            }
            if let data = data {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    s.placeImageView!.image = UIImage(data: data, scale: s.scale)
                })
            }
            }).resume()
    }
}

class MarketCell : ItemCell {
    var marketRow : MarketRow? {
        get { return row as? MarketRow }
    }
    
    override var row : ItemRow? {
        didSet {
            cleanup()
            if let row = row as? MarketRow {
                updateItemStack()
                if let url = row.set.imageURL(imageSize) {
                    setPlaceImage(url)
                }
                label!.text = row.set.name
            }
        }
    }
}

class PickupCell : ItemCell, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    
    override func awakeFromNib() {
        locationManager.delegate = self
    }
    
    override func cleanup() {
        super.cleanup()
        withinRange = true
    }
    
    func locationManager(manager: CLLocationManager, didUpdateToLocation newLocation: CLLocation, fromLocation oldLocation: CLLocation) {
        checkLocation()
    }
    
    func checkLocation() {
        guard let row = pickupRow, userLocation = locationManager.location else { return }
        if row.place.id == helicarrierID { withinRange = true; return }
        let location = CLLocation(latitude: row.place.location.latitude, longitude: row.place.location.longitude)
        withinRange = location.distanceFromLocation(userLocation) < row.place.radius + userLocation.horizontalAccuracy
    }
    
    var withinRange : Bool = true {
        didSet {
            if oldValue == withinRange { return } // No change
            detailLabel!.enabled = withinRange
            label!.enabled = withinRange
            backgroundColor! = withinRange ? UIColor.whiteColor() : UIColor.lightGrayColor()
        }
    }
    
    override func prepareForReuse() {
        cleanup()
    }
    
    var pickupRow : PickupRow? {
        return row as? PickupRow
    }
    
    override var row : ItemRow? {
        didSet {
            // Cleanup
            cleanup()
            locationManager.stopUpdatingLocation()
            if let row = row as? PickupRow {
                checkLocation()
                locationManager.startUpdatingLocation()
                updateItemStack()
                if let url = row.place.imageURL(imageSize) {
                    setPlaceImage(url)
                }
                label!.text = row.place.name
            }
        }
    }
}