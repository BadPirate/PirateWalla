//
//  TradeMaker.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/31/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit

class TradeMakerTVC: PWTVC {
    let youSection = PWSection(title: "You")
    let themSection = PWSection(title: "Them")
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        // You
        let youUser = StringSettingRow(description: "User ID", defaultKey: settingUserID, defaultValue: "")
        let youHaveFavoriteNumber = ToggleSettingRow(description: "Favorite Number", defaultKey: settingFavoriteNumber, defaultState: false)
        let youCollect = StringSettingRow(description: "Favorite Number", defaultKey: settingCollectID, defaultValue: "1")
        youCollect.keyboardType = .NumberPad
        youCollect.dependentOn.insert(settingFavoriteNumber)
        let youShowFavoriteTrade = ToggleSettingRow(description: "Show favorite trade", defaultKey: settingTradeMakerShowFavoriteTrade, defaultState: false)
        youShowFavoriteTrade.dependentOn.insert(settingFavoriteNumber)
        let youCollectTD = ToggleSettingRow(description: "Collecting TD", defaultKey: settingTradeMakerCollectTD, defaultState: true)
        let youCollectDD = ToggleSettingRow(description: "Collecting DD", defaultKey: settingTradeMakerCollectDD, defaultState: true)
        let youShowMissing = ToggleSettingRow(description: "Show Missing", defaultKey: settingTradeMakerShowMissing, defaultState: true)
        youSection.rows = [youUser,youHaveFavoriteNumber,youShowFavoriteTrade,youCollect,youCollectTD,youCollectDD,youShowMissing]
        
        let themUser = StringSettingRow(description: "User ID", defaultKey: settingTradeMakerThemID, defaultValue: "")
        let themHaveFavorite = ToggleSettingRow(description: "Favorite Number", defaultKey: settingTradeMakerTheyHaveFavorite, defaultState: false)
        let themCollect = StringSettingRow(description: "Favorite Number", defaultKey: settingTradeMakerTheyCollectID, defaultValue: "1")
        let themShowFavoriteTrade = ToggleSettingRow(description: "Show favorite trade", defaultKey: settingTradeMakerShowTheirFavoriteTrade, defaultState: false)
        themShowFavoriteTrade.dependentOn.insert(settingTradeMakerTheyHaveFavorite)
        let themCollectTD = ToggleSettingRow(description: "Collecting TD", defaultKey: settingTradeMakerTheyCollectTD, defaultState: true)
        let themCollectDD = ToggleSettingRow(description: "Collecting DD", defaultKey: settingTradeMakerTheyCollectDD, defaultState: true)
        let themShowMissing = ToggleSettingRow(description: "Show Missing", defaultKey: settingTradeMakerShowTheirMissing, defaultState: true)
        themCollect.keyboardType = .NumberPad
        themCollect.dependentOn.insert(settingTradeMakerTheyHaveFavorite)
        themSection.rows = [themUser,themHaveFavorite,themShowFavoriteTrade,themCollect,themCollectDD,themCollectTD,themShowMissing]
        
        sections = [youSection,themSection]
    }
}
