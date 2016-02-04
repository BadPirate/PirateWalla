//
//  TradeMakerResultTVC.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/31/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit

enum ItemResultType {
    case Saved, Pouch, Unique, Locked
    func image() -> UIImage {
        switch self {
        case .Pouch:
            return UIImage(named: "pouch")!
        case .Locked:
            return UIImage(named: "locked")!
        case .Saved:
            return UIImage(named: "saved")!
        case .Unique:
            return UIImage(named: "saved")!
        }
    }
}

class TradeGroup {
    var user : SBUser?
    let missingSection : PWSection
    let favoriteSection : PWSection
    let tdSection : PWSection
    let ddSection : PWSection
    let favoriteTrade : PWSection
    var groupItems = [ Int : [ ItemResultType : Set<SBItemBase> ]]()
    let favoriteNumber : Int
    let collectTD : Bool
    let collectDD : Bool
    let showMissing : Bool
    let showFavoriteTrade : Bool
    
    init(you : String, favoriteNumber: Int, collectTD : Bool, collectDD : Bool, showMissing: Bool, showFavoriteTrade: Bool) {
        self.collectTD = collectTD
        self.collectDD = collectDD
        self.favoriteNumber = favoriteNumber
        self.showMissing = showMissing
        self.showFavoriteTrade = showFavoriteTrade
        missingSection = PWSection(title: "\(you) want missing")
        favoriteSection = PWSection(title: "\(you) want favorite #")
        tdSection = PWSection(title: "\(you) want TD")
        ddSection = PWSection(title: "\(you) want DD")
        favoriteTrade = PWSection(title: "\(you) need for favorite trade")
    }
    var sections : [PWSection] {
        get {
            return [favoriteSection,missingSection,tdSection,ddSection,favoriteTrade]
        }
    }
    
    func foundItems(type : ItemResultType, items : Set<SBItemBase>) {
        for item in items {
            if groupItems[item.itemTypeID] == nil {
                groupItems[item.itemTypeID] = [ ItemResultType : Set<SBItemBase> ]()
            }
            if groupItems[item.itemTypeID]![type] == nil {
                groupItems[item.itemTypeID]![type] = Set<SBItemBase>()
            }
            groupItems[item.itemTypeID]![type]!.insert(item)
        }
    }
    
    func combine(tradeGroup : TradeGroup, completion : (error : NSError?, itemTypes: Set<SBItemType>?) -> Void) {
        guard let user = user else { return }
        var missingTypeInfo = Set<Int>()
        for (itemTypeID, groupedItems) in tradeGroup.groupItems {
            for (resultType, items) in groupedItems {
                for item in items {
                    if let haveItemGroup = groupItems[itemTypeID] {
                        // Favorite?
                        if item.number == favoriteNumber {
                            for (haveItemResult, haveItems) in haveItemGroup {
                                for haveItem in haveItems {
                                    let row = TradeRow(fromUser: user, fromType: haveItemResult, fromItem: haveItem, toUser: tradeGroup.user, toType: resultType, toItem: item)
                                    if resultType == .Saved { missingTypeInfo.insert(item.itemTypeID) }
                                    if haveItemResult == .Saved { missingTypeInfo.insert(haveItem.itemTypeID) }
                                    favoriteSection.addPendingRow(row)
                                }
                            }
                            continue
                        }
                        
                        // Determine best number
                        var bestNumber = NSIntegerMax
                        var bestItemType : ItemResultType? = nil
                        var bestItem : SBItemBase? = nil
                        var alreadyFavorite = false
                        for (haveType, haveItems) in haveItemGroup {
                            for haveItem in haveItems {
                                if haveItem.number == favoriteNumber {
                                    alreadyFavorite = true
                                    break
                                }
                                bestNumber = min(haveItem.number,bestNumber)
                                if bestNumber == haveItem.number {
                                    bestItemType = haveType
                                    bestItem = haveItem
                                }
                            }
                            if alreadyFavorite { break }
                        }
                        if alreadyFavorite { continue }
                        
                        // TD / DD?
                        if item.number != tradeGroup.favoriteNumber && (collectTD && item.number < 1000 && bestNumber >= 1000) || (collectDD && item.number < 100 && bestNumber >= 100)
                        {
                            let row = TradeRow(fromUser: user, fromType: bestItemType!, fromItem: bestItem!, toUser: tradeGroup.user, toType: resultType, toItem: item)
                            if resultType == .Saved { missingTypeInfo.insert(item.itemTypeID) }
                            if bestItemType == .Saved { missingTypeInfo.insert(bestItem!.itemTypeID) }
                            if item.number >= 100 {
                                tdSection.addPendingRow(row)
                            }
                            else
                            {
                                ddSection.addPendingRow(row)
                            }
                        }
                        
                        // Favorite Improvement?
                        if showFavoriteTrade && item.number != tradeGroup.favoriteNumber && item.number < favoriteNumber && bestNumber > favoriteNumber {
                            let row = TradeRow(fromUser: user, fromType: bestItemType!, fromItem: bestItem!, toUser: tradeGroup.user, toType: resultType, toItem: item)
                            if resultType == .Saved { missingTypeInfo.insert(item.itemTypeID) }
                            if bestItemType == .Saved { missingTypeInfo.insert(bestItem!.itemTypeID) }
                            favoriteTrade.addPendingRow(row)
                        }
                    }
                    else if showMissing
                    {
                        // Missing
                        let row = TradeRow(fromUser: tradeGroup.user!, fromType: resultType, fromItem: item, toUser: nil, toType: nil, toItem: nil)
                        if resultType == .Saved { missingTypeInfo.insert(item.itemTypeID) }
                        missingSection.addPendingRow(row)
                    }
                }
            }
        }
        if missingTypeInfo.count > 0 {
            sharedCloud.itemTypesWithIdentifiers(missingTypeInfo, completion: { (error, itemTypes) -> Void in
                if let error = error {
                    print("Error parsing - \(error)")
                    completion(error: error, itemTypes: nil)
                    return
                }
                completion(error: error, itemTypes: itemTypes)
            })
        }
        else
        {
            completion(error: nil, itemTypes: nil)
        }
    }
}

class TradeMakerResultTVC: PWTVC {
    let youGroup = TradeGroup(you: "You", favoriteNumber: defaults.boolForKey(settingFavoriteNumber) ? Int(defaults.stringForKey(settingCollectID) ?? "-1") ?? -1 : -1, collectTD: defaults.boolForKey(settingTradeMakerCollectTD), collectDD: defaults.boolForKey(settingTradeMakerCollectDD), showMissing: defaults.boolForKey(settingTradeMakerShowMissing), showFavoriteTrade: defaults.boolForKey(settingTradeMakerShowFavoriteTrade))
    let themGroup = TradeGroup(you: "They", favoriteNumber: defaults.boolForKey(settingTradeMakerTheyHaveFavorite) ? Int(defaults.stringForKey(settingTradeMakerTheyCollectID) ?? "-1") ?? -1 : -1, collectTD: defaults.boolForKey(settingTradeMakerTheyCollectTD), collectDD: defaults.boolForKey(settingTradeMakerTheyCollectDD), showMissing: defaults.boolForKey(settingTradeMakerShowTheirMissing), showFavoriteTrade: defaults.boolForKey(settingTradeMakerShowTheirFavoriteTrade))
    
    var cancelled = false, completedLoad = false
    
    let bee = sharedBee
    let cloud = sharedCloud
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        var sections = youGroup.sections
        sections.appendContentsOf(themGroup.sections)
        self.sections = sections
        
        // Load it up!
        guard let youUserID = defaults.stringForKey(settingUserID), themUserID = defaults.stringForKey(settingTradeMakerThemID) else { return }
        itemRetrieval("your", userID: youUserID, tradeGroup: youGroup)
        itemRetrieval("their", userID: themUserID, tradeGroup: themGroup)
    }
    
    override func didCompleteAllActivities() {
        if cancelled { return }
        if !completedLoad {
            completedLoad = true
            if !NSThread.isMainThread() {
                dispatch_async(dispatch_get_main_queue(), { [weak self] () -> Void in
                    self?.didCompleteAllActivities()
                    })
                return
            }
            animateTableChanges = false
            let parsingYou = "Parsing your items"
            startedActivity(parsingYou)
            youGroup.combine(themGroup, completion: { [weak self] (error, itemTypesYou) -> Void in
                guard let s = self else { return }
                if let error = error {
                    s.errored(error)
                    return;
                }
                s.stoppedActivity(parsingYou)
                let parsingTheir = "Parsing their items"
                s.startedActivity(parsingTheir)
                s.themGroup.combine(s.youGroup, completion: { [weak s] (error, itemTypesThem) -> Void in
                    guard let s = s else { return }
                    if let error = error {
                        s.errored(error)
                        return;
                    }
                    s.stoppedActivity(parsingTheir)
                    for section in s.sections {
                        for row in section.pendingRows {
                            if let row = row as? TradeRow {
                                if row.fromType == .Saved {
                                    if let itemType = s.cloud.itemTypeCache[row.fromItem.itemTypeID] {
                                        row.fromItem = row.fromItem.enhanceWithItemType(itemType)
                                    }
                                }
                                if row.toType == .Saved {
                                    if let itemType = s.cloud.itemTypeCache[row.toItem!.itemTypeID] {
                                        row.toItem = row.toItem!.enhanceWithItemType(itemType)
                                    }
                                }
                            }
                        }
                    }
                    s.shouldUpdateSections()
                })
            })
        }

    }
    
    func errored(error : NSError) {
        if cancelled { return }
        cancelled = true
        AppDelegate.handleError(error, button: "OK", title: "Error", completion: nil)
    }
    
    func itemRetrieval(your : String, userID : String, tradeGroup : TradeGroup) {
        let activity = "Getting \(your) user"

        startedActivity(activity)
        bee.user(userID) { [weak self] (error, user) -> Void in
            guard let s = self else { return }
            if let error = error {
                AppDelegate.handleError(error, button: "OK", title: "Error", completion: nil)
                return
            }
            if let user = user {
                tradeGroup.user = user
                let activity = "Getting \(your) Pouch"
                s.startedActivity(activity)
                user.pouch({ [weak s] (error, items) -> Void in
                    guard let s = s else { return }
                    s.stoppedActivity(activity)
                    if let error = error {
                        s.errored(error)
                        return
                    }
                    if let items = items {
                        tradeGroup.foundItems(.Pouch, items: items)
                    }
                })
                let savedItemsActivity = "Getting \(your) saved items"
                s.startedActivity(savedItemsActivity)
                user.savedItems({ [weak s] (error, savedItems) -> Void in
                    guard let s = s else { return }
                    if let error = error {
                        s.errored(error)
                        return
                    }
                    
                    if let items = savedItems {
                        tradeGroup.foundItems(.Saved, items: items)
                    }
                    s.stoppedActivity(savedItemsActivity)
                })
                let lockedItemsActivity = "Getting \(your) locked items"
                s.startedActivity(lockedItemsActivity)
                user.locked({ [weak s] (error, items) -> Void in
                    guard let s = s else { return }
                    s.stoppedActivity(lockedItemsActivity)
                    if let error = error {
                        // Ignore locked items error
                        print("Locked items error - \(error.code), \(error)")
                        return
                    }
                    if let items = items {
                        tradeGroup.foundItems(.Locked, items: Set(items))
                    }
                })
            }
            s.stoppedActivity(activity)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

class TradeRow : PWRow {
    let fromUser : SBUser
    let fromType : ItemResultType
    var fromItem : SBItemBase
    let toUser : SBUser?
    let toType : ItemResultType?
    var toItem : SBItemBase?
    
    init(fromUser: SBUser, fromType: ItemResultType, fromItem: SBItemBase, toUser: SBUser?, toType: ItemResultType?, toItem: SBItemBase?) {
        self.fromUser = fromUser
        self.fromType = fromType
        self.fromItem = fromItem
        self.toUser = toUser
        self.toType = toType
        self.toItem = toItem
        super.init()
        setup = { [weak self] (cell : UITableViewCell,tableView) in
            guard let s = self else { return }
            if let cell = cell as? PWCell {
                cell.row = s
            }
        }
        select = { (tableView : UITableView, indexPath) in
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            var itemID = fromItem.id
            if let toUser = toUser, userID = defaults.stringForKey(settingUserID), toItem = toItem {
                if toUser.name == userID || toUser.id == Int(userID) {
                    itemID = toItem.id
                }
            }
            UIApplication.sharedApplication().openURL(NSURL(string: "wallabee://items/\(itemID)")!)
        }
        reuse = "trade"
    }
}

class TradeCell : PWCell {
    @IBOutlet var fromUserView : UIImageView?
    @IBOutlet var fromTypeView : UIImageView?
    @IBOutlet var fromItemView : UIImageView?
    @IBOutlet var fromItemLabel : UILabel?
    @IBOutlet var toUserView : UIImageView?
    @IBOutlet var toTypeView : UIImageView?
    @IBOutlet var toItemView : UIImageView?
    @IBOutlet var toItemLabel : UILabel?
    @IBOutlet var transferView : UIImageView?
    
    var toVisible = false {
        didSet {
            dispatch_async(dispatch_get_main_queue()) { [weak self] () -> Void in
                guard let s = self else { return }
                s.toTypeView!.hidden = !s.toVisible
                s.toItemView!.hidden = !s.toVisible
                s.toItemLabel!.hidden = !s.toVisible
                s.toUserView!.hidden = !s.toVisible
                s.transferView!.hidden = !s.toVisible
            }
        }
    }
    
    override var row : PWRow? {
        didSet {
            let size = Int(50*UIScreen.mainScreen().scale)
            let fromUserView = self.fromUserView!, fromTypeView = self.fromTypeView!, fromItemView = self.fromItemView!
            if let row = row as? TradeRow {
                // From User
                fromUserView.image = nil
                row.fromUser.image(size, completion: { [weak self] (error, image) -> Void in
                    guard let s = self else { return }
                    if let error = error {
                        print(error)
                        return
                    }
                    if s.row !== row {
                        return
                    }
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        fromUserView.image = image
                    })
                })
                
                // From Type
                fromTypeView.image = row.fromType.image()
                
                // From Item
                fromItemView.image = nil
                row.fromItem.image(size, completion: { [weak self] (error, image) -> Void in
                    guard let s = self else { return }
                    if let error = error {
                        print(error)
                        return
                    }
                    if s.row !== row {
                        return
                    }
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        fromItemView.image = image
                    })
                })
                
                fromItemLabel!.text = "\(row.fromItem.number)"
                
                if let toUser = row.toUser, toType = row.toType, toItem = row.toItem {
                    toVisible = true
                    // To User
                    let toUserView = self.toUserView!, toTypeView = self.toTypeView!, toItemView = self.toItemView!
                    toUserView.image = nil
                    toUser.image(size, completion: { [weak self] (error, image) -> Void in
                        guard let s = self else { return }
                        if let error = error {
                            print(error)
                            return
                        }
                        if s.row !== row {
                            return
                        }
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            toUserView.image = image
                        })
                    })
                    
                    // To Type
                    toTypeView.image = toType.image()
                    
                    // To Item
                    toItemView.image = nil
                    toItem.image(size, completion: { [weak self] (error, image) -> Void in
                        guard let s = self else { return }
                        if let error = error {
                            print(error)
                            return
                        }
                        if s.row !== row {
                            return
                        }
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            toItemView.image = image
                        })
                    })
                    
                    toItemLabel!.text = "\(toItem.number)"
                }
                else
                {
                    toVisible = false
                }
            }
        }
    }
}
