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
let defaults = NSUserDefaults.standardUserDefaults()

class ActionTVC : PWTVC, CLLocationManagerDelegate {
    let bee : SwiftBee
    let cloudCache : CloudCache
    let locationManager = CLLocationManager()
    
    // Sections
    let missingSection : ActionSection
    let mixPickupSection : ActionSection
    let significantImprovement : ActionSection
    let improveSection : ActionSection
    let sdSection : ActionSection
    let ddSection : ActionSection
    let tdSection : ActionSection
    let onexxSection : ActionSection
    let pouchSection : ActionSection
    
    // State Variables
    var user : SBUser?
    var nearby : [ SBPlace ]?
    let savedItemsLock : dispatch_queue_t
    var savedItems : [ Int : SBSavedItem ]?
    var pouchItemTypes : [ Int : SBSavedItem ]?
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
        significantImprovement = ActionSection(title: "Significant Improvement", rowDescriptor: "Improved")
        mixPickupSection = ActionSection(title: "Pickup for Mix", rowDescriptor: "Mix")
        pouchSection = ActionSection(title: "Pouch", rowDescriptor: "Pouch")
        let bee = SwiftBee()
        self.bee = bee
        self.cloudCache = CloudCache(bee: bee)
        savedItemsLock = dispatch_queue_create("SavedItemsLock", nil)
        super.init(coder: aDecoder)
        sections = [missingSection,pouchSection,significantImprovement,mixPickupSection,improveSection,sdSection,ddSection,tdSection,onexxSection]
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
    
    func reset() {
        bee.cancelAll()
        clearRows()
        if let user = user {
            let userID = defaults.stringForKey(settingUserID)
            if userID != user.name && userID != "\(user.id)" {
                self.user = nil
                login()
            }
        }
        nearby = nil
        dispatch_sync(savedItemsLock) { () -> Void in
            self.savedItems = nil
            self.mixRequiredItems = nil
            self.mixReverseLookup = nil
            self.pouchItemTypes = nil
        }
        refreshing = false
    }
    
    @IBAction func reload() {
        reset()
        getNearby()
        getSavedItems()
        getPouch()
    }
    
    func logout() {
        defaults.removeObjectForKey(settingUserID)
        defaults.synchronize()
        user = nil
        navigationItem.title = "Logged Out"
        reset()
    }
    
    func login() {
        if let id = defaults.stringForKey(settingUserID)
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
                s.didLogin(user)
            }
            return
        }
        
        let alert = UIAlertController(title: "Wallab.ee User", message: nil, preferredStyle: .Alert)
        alert.addTextFieldWithConfigurationHandler { (textField) -> Void in
            textField.placeholder = "Wallabee user name"
        }
        alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: { (action) -> Void in
            defaults.setObject(alert.textFields![0].text, forKey: settingUserID)
            defaults.synchronize()
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
        if defaults.boolForKey(settingSearchNearby) == false {
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
        guard let savedItems = savedItems, pouchItemTypes = pouchItemTypes else { return }
        var placeObjectsFound = placeObjects()
        
        let minImprovement = defaults.integerForKey(settingMinimumImprovement)
        for item in items {
            if item.locked { continue }
            
            // Missing?
            if savedItems[item.itemTypeID] == nil && pouchItemTypes[item.itemTypeID] == nil {
                print("Missing - \(item.name)")
                appendPlaceObject(&placeObjectsFound, section: missingSection, atPlace: place, item: item)
                continue
            }
            
            var isMarketItem = false
            var isOverpriced = false
            if let marketItem = item as? SBMarketItem {
                isMarketItem = true
                isOverpriced = defaults.integerForKey(settingMaxMarketImprovementPrice) < marketItem.cost
            }
            
            if !isMarketItem || (defaults.boolForKey(settingMarketImproveSearch) && !isOverpriced) {
                // Improved?
                if defaults.boolForKey(settingShowImprovements) {
                    if let savedItem = savedItems[item.itemTypeID] {
                        if item.numberClass.rawValue < savedItem.numberClass.rawValue {
                            print("Significant improvement - \(item.name)")
                            appendPlaceObject(&placeObjectsFound, section: significantImprovement, atPlace: place, item: item)
                        }
                        else if !defaults.boolForKey(settingSignificantImprovement) && item.number + minImprovement < savedItem.number {
                            print("Improved - \(item.name)")
                            appendPlaceObject(&placeObjectsFound, section: improveSection, atPlace: place, item: item)
                            continue
                        }
                    }
                }
            }
            
            if !isMarketItem || defaults.boolForKey(settingMarketShowTD) {
                // SD?
                if item.numberClass == .SD && defaults.boolForKey(settingSDSearch) {
                    print("Single Digit! - \(item.name)")
                    appendPlaceObject(&placeObjectsFound, section: sdSection, atPlace: place, item: item)
                    continue
                }
                
                // DD?
                if item.numberClass == .DD && defaults.boolForKey(settingDDSearch) {
                    print("DD - \(item.name)")
                    appendPlaceObject(&placeObjectsFound, section: ddSection, atPlace: place, item: item)
                    continue
                }
                
                // TD?
                if item.numberClass == .TD && defaults.boolForKey(settingTDSearch) {
                    print("TD - \(item.name)")
                    appendPlaceObject(&placeObjectsFound, section: tdSection, atPlace: place, item: item)
                    continue
                }
                
                // 1xxx
                if item.numberClass == .OneXXX && defaults.boolForKey(setting1xxxSearch) {
                    print("1xxx - \(item.name)")
                    appendPlaceObject(&placeObjectsFound, section: onexxSection, atPlace: place, item: item)
                    continue
                }
            }
            
            // Pickup for Mix?
            if let mixReverseLookup = mixReverseLookup {
                if defaults.boolForKey(settingMixHelper) && mixReverseLookup[item.itemTypeID] != nil && pouchItemTypes[item.itemTypeID] == nil {
                    print("Found item needed for mix - \(item.name)")
                    appendPlaceObject(&placeObjectsFound, section: mixPickupSection, atPlace: place, item: item)
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
        if defaults.boolForKey(settingMixHelper) {
            guard let _ = mixReverseLookup, _ = mixRequiredItems else { print("Waiting for Mix / saved items"); return }
        }
        guard let pouchItemTypes = pouchItemTypes else { print("Waiting for pouch"); return }
        
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
        
        if defaults.boolForKey(settingSearchMarket)  {
            // Check the Market
            let marketActivity = "Searching Market"
            startedActivity(marketActivity)
            bee.market { [weak self] (error, items) -> Void in
                self?.stoppedActivity(marketActivity)
                guard let s = self else { return }
                if error != nil { return }
                if let items = items {
                    let maxPrice = defaults.boolForKey(settingLimitMarket) ? defaults.integerForKey(settingMarketLimit) : 0
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
        
        // Check pouch
        if defaults.boolForKey(settingMixHelper) {
            var foundMixes = [ SBItemType : Set<SBSavedItem> ]()
            for itemType in pouchItemTypes.keys {
                if let itemType = mixReverseLookup![itemType] {
                    var items = Set<SBSavedItem>()
                    var complete = true
                    for itemTypeID in itemType.mix {
                        if let pouchItem = pouchItemTypes[itemTypeID] {
                            items.insert(pouchItem)
                        }
                        else
                        {
                            complete = false
                            break
                        }
                    }
                    if complete {
                        foundMixes[itemType] = items
                    }
                }
            }
            dispatch_sync(pouchSection.pendingRowLock) { () -> Void in
                for (itemType,itemSet) in foundMixes
                {
                    let mixRow = RecipeRow(items: Array(itemSet), itemType: itemType)
                    self.pouchSection.pendingRows.append(mixRow)
                }
            }
            if foundMixes.count > 0 { shouldUpdateSections() }
        }
    }
    
    func didLogin(user : SBUser) {
        print("Logged in - \(user.name) #\(user.id)")
        self.navigationItem.title = user.name
        self.user = user
        self.getSavedItems()
        self.getPouch()
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
    
    func getPouch() {
        guard let user = user else { login(); return }
        let activity = "Getting Pouch Items"
        startedActivity(activity)
        user.pouch { [weak self ] (error, items) -> Void in
            guard let s = self else { return }
            s.stoppedActivity(activity)
            let items = items!
            dispatch_sync(s.savedItemsLock, { () -> Void in
                s.pouchItemTypes = [ Int : SBItem ]()
                for item in items {
                    s.pouchItemTypes![item.itemTypeID] = item
                }
            })
            s.refreshList()
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
            s.addMixRequirements()
        }
    }
    
    func addMixRequirements() {
        if !defaults.boolForKey(settingMixHelper) {
            refreshList()
            return
        }
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
}

class ActionSection : PWSection {
    let rowDescriptor : String
    init(title: String, rowDescriptor: String) {
        self.rowDescriptor = rowDescriptor
        super.init(title: title)
    }
}

class ActionRow : PWRow {
    
}

class RecipeRow : ActionRow {
    let items : [SBSavedItem]
    let bee : SwiftBee
    let itemType : SBItemType
    init(items : [SBSavedItem], itemType : SBItemType) {
        self.items = items
        self.itemType = itemType
        self.bee = itemType.bee
        super.init()
        reuse = "recipe"
        setup = { cell,_ in
            if let cell = cell as? RecipeCell {
                cell.row = self
            }
        }
        select = { tableView, indexPath in
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            if defaults.boolForKey("pouchWarned") != true {
                let alert = UIAlertController(title: "Pouch Items", message: "Piratewalla can't jump you right into your pouch (Yet), you'll need to manually go into your pouch for now", preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "Got it", style: .Default, handler: { (_) -> Void in
                    UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://inbox")!)
                }))
                if let rootVC = (UIApplication.sharedApplication().delegate as? AppDelegate)?.window?.rootViewController {
                    rootVC.presentViewController(alert, animated: true, completion: nil)
                }
                defaults.setBool(true, forKey: "pouchWarned")
                defaults.synchronize()
                return
            }
            UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://inbox")!)
        }
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
            if defaults.boolForKey("marketWarned") != true {
                let alert = UIAlertController(title: "Market Items", message: "Piratewalla can't jump you right into the Market view at this time (Yet), you'll need to manually go into the appropriate part of the market on your own for now", preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "Got it", style: .Default, handler: { (_) -> Void in
                    UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://inbox")!)
                }))
                if let rootVC = (UIApplication.sharedApplication().delegate as? AppDelegate)?.window?.rootViewController {
                    rootVC.presentViewController(alert, animated: true, completion: nil)
                }
                defaults.setBool(true, forKey: "marketWarned")
                defaults.synchronize()
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
                if defaults.boolForKey("helicarrierWarned") != true {
                    let alert = UIAlertController(title: "Helicarrier", message: "Piratewalla can't jump you right into the Helicarrier view at this time, you'll need to manually go into, Places -> Foragers Helicarrier to collect these", preferredStyle: .Alert)
                    alert.addAction(UIAlertAction(title: "Got it", style: .Default, handler: { (_) -> Void in
                        UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://inbox")!)
                    }))
                    if let rootVC = (UIApplication.sharedApplication().delegate as? AppDelegate)?.window?.rootViewController {
                        rootVC.presentViewController(alert, animated: true, completion: nil)
                    }
                    defaults.setBool(true, forKey: "helicarrierWarned")
                    defaults.synchronize()
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

class RecipeCell : UITableViewCell {
    @IBOutlet var stack : UIStackView?
    @IBOutlet var plus : UIImageView?
    @IBOutlet var into : UIImageView?
    @IBOutlet var intoResult : UIImageView?
    
    var row : RecipeRow? {
        didSet {
            let stack = self.stack!, plus = self.plus!, into = self.into!, intoResult = self.intoResult!
            
            stack.subviews.forEach { (view) -> () in
                view.removeFromSuperview()
            }
            if let row = row {
                for item in row.items {
                    let itemImageView = UIImageView(frame: CGRectMake(0, 0, 50, 50))
                    item.image(50, completion: { [weak itemImageView] (error, image) -> Void in
                        guard let itemImageView = itemImageView, image = image else { return }
                        dispatch_async(dispatch_get_main_queue(), { [weak itemImageView] () -> Void in
                            guard let itemImageView = itemImageView else { return }
                            itemImageView.image = image
                        })
                    })
                    stack.addArrangedSubview(itemImageView)
                    if item !== row.items.last {
                        let plusCopy = UIImageView(image: plus.image)
                        plusCopy.addConstraint(NSLayoutConstraint(item: plusCopy, attribute: .Width, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 1, constant: plus.frame.size.width))
                        stack.addArrangedSubview(plusCopy)
                    }
                }
                stack.addArrangedSubview(into)
                intoResult.image = nil
                stack.addArrangedSubview(intoResult)
                row.itemType.image(50, completion: { [weak self] (error, image) -> Void in
                    guard let s = self else { return }
                    if s.row !== row { return }
                    if let image = image {
                        dispatch_async(dispatch_get_main_queue(), { [weak s] () -> Void in
                            guard let s = s else { return }
                            if s.row !== row { return }
                            s.intoResult!.image = image
                        })
                    }
                })
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
    
    var scale : CGFloat {
        get {
            return UIScreen.mainScreen().scale
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
                    item.image(50, completion: { [weak self, weak imageView] (error, image) -> Void in
                        guard let s = self, imageView = imageView else { return }
                        if s.row !== row { return }
                        if let error = error {
                            print("Error loading image - \(error)")
                            return
                        }
                        if let image = image {
                            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                imageView.image = image
                            })
                        }
                    })

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
                let size = Int(50 * UIScreen.mainScreen().scale)
                if let url = row.set.imageURL(size) {
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
                let size = Int(50 * UIScreen.mainScreen().scale)
                if let url = row.place.imageURL(size) {
                    setPlaceImage(url)
                }
                label!.text = row.place.name
            }
        }
    }
}