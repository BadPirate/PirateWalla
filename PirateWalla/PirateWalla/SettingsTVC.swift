//
//  SettingsTVC.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/23/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit

let settingSDSearch = "SDSearch"
let settingDDSearch = "DDSearch"
let settingTDSearch = "TDSearch"
let setting1xxxSearch = "1xxxSearch"
let settingSearchNearby = "SearchNearby"
let settingSearchMarket = "SearchMarket"
let settingLimitMarket = "LimitMarket"
let settingMarketLimit = "MarketLimit"
let settingShowImprovements = "ShowImprovements"
let settingSignificantImprovement = "SignificantImprovements"
let settingMinimumImprovement = "MinimumImprovement"
let settingUserID = "UserID"
let settingMixHelper = "MixHelper"
let settingMaxMarketImprovementPrice = "MaxMarketImprovement"
let settingMarketImproveSearch = "SearchMarketImprove"
let settingMarketShowTD = "ShowMarketTD"
let settingCollectID = "CollectID"
let settingFavoriteNumber = "HasFavoriteNumber"

let settingTradeMakerThemID = "TradeMakerThemID"
let settingTradeMakerTheyCollectID = "TradeMakerTheyCollectID"
let settingTradeMakerTheyHaveFavorite = "TradeMakerTheyHaveFavorite"
let settingTradeMakerCollectTD = "TradeMakerCollectTD"
let settingTradeMakerCollectDD = "TradeMakerCollectDD"
let settingTradeMakerCollectUnique = "TradeMakerCollectUnique"

class SettingsTVC : PWTVC {
    let generalSection : PWSection
    let nearbySection : PWSection
    let marketSection : PWSection
    let improvedSection : PWSection
    
    required init?(coder aDecoder: NSCoder) {
        // General
        generalSection = PWSection(title: "General")
        let userSetting = StringSettingRow(description: "User ID", defaultKey: settingUserID, defaultValue: "Not logged in")
        let mixSearch = ToggleSettingRow(description: "Mix Helper", defaultKey: settingMixHelper, defaultState: true)
        let sdSearch = ToggleSettingRow(description: "Single Digit Search", defaultKey: settingSDSearch, defaultState: true)
        let ddSearch = ToggleSettingRow(description: "Double Digit Search", defaultKey: settingDDSearch, defaultState: true)
        let tdSearch = ToggleSettingRow(description: "Triple Digit Search", defaultKey: settingTDSearch, defaultState: true)
        let onexxxSearch = ToggleSettingRow(description: "1xxx Search", defaultKey: setting1xxxSearch, defaultState: false)
        generalSection.rows = [userSetting, mixSearch, sdSearch, ddSearch, tdSearch, onexxxSearch]
        
        // Nearby
        nearbySection = PWSection(title: "Nearby")
        let nearby = ToggleSettingRow(description: "Search Nearby", defaultKey: settingSearchNearby, defaultState: true)
        nearbySection.rows = [nearby]
        
        // Market
        marketSection = PWSection(title: "Market")
        let market = ToggleSettingRow(description: "Search Market", defaultKey: settingSearchMarket, defaultState: true)
        let limitMarket = ToggleSettingRow(description: "Limit Price", defaultKey: settingLimitMarket, defaultState: false)
        limitMarket.dependentOn.insert("SearchMarket")
        let marketLimit = StringSettingRow(description: "Max Missing Price", defaultKey: settingMarketLimit, defaultValue: "5000")
        marketLimit.keyboardType = .NumberPad
        marketLimit.dependentOn.insert(settingLimitMarket)
        marketLimit.dependentOn.insert(settingSearchMarket)
        let searchMarketImprove = ToggleSettingRow(description: "Search Market Improvements", defaultKey: settingMarketImproveSearch, defaultState: true)
        searchMarketImprove.dependentOn.insert(settingSearchMarket)
        let maxImproveLimit = StringSettingRow(description: "Max Improve Price", defaultKey: settingMaxMarketImprovementPrice, defaultValue: "1000")
        maxImproveLimit.dependentOn.insert(settingSearchMarket)
        maxImproveLimit.dependentOn.insert(settingMarketImproveSearch)
        maxImproveLimit.keyboardType = .NumberPad
        let marketTD = ToggleSettingRow(description: "Show SD/DD/TD/1xxx", defaultKey: settingMarketShowTD, defaultState: false)
        marketTD.dependentOn.insert(settingSearchMarket)
        marketSection.rows = [market,limitMarket,marketLimit,searchMarketImprove,maxImproveLimit,marketTD]
        
        // Improved
        improvedSection = PWSection(title: "Improvement")
        let improve = ToggleSettingRow(description: "Show Improvements", defaultKey: settingShowImprovements, defaultState: true)
        let significantImprovement = ToggleSettingRow(description: "Significant Improvement Only", defaultKey: settingSignificantImprovement, defaultState: false)
        significantImprovement.dependentOn.insert(settingShowImprovements)
        let minimumImprovement = StringSettingRow(description: "Minimum Improvement", defaultKey: settingMinimumImprovement, defaultValue: "0")
        minimumImprovement.keyboardType = .NumberPad
        minimumImprovement.dependentOn.insert(settingShowImprovements)
        minimumImprovement.exclusiveOn.insert(settingSignificantImprovement)
        improvedSection.rows = [improve,significantImprovement,minimumImprovement]
        
        super.init(coder: aDecoder)
        sections = [generalSection,nearbySection,marketSection,improvedSection]
    }
}

class SettingsRow : PWRow {
    let defaultKey : String
    let rowDescription : String
    var dependentOn = Set<String>()
    var exclusiveOn = Set<String>()
    var defaultChanged : (value : AnyObject?) -> Void
    var watcher : AnyObject?
    var enabled : Bool = true
    
    init(defaultKey : String, description : String) {
        self.defaultKey = defaultKey
        self.rowDescription = description
        defaultChanged = { _ in }
        super.init()
        watcher = NSNotificationCenter.defaultCenter().addObserverForName(NSUserDefaultsDidChangeNotification, object: nil, queue: nil, usingBlock: { [weak self] (note) -> Void in
            guard let s = self else { return }
            if s.enabled != s.shouldEnable {
                s.enabled = s.shouldEnable
            }
            s.defaultChanged(value: NSUserDefaults.standardUserDefaults().valueForKey(defaultKey))
        })
    }
    
    var shouldEnable : Bool {
        get {
            var shouldEnable = true
            for dependency in dependentOn {
                if defaults.boolForKey(dependency) == false {
                    shouldEnable = false
                    break
                }
            }
            if shouldEnable {
                for exclusive in exclusiveOn {
                    if defaults.boolForKey(exclusive) == true {
                        shouldEnable = false
                        break
                    }
                }
            }
            return shouldEnable
        }
    }
    deinit {
        if let watcher = watcher {
            NSNotificationCenter.defaultCenter().removeObserver(watcher)
        }
    }
    
}

class ToggleSettingRow : SettingsRow {
    let defaultState : Bool
    init(description: String, defaultKey : String, defaultState : Bool) {
        let defaults = NSUserDefaults.standardUserDefaults()
        self.defaultState = defaultState
        super.init(defaultKey: defaultKey, description: description)
        let toggle = UISwitch()
        toggle.addTarget(self, action: "toggled:", forControlEvents: .ValueChanged)
        setup = { [weak self] (cell : UITableViewCell, _) in
            guard let s = self else { return }
            cell.textLabel!.text = description
            cell.accessoryView = toggle
            if defaults.valueForKey(defaultKey) == nil {
                defaults.setBool(defaultState, forKey: defaultKey)
                defaults.synchronize()
            }
            toggle.on = defaults.boolForKey(defaultKey)
            if let cell = cell as? PWCell {
                cell.row = s
            }
            s.enabled = s.shouldEnable
        }
        select = { [weak self] (tableView : UITableView, indexPath : NSIndexPath) in
            guard let s = self else { return }
            if !s.enabled { return }
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            defaults.setBool(!defaults.boolForKey(defaultKey), forKey: defaultKey)
            defaults.synchronize()
        }
        defaultChanged = { [weak toggle] value in
            guard let toggle = toggle else { return }
            if let number = value as? NSNumber {
                let on = number.boolValue
                toggle.setOn(on, animated: true)
            }
        }
    }
    
    override var enabled : Bool {
        didSet {
            guard let cell = cell else { return }
            if let toggle = cell.accessoryView as? UISwitch {
                toggle.enabled = enabled
            }
            cell.textLabel!.enabled = enabled
            cell.selectionStyle = enabled ? .Default : .None
        }
    }
    
    func toggled(sender : AnyObject)
    {
        if let toggle = sender as? UISwitch {
            NSUserDefaults.standardUserDefaults().setBool(toggle.on, forKey: defaultKey)
            NSUserDefaults.standardUserDefaults().synchronize()
        }
    }
}

class StringSettingRow : SettingsRow {
    let defaultValue : String
    var keyboardType = UIKeyboardType.Default
    init(description : String, defaultKey : String, defaultValue : String) {
        self.defaultValue = defaultValue
        super.init(defaultKey: defaultKey, description: description)
        let defaults = NSUserDefaults.standardUserDefaults()
        setup = { [weak self] (cell : UITableViewCell, _) in
            guard let s = self else { return }
            if defaults.stringForKey(defaultKey) == nil {
                defaults.setValue(defaultValue, forKey: defaultKey)
                defaults.synchronize()
            }
            let value = defaults.stringForKey(defaultKey)!
            cell.textLabel!.text = "\(description) - \(value)"
            cell.accessoryView = nil
            cell.accessoryType = .DisclosureIndicator
            if let cell = cell as? PWCell {
                cell.row = s
            }
            s.enabled = s.shouldEnable
        }
        select = { [weak self] (tableView : UITableView, index : NSIndexPath) in
            guard let s = self else { return }
            if !s.enabled { return }
            tableView.deselectRowAtIndexPath(index, animated: true)
            let alert = UIAlertController(title: description, message: nil, preferredStyle: .Alert)
            alert.addTextFieldWithConfigurationHandler({ [weak self] (textField) -> Void in
                guard let s = self else { return }
                textField.text = defaults.stringForKey(defaultKey)
                textField.placeholder = description
                textField.keyboardType = s.keyboardType
            })
            alert.addAction(UIAlertAction(title: "Set", style: .Default, handler: { (_) -> Void in
                defaults.setValue(alert.textFields![0].text, forKey: defaultKey)
                defaults.synchronize()
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
            AppDelegate.presentAlert(alert)
        }
        defaultChanged = { [weak self] value in
            if let value = value as? String, cell = self?.cell {
                dispatch_async(dispatch_get_main_queue(), { [weak cell] () -> Void in
                    guard let cell = cell else { return }
                    let labelText = "\(description) - \(value)"
                    if cell.textLabel!.text != labelText {
                        cell.textLabel!.text = labelText
                        cell.setNeedsLayout()
                    }
                })
            }
        }
    }
    
    override var enabled : Bool {
        didSet {
            guard let cell = cell else { return }
            cell.selectionStyle = enabled ? .Default : .None
            cell.textLabel!.enabled = enabled
        }
    }
}


