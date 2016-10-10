//
//  ProxyPreferencesController.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/29.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa

class ProxyPreferencesController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    
    var networkServices: NSArray!
    var selectedNetworkServices: NSMutableSet!
    
    var autoConfigureNetworkServices: Bool = true
    
    @IBOutlet var autoConfigCheckBox: NSButton!
    
    @IBOutlet var tableView: NSTableView!

    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        let defaults = UserDefaults.standard
        self.setValue(defaults.bool(forKey: "AutoConfigureNetworkServices"), forKey: "autoConfigureNetworkServices")
        
        if let services = defaults.array(forKey: "Proxy4NetworkServices") {
            selectedNetworkServices = NSMutableSet(array: services)
        } else {
            selectedNetworkServices = NSMutableSet()
        }
        
        networkServices = ProxyConfTool.networkServicesList() as NSArray!
        tableView.reloadData()
    }
    
    @IBAction func ok(_ sender: NSObject){
        ProxyConfHelper.disableProxy("hi")
        
        let defaults = UserDefaults.standard
        defaults.setValue(selectedNetworkServices.allObjects, forKeyPath: "Proxy4NetworkServices")
        defaults.set(autoConfigureNetworkServices, forKey: "AutoConfigureNetworkServices")
        
        defaults.synchronize()
        
        window?.performClose(self)
        
        NotificationCenter.default
            .post(name: Notification.Name(rawValue: NOTIFY_ADV_PROXY_CONF_CHANGED), object: nil)
    }
    
    @IBAction func cancel(_ sender: NSObject){
        window?.performClose(self)
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
        
        let key = (networkServices[row] as AnyObject)["key"] as! String
        if selectedNetworkServices.contains(key) {
            cell.state = 1
        } else {
            cell.state = 0
        }
        let userDefinedName = (networkServices[row] as AnyObject)["userDefinedName"] as! String
        cell.title = userDefinedName
        return cell
    }
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?
        , for tableColumn: NSTableColumn?, row: Int) {
        let key = (networkServices[row] as AnyObject)["key"] as! String
        
//        NSLog("%d", object!.integerValue)
        if (object! as AnyObject).intValue == 1 {
            selectedNetworkServices.add(key)
        } else {
            selectedNetworkServices.remove(key)
        }
    }
}
