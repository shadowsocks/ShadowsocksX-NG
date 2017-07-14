//
//  SubscribePreferenceWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 2017/6/15.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Cocoa

class SubscribePreferenceWindowController: NSWindowController {

    @IBOutlet weak var FeedLabel: NSTextField!
    @IBOutlet weak var OKButton: NSButton!

    @IBOutlet weak var FeedTextField: NSTextField!
    @IBOutlet weak var TokenTextField: NSTextField!
    @IBOutlet weak var GroupTextField: NSTextField!
    @IBOutlet weak var MaxCountTextField: NSTextField!
    
    var sbMgr: SubscribeManager!
    var defaults: UserDefaults!
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        // TODO load stored subscribes and prepare the manager
        sbMgr = SubscribeManager.instance
        defaults = UserDefaults.standard
    }
    
    override func awakeFromNib() {
//        profilesTableView.register(forDraggedTypes: [tableViewDragType])
//        profilesTableView.allowsMultipleSelection = true
    }
    
    @IBAction func onOk(_ sender: NSButton) {
        // TODO append to manager and save
        let subscribe = Subscribe.init(initUrlString: FeedTextField.stringValue, initGroupName: GroupTextField.stringValue, initToken: TokenTextField.stringValue, initMaxCount: MaxCountTextField.integerValue)
        if subscribe.feedValidator() {
            _ = sbMgr.addSubscribe(oneSubscribe: subscribe)
        }
        subscribe.updateServerFromFeed()
        window?.performClose(self)
    }
    
    func bindSubscribe(index: Int){
        if index >= 0 && index <= SubscribeManager.instance.subscribes.count {
            var editSubscribe = SubscribeManager.instance.subscribes[index]
            FeedTextField.bind("value", to: editSubscribe, withKeyPath: "subscribeFeed", options:  [NSContinuouslyUpdatesValueBindingOption: true])
        }
    }
    
}
