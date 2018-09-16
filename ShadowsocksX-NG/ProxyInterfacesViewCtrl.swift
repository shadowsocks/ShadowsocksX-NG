//
//  ProxyInterfacesTableViewCtrl.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/3/17.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Cocoa
import RxCocoa
import RxSwift

class ProxyInterfacesViewCtrl: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    var networkServices: NSArray!
    var selectedNetworkServices: NSMutableSet!
    
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var autoConfigCheckBox: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let defaults = UserDefaults.standard
        if let services = defaults.array(forKey: "Proxy4NetworkServices") {
            selectedNetworkServices = NSMutableSet(array: services)
        } else {
            selectedNetworkServices = NSMutableSet()
        }
        
        networkServices = ProxyConfTool.networkServicesList() as NSArray?
        tableView.reloadData()
    }

    //--------------------------------------------------
    // For NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        if networkServices != nil {
            return networkServices.count
        }
        return 0;
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?
        , row: Int) -> Any? {
        let cell = tableColumn!.dataCell as! NSButtonCell
        
        let networkService = networkServices[row] as! [String: Any]
        let key = networkService["key"] as! String
        if selectedNetworkServices.contains(key) {
            cell.state = .on
        } else {
            cell.state = .off
        }
        let userDefinedName = networkService["userDefinedName"] as! String
        cell.title = userDefinedName
        return cell
    }
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?
        , for tableColumn: NSTableColumn?, row: Int) {
        let networkService = networkServices[row] as! [String: Any]
        let key = networkService["key"] as! String
        
//        NSLog("%d", object!.integerValue)
        if (object! as AnyObject).intValue == 1 {
            selectedNetworkServices.add(key)
        } else {
            selectedNetworkServices.remove(key)
        }

        UserDefaults.standard.set(selectedNetworkServices.allObjects,
                                  forKey: "Proxy4NetworkServices")
    }
}
