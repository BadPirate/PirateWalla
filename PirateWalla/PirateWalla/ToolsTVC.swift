//
//  ToolsTVC.swift
//  PirateWalla
//
//  Created by Kevin Lohman on 1/24/16.
//  Copyright © 2016 Logic High. All rights reserved.
//

import UIKit

class ToolsTVC : PWTVC {
    let mainSection = PWSection(title: "Tools")
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        // Main Section
        let numberInspector = ToolRow(description: "Issue Number Inspector", segue: "NumberInspector", controller: self)
        let tradeMaker = ToolRow(description: "Trade Maker", segue: "TradeMaker", controller: self)
        mainSection.rows = [numberInspector,tradeMaker]
        sections = [mainSection]
    }
}

class ToolRow : PWRow {
    init(description : String, segue : String, controller : UIViewController)
    {
        super.init()
        setup = { (cell : UITableViewCell, _) in
            cell.textLabel!.text = description
            cell.accessoryType = .DisclosureIndicator
        }
        select = { [weak self] (tableView : UITableView, indexPath) in
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
            controller.performSegueWithIdentifier(segue, sender: self)
        }
    }
}