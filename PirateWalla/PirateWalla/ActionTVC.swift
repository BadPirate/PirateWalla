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
    let progressView  = UILabel(frame: CGRectMake(0,0,200,40))
    
    // Sections
    let sections : [ActionSection]
    let missingSection : ActionSection
    let mixPickupSection : ActionSection
    let improveSection : ActionSection
    let sdSection : ActionSection
    let ddSection : ActionSection
    let tdSection : ActionSection
    let onexxSection : ActionSection
    
    var willUpdateSections : Bool = false
    var willUpdateProgress : Bool = false
    let activityLock : dispatch_queue_t
    var activities = [String]()
    
    // State Variables
    var user : SBUser?
    var nearby : [ SBPlace ]?
    let savedItemsLock : dispatch_queue_t
    var savedItems : [ Int : SBSavedItem ]?
    typealias Mixes = [ Int : Set<Int> ]
    var mixRequiredItems : Mixes?
    var mixReverseLookup : [ Int : SBItemType ]?
    var refreshing = false
    var refreshLocation = false
    
    required init?(coder aDecoder: NSCoder) {
        sdSection = ActionSection(title: "SINGLE DIGIT!!", rowDescriptor: "SD")
        ddSection = ActionSection(title: "Double Digit Items", rowDescriptor: "DD")
        tdSection = ActionSection(title: "Triple Digit Items", rowDescriptor: "TD")
        onexxSection = ActionSection(title: "1xxx", rowDescriptor: "1xxx")
        missingSection = ActionSection(title: "Missing Items", rowDescriptor: "Missing")
        improveSection = ActionSection(title: "Improved Items", rowDescriptor: "Improved")
        mixPickupSection = ActionSection(title: "Pickup for Mix", rowDescriptor: "Mix")
        
        sections = [missingSection,sdSection,ddSection,tdSection,onexxSection,mixPickupSection,improveSection]
        let bee = SwiftBee()
        self.bee = bee
        self.cloudCache = CloudCache(bee: bee)
        activityLock = dispatch_queue_create("ActivityLock", nil)
        savedItemsLock = dispatch_queue_create("SavedItemsLock", nil)
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        self.navigationItem.title = "Log in"
        locationManager.delegate = self
        if let navigationController = navigationController {
            navigationController.toolbarHidden = false
        }
        progressView.textAlignment = .Center
        progressView.adjustsFontSizeToFitWidth = true
        toolbarItems = [UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil),UIBarButtonItem(customView: progressView),UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)]
        login()
        getNearby()
    }
    
    func addToggleSetting(alert : UIAlertController, setting : String, description: String, onAction: String, offAction: String) {
        let value = NSUserDefaults.standardUserDefaults().boolForKey(setting)
        let stateString = value ? offAction : onAction
        alert.addAction(UIAlertAction(title: "\(stateString) \(description)" , style: .Default, handler: { [weak self] (_) -> Void in
            NSUserDefaults.standardUserDefaults().setBool(!value, forKey: setting)
            NSUserDefaults.standardUserDefaults().synchronize()
            self?.reload()
        }))
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
    
    @IBAction func settings(sender: UIBarButtonItem) {
        let alert = UIAlertController(title: "Settings", message: nil, preferredStyle: .ActionSheet)
        addToggleSetting(alert, setting: "disableNearbySearch", description: "nearby", onAction: "Don't search", offAction: "Search")
        addToggleSetting(alert, setting: "disableMarketSearch", description: "Market", onAction: "Don't search", offAction: "Search")
        addToggleSetting(alert, setting: "enable1xxxSearch", description: "1xxx Search", onAction: "Enable", offAction: "Disable")
        addToggleSetting(alert, setting: "disableSDSearch", description: "SD Search", onAction: "Disable", offAction: "Enable")
        addToggleSetting(alert, setting: "disableDDSearch", description: "DD Search", onAction: "Disable", offAction: "Enable")
        addToggleSetting(alert, setting: "disableTDSearch", description: "TD Search", onAction: "Disable", offAction: "Enable")
        addNumericalSetting(alert, key: "minImprovement", zero: "0", title: "Min Improvement", description: "Minimum amount items should be improved before showing in list, 0 for no minimum")
        addNumericalSetting(alert, key: "maxPrice", zero: "No Max", title: "Max Market", description: "Maximum market price per item, 0 for no maximum")
        alert.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
        if let presenter = alert.popoverPresentationController{
            presenter.barButtonItem = sender
        }
        alert.addAction(UIAlertAction(title: "Logout", style: .Default, handler: { [weak self] _ -> Void in
            guard let s = self else { return }
            s.logout()
            s.login()
        }))
        self.presentViewController(alert, animated: true, completion: nil)
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
        }
        else
        {
            if progressView.text != nil {
                progressView.text = nil
            }
        }
    }
    
    func reset() {
        bee.cancelAll()
        clearRows()
        nearby = nil
        dispatch_sync(savedItemsLock) { () -> Void in
            self.savedItems = nil
        }
        refreshing = false
    }
    
    @IBAction func reload() {
        reset()
        getNearby()
        getSavedItems()
    }
    
    func logout() {
        NSUserDefaults.standardUserDefaults().removeObjectForKey("id")
        NSUserDefaults.standardUserDefaults().synchronize()
        user = nil
        navigationItem.title = "Logged Out"
        reset()
    }
    
    func login() {
        if let id = NSUserDefaults.standardUserDefaults().stringForKey("id")
        {
            let loginActivity = "Logging in"
            startedActivity(loginActivity)
            bee.user(id) { [weak self] (error, user) -> Void in
                guard let s = self else { return }
                s.stoppedActivity(loginActivity)
                if let error = error {
                    AppDelegate.handleError(error, button: "Retry", title: "Error logging in", completion: { () -> Void in
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
                    s.startedActivity("Updating Location")
                    s.locationManager.startUpdatingLocation()
                }
                else
                {
                    s.nearbyForLocation(userLocation)
                }
            }
            else {
                s.startedActivity("Updating Location")
                s.locationManager.startUpdatingLocation()
            }
        }
    }
    
    func getNearby() {
        if NSUserDefaults.standardUserDefaults().boolForKey("disableNearbySearch") == true {
            nearby = [SBPlace]()
            refreshList()
            return
        }
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
        
        if let currentLocation = locationManager.location {
            refreshLocation = true
            nearbyForLocation(currentLocation)
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
            dispatch_sync(section.pendingRowLock, { () -> Void in
                section.pendingRows.removeAll()
            })
        }
        if rowsRemoved {
            tableView.reloadData()
        }
    }
    
    let marketPlaceID = -100
    typealias placeObjects = [ ActionSection : [ SBPlace : Set<SBItemBase> ] ]
    
    func appendPlaceObject(inout placeObject : placeObjects, section : ActionSection, atPlace : SBPlace?, item : SBItemBase) {
        let place = (atPlace != nil) ? atPlace! : SBPlace(dictionary: [ "id" : "\(marketPlaceID)" ], bee: item.bee)
        
        if placeObject[section] == nil {
            placeObject[section] = [ SBPlace : Set<SBItemBase> ]()
        }
        if placeObject[section]![place] == nil {
            placeObject[section]![place] = Set<SBItemBase>()
        }
        placeObject[section]![place]!.insert(item)
    }
    
    func parseItems(items: [SBItemBase], place : SBPlace?)
    {
        guard let savedItems = savedItems, mixReverseLookup = mixReverseLookup else { return }
        var placeObjectsFound = placeObjects()
        
        let minImprovement = NSUserDefaults.standardUserDefaults().integerForKey("minImprovement")
        for item in items {
            if item.locked { continue }
            
            // SD?
            if item.number < 10 && !NSUserDefaults.standardUserDefaults().boolForKey("disableSDSearch") {
                print("Single Digit! - \(item.name)")
                appendPlaceObject(&placeObjectsFound, section: sdSection, atPlace: place, item: item)
                continue
            }
            
            // Missing?
            if savedItems[item.itemTypeID] == nil {
                print("Missing - \(item.name)")
                appendPlaceObject(&placeObjectsFound, section: missingSection, atPlace: place, item: item)
                continue
            }
            
            // DD?
            if item.number < 100 && !NSUserDefaults.standardUserDefaults().boolForKey("disableDDSearch") {
                print("DD - \(item.name)")
                appendPlaceObject(&placeObjectsFound, section: ddSection, atPlace: place, item: item)
                continue
            }
            
            // TD?
            if item.number < 1000 && !NSUserDefaults.standardUserDefaults().boolForKey("disableTDSearch") {
                print("TD - \(item.name)")
                appendPlaceObject(&placeObjectsFound, section: tdSection, atPlace: place, item: item)
                continue
            }
            
            // 1xxx
            if item.number < 2000 && NSUserDefaults.standardUserDefaults().boolForKey("enable1xxxSearch") {
                print("1xxx - \(item.name)")
                appendPlaceObject(&placeObjectsFound, section: onexxSection, atPlace: place, item: item)
                continue
            }
            
            // Pickup for Mix?
            if mixReverseLookup[item.itemTypeID] != nil {
                print("Found item needed for mix - \(item.name)")
                appendPlaceObject(&placeObjectsFound, section: mixPickupSection, atPlace: place, item: item)
                continue
            }
            
            // Improved?
            if let savedItem = savedItems[item.itemTypeID] {
                if item.number + minImprovement < savedItem.number {
                    print("Improved - \(item.name)")
                    appendPlaceObject(&placeObjectsFound, section: improveSection, atPlace: place, item: item)
                    continue
                }
            }
        }
        
        for (actionSection, placeObjects) in placeObjectsFound {
            for (place, items) in placeObjects {
                if place.id == marketPlaceID {
                    // Market
                    let marketActivity = "Sorting Market Items"
                    var marketItems = Set<SBMarketItem>()
                    for item in items {
                        if let item = item as? SBMarketItem {
                            marketItems.insert(item)
                        }
                    }
                    startedActivity(marketActivity)
                    groupItemsBySet(marketItems, completion: { [weak self] (error, groups) -> Void in
                        self?.stoppedActivity(marketActivity)
                        guard let s = self, groups = groups else { return }
                        if let error = error {
                            AppDelegate.handleError(error, button: "Cloud Error", title: "Okay", completion: { () -> Void in })
                            return
                        }
                        for (set, items) in groups {
                            dispatch_sync(actionSection.pendingRowLock, { () -> Void in
                                actionSection.pendingRows.append(MarketRow(set: set, items: Array(items), kindLabel: actionSection.rowDescriptor))
                            })
                            s.shouldUpdateSections()
                        }
                    })
                }
                else {
                    var plainItems = [SBItem]()
                    for item in items {
                        if let item = item as? SBItem {
                            plainItems.append(item)
                        }
                    }
                    let pickupRow = PickupRow(place: place, items: plainItems, kindLabel: actionSection.rowDescriptor)
                    dispatch_sync(actionSection.pendingRowLock, { () -> Void in
                        actionSection.pendingRows.append(pickupRow)
                    })
                    shouldUpdateSections()
                }
            }
        }
    }
    
    func groupItemsBySet(items: Set<SBMarketItem>, completion : (error : NSError?, groups : [ SBSet : Set<SBItem> ]?) -> Void)
    {
        cloudCache.enhance(items) { [weak self] (error, items) -> Void in
            guard let s = self else { return }
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
            
            s.cloudCache.sets(Set(groupedBySetIdentifier.keys), completion: { (error, sets) -> Void in
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
        
        guard let user = user else { print("Waiting for user (\(self.user)) data before refresh"); return }
        guard let nearby = nearby else { print("Waiting for nearby (\(self.nearby)) information before refresh"); return }
        guard let savedItems = savedItems else { print("Waiting for savedItems (\(self.savedItems)) information before refresh"); return }
        guard let mixReverseLookup = mixReverseLookup, mixRequiredItems = mixRequiredItems else { print("Waiting for Mix / saved items"); return }
        
        if refreshing { return }
        refreshing = true
        
        clearRows()
        
        // Check the Helicarrier
        let helicarrierActivity = "Checking Helicarrier"
        startedActivity(helicarrierActivity)
        bee.place(helicarrierID) { [weak self] (error, place) -> Void in
            guard let s = self else { return }
            if let place = place {
                place.items({ [weak s] (error, items) -> Void in
                    s?.stoppedActivity(helicarrierActivity)
                    guard let s = s, items = items else { return }
                    s.parseItems(items, place: place)
                    })
            }
            else
            {
                self?.stoppedActivity(helicarrierActivity)
            }
        }
        
        // Check Nearby
        print("Refreshing list User - \(user.id) - Nearby \(nearby.count) - Saved Items \(savedItems.count)")
        for place in nearby {
            let checkNearbyActivity = "Searching \(place.name)"
            startedActivity(checkNearbyActivity)
            place.items({ [weak self] (error, items) -> Void in
                self?.stoppedActivity(checkNearbyActivity)
                guard let s = self, let snb = s.nearby, items = items else { return }
                if snb != nearby { return }
                if let error = error {
                    AppDelegate.handleError(error, button: "Okay", title: "Error locating items", completion: { () -> Void in })
                    return
                }
                s.parseItems(items, place: place)
                })
        }
        
        if NSUserDefaults.standardUserDefaults().boolForKey("disableMarketSearch") == false {
            // Check the Market
            let marketActivity = "Searching Market"
            startedActivity(marketActivity)
            bee.market { [weak self] (error, items) -> Void in
                self?.stoppedActivity(marketActivity)
                guard let s = self else { return }
                if error != nil { return }
                if let items = items {
                    let maxPrice = NSUserDefaults.standardUserDefaults().integerForKey("maxPrice")
                    var foundItems = [SBMarketItem]()
                    for item in items {
                        if maxPrice > 0 && item.cost > maxPrice {
                            print("Market item found, but overpriced \(item.shortDescription)")
                            continue
                        }
                        foundItems.append(item)
                    }
                    s.parseItems(foundItems, place: nil)
                }
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
    
    func didLogin(user : SBUser) {
        print("Logged in - \(user.name) #\(user.id)")
        self.navigationItem.title = user.name
        self.user = user
        self.getSavedItems()
    }
    
    func getSavedItems() {
        guard let user = user else { login(); return }
        let savedActivity = "Getting saved items"
        self.startedActivity(savedActivity)
        user.savedItems { [weak self] (error, savedItems) -> Void in
            self?.stoppedActivity(savedActivity)
            guard let s = self else { return }
            if let error = error {
                AppDelegate.handleError(error, completion: { () -> Void in
                    s.login()
                })
                return
            }
            dispatch_sync(s.savedItemsLock, { () -> Void in
                s.savedItems = [ Int : SBSavedItem ]()
                if let savedItems = savedItems {
                    for savedItem in savedItems {
                        s.savedItems![savedItem.itemTypeID] = savedItem
                    }
                }
            })
            s.addUniqueItems()
        }
    }
    
    func addUniqueItems() {
        guard let user = user else { login(); return }
        let uniqueItemsActivity = "Getting unique items"
        startedActivity(uniqueItemsActivity)
        user.uniqueItems { [weak self] (error, uniqueItems) -> Void in
            self?.stoppedActivity(uniqueItemsActivity)
            guard let s = self else { return }
            if let error = error {
                AppDelegate.handleError(error, completion: { () -> Void in
                    s.login()
                })
                return
            }
            dispatch_sync(s.savedItemsLock, { () -> Void in
                if s.savedItems == nil { return }
                if let uniqueItems = uniqueItems {
                    for uniqueItem in uniqueItems {
                        s.savedItems![uniqueItem.itemTypeID] = uniqueItem
                    }
                }
            })
            s.getMixRequirements()
        }
    }
    
    func getMixRequirements() {
        let activity = "Updating Set List"
        startedActivity(activity)
        bee.setList { [weak self] (error, sets) -> Void in
            guard let s = self else { return }
            s.stoppedActivity(activity)
            if let error = error {
                AppDelegate.handleError(error, button: "Okay", title: "Mix error", completion: { () -> Void in
                    s.mixRequiredItems = Mixes()
                    s.refreshList()
                })
                return
            }
            let sets = sets!
            var setIdentifiers = Set<Int>()
            for set in sets {
                setIdentifiers.insert(set.setID)
            }
            let activity = "Calculating mixes"
            s.startedActivity(activity)
            s.cloudCache.sets(setIdentifiers, completion: { [weak s] (error, sets) -> Void in
                guard let s = s else { return }
                s.stoppedActivity(activity)
                if let error = error {
                    AppDelegate.handleError(error, button: "Okay", title: "Mix error", completion: { () -> Void in
                        s.mixRequiredItems = Mixes()
                        s.refreshList()
                    })
                    return
                }
                let sets = sets!
                dispatch_sync(s.savedItemsLock, { () -> Void in
                    guard let savedItems = s.savedItems else { return }
                    s.mixRequiredItems = Mixes()
                    s.mixReverseLookup = [ Int : SBItemType ]()
                    for set in sets {
                        for itemType in set.itemTypes {
                            if savedItems[itemType.id] == nil {
                                let mix = itemType.mix
                                s.mixRequiredItems![itemType.id] = mix
                                for mixItem in mix {
                                    s.mixReverseLookup![mixItem] = itemType
                                }
                            }
                        }
                    }
                })
                s.refreshList()
            })
        }
    }
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        getNearby()
    }
    
    func locationManager(manager: CLLocationManager, didUpdateToLocation newLocation: CLLocation, fromLocation oldLocation: CLLocation) {
        stoppedActivity("Updating Location")
        locationManager.stopUpdatingLocation()
        
        if (refreshLocation) {
            refreshLocation = false;
            if oldLocation.distanceFromLocation(newLocation) > 500
            {
                nearbyForLocation(newLocation)
            }
            return
        }
        nearbyForLocation(newLocation)
    }
    
    func nearbyForLocation(location : CLLocation) {
        let nearbyActivity = "Searching nearby"
        startedActivity(nearbyActivity)
        bee.nearby(location) { [weak self] (error, places) -> Void in
            guard let s = self else { return }
            s.stoppedActivity(nearbyActivity)
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

class ActionSection : Hashable {
    let title : String
    let rowDescriptor : String
    let pendingRowLock : dispatch_queue_t
    
    var rows : [ ActionRow ] = [ActionRow]()
    var pendingRows : [ ActionRow ] = [ActionRow]()
    init(title : String, rowDescriptor : String) {
        self.title = title
        self.pendingRowLock = dispatch_queue_create("actionTVC.\(title)", nil)
        self.rowDescriptor = rowDescriptor
    }
    var hashValue: Int {
        get {
            return title.hashValue
        }
    }
}

func ==(lhs: ActionSection, rhs: ActionSection) -> Bool {
    return lhs.title == rhs.title
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
                cell.detailText = "\(items.count) \(kindLabel) item\(items.count == 1 ? "" : "s")"
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
    @IBOutlet var moreImageView : UIImageView?
    @IBOutlet var moreImageConstraint : NSLayoutConstraint?
    
    func cleanup() {
        placeImageView!.image = nil
        label!.text = nil
        detailLabel!.text = nil
        updateItemStack()
    }
    
    override var frame : CGRect {
        didSet {
            updateItemStack()
        }
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
    
    var imageViews = [UIImageView]()
    
    var row : ItemRow? {
        didSet {
            imageViews.removeAll()
            if let row = row {
                for item in row.items {
                    let imageView = UIImageView(frame: CGRectMake(0, 0, 50, 50))
                    imageView.addConstraint(NSLayoutConstraint(item: imageView, attribute: .Width, relatedBy: .GreaterThanOrEqual, toItem: nil, attribute: .NotAnAttribute, multiplier: 1.0, constant: minimumItemWidth))
                    imageView.image = blankImage
                    if let url = item.imageURL(imageSize) {
                        item.bee.session.dataTaskWithURL(url, completionHandler: { [weak self, weak imageView] (data, _, error) -> Void in
                            guard let s = self, imageView = imageView else { return }
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
                    imageViews.append(imageView)
                }
            }
        }
    }
    
    var blankImage : UIImage {
        get {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(50, 50), false, 0.0);
            let blank = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            return blank
        }
    }
    
    let minimumItemWidth = CGFloat(25)
    let maximumPercent : CGFloat = 0.4
    var moreWidth : CGFloat = 0
    
    func updateItemStack() {
        guard let row = row else { return }
        let itemsStack = self.itemsStack!
        itemsStack.subviews.forEach { (view) -> () in
            view.removeFromSuperview()
        }
        let showItems = min(Int(floor((frame.size.width * maximumPercent) / (minimumItemWidth + itemsStack.spacing))),row.items.count)
        for on in 0..<showItems {
            let imageView = imageViews[on]
            itemsStack.addArrangedSubview(imageView)
        }
        let showMore = showItems != row.items.count
        moreWidth = max(moreImageConstraint!.constant,moreWidth)
        moreImageConstraint!.constant = showMore ? moreWidth : 0.0
        let minStackWidth = CGFloat(showItems) * minimumItemWidth + CGFloat(max(0,showItems-1)) * itemsStack.spacing
        let maxStackWidth = CGFloat(showItems) * 50.0 + CGFloat(max(0,showItems-1)) * itemsStack.spacing
        let width = min(max(minStackWidth,frame.width*maximumPercent),maxStackWidth)
        itemsStack.removeConstraints(itemsStack.constraints)
        itemsStack.addConstraint(NSLayoutConstraint(item: itemsStack, attribute: .Width, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 1.0, constant: width))
    }
    
    func setPlaceImage(url : NSURL) {
        guard let row = row else { return }
        placeImageView!.image = blankImage
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
        withinRange = distanceForPickup() <= 0
    }
    
    func distanceForPickup() -> Double {
        guard let row = pickupRow, userLocation = locationManager.location else { return 0 }
        if row.place.id == helicarrierID { return 0 }
        let location = CLLocation(latitude: row.place.location.latitude, longitude: row.place.location.longitude)
        return location.distanceFromLocation(userLocation) - row.place.radius + userLocation.horizontalAccuracy
    }
    
    var withinRange : Bool = true {
        didSet {
            updateState()
        }
    }
    
    func updateState() {
        detailLabel!.enabled = withinRange
        label!.enabled = withinRange
        detailLabel!.text = withinRange ? detailText : "(\(Int(distanceForPickup()))m) Too far away to pickup"
        backgroundColor! = withinRange ? UIColor.whiteColor() : UIColor.lightGrayColor()
    }
    
    
    var detailText : String? {
        didSet {
            updateState()
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