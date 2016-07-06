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
        let defaults = NSUserDefaults.standardUserDefaults()
        self.setValue(defaults.boolForKey("AutoConfigureNetworkServices"), forKey: "autoConfigureNetworkServices")
        
        if let services = defaults.arrayForKey("Proxy4NetworkServices") {
            selectedNetworkServices = NSMutableSet(array: services)
        } else {
            selectedNetworkServices = NSMutableSet()
        }
        
        networkServices = ProxyConfTool.networkServicesList()
        tableView.reloadData()
    }
    
    @IBAction func ok(sender: NSObject){
        ProxyConfHelper.disableProxy()
        
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.setValue(selectedNetworkServices.allObjects, forKeyPath: "Proxy4NetworkServices")
        defaults.setBool(autoConfigureNetworkServices, forKey: "AutoConfigureNetworkServices")
        
        defaults.synchronize()
        
        window?.performClose(self)
        
        NSNotificationCenter.defaultCenter()
            .postNotificationName(NOTIFY_ADV_PROXY_CONF_CHANGED, object: nil)
    }
    
    @IBAction func cancel(sender: NSObject){
        window?.performClose(self)
    }
    
    //--------------------------------------------------
    // For NSTableViewDataSource
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        if networkServices != nil {
            return networkServices.count
        }
        return 0;
    }
    
    func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?
        , row: Int) -> AnyObject? {
        let cell = tableColumn!.dataCell as! NSButtonCell
        
        let key = networkServices[row]["key"] as! String
        if selectedNetworkServices.containsObject(key) {
            cell.state = 1
        } else {
            cell.state = 0
        }
        let userDefinedName = networkServices[row]["userDefinedName"] as! String
        cell.title = userDefinedName
        return cell
    }
    
    func tableView(tableView: NSTableView, setObjectValue object: AnyObject?
        , forTableColumn tableColumn: NSTableColumn?, row: Int) {
        let key = networkServices[row]["key"] as! String
        
//        NSLog("%d", object!.integerValue)
        if object!.integerValue == 1 {
            selectedNetworkServices.addObject(key)
        } else {
            selectedNetworkServices.removeObject(key)
        }
    }
}
