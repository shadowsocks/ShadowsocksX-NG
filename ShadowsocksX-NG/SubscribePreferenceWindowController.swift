//
//  SubscribePreferenceWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 2017/6/15.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Cocoa

class SubscribePreferenceWindowController: NSWindowController
    , NSTableViewDataSource, NSTableViewDelegate {

    @IBOutlet weak var FeedLabel: NSTextField!
    @IBOutlet weak var OKButton: NSButton!

    @IBOutlet weak var FeedTextField: NSTextField!
    @IBOutlet weak var TokenTextField: NSTextField!
    @IBOutlet weak var GroupTextField: NSTextField!
    @IBOutlet weak var MaxCountTextField: NSTextField!
    @IBOutlet weak var SubscribeTableView: NSTableView!

    @IBOutlet weak var AddSubscribeBtn: NSButton!
    @IBOutlet weak var DeleteSubscribeBtn: NSButton!
    
    var sbMgr: SubscribeManager!
    var defaults: UserDefaults!
    let tableViewDragType: String = "subscribe.host"
    var editingSubscribe: Subscribe!
    
    override func windowDidLoad() {
        super.windowDidLoad()

        sbMgr = SubscribeManager.instance
        defaults = UserDefaults.standard
        SubscribeTableView.reloadData()
        updateSubscribeBoxVisible()
    }
    
    override func awakeFromNib() {
        SubscribeTableView.register(forDraggedTypes: [tableViewDragType])
        SubscribeTableView.allowsMultipleSelection = true
    }
    
    @IBAction func onOk(_ sender: NSButton) {
        if editingSubscribe != nil {
            if !editingSubscribe.feedValidator() {
                // Done Shake window
                shakeWindows()
                return
            }
        }
        sbMgr.save()
        window?.performClose(self)
    }
    
    @IBAction func onAdd(_ sender: NSButton) {
        if editingSubscribe != nil && !editingSubscribe.feedValidator(){
            shakeWindows()
            return
        }
        SubscribeTableView.beginUpdates()
        let subscribe = Subscribe(initUrlString: "", initGroupName: "", initToken: "", initMaxCount: -1)
        sbMgr.subscribes.append(subscribe)
        
        let index = IndexSet(integer: sbMgr.subscribes.count-1)
        SubscribeTableView.insertRows(at: index, withAnimation: .effectFade)
        
        self.SubscribeTableView.scrollRowToVisible(self.sbMgr.subscribes.count-1)
        self.SubscribeTableView.selectRowIndexes(index, byExtendingSelection: false)
        SubscribeTableView.endUpdates()
        updateSubscribeBoxVisible()
    }
    
    @IBAction func onDelete(_ sender: NSButton) {
        let index = Int(SubscribeTableView.selectedRowIndexes.first!)
        var deleteCount = 0
        if index >= 0 {
            SubscribeTableView.beginUpdates()
            for (_, toDeleteIndex) in SubscribeTableView.selectedRowIndexes.enumerated() {
                _ = sbMgr.deleteSubscribe(atIndex: toDeleteIndex - deleteCount)
                SubscribeTableView.removeRows(at: IndexSet(integer: toDeleteIndex - deleteCount), withAnimation: .effectFade)
                deleteCount += 1
                if sbMgr.subscribes.count == 0 {
                    cleanField()
                }
            }
            SubscribeTableView.endUpdates()
        }
        self.SubscribeTableView.scrollRowToVisible(index - 1)
        self.SubscribeTableView.selectRowIndexes(IndexSet(integer: index - 1), byExtendingSelection: false)
        updateSubscribeBoxVisible()
    }
    
    func updateSubscribeBoxVisible() {
        if sbMgr.subscribes.count <= 0 {
            DeleteSubscribeBtn.isEnabled = false
            FeedTextField.isEnabled = false
            TokenTextField.isEnabled = false
            GroupTextField.isEnabled = false
            MaxCountTextField.isEnabled = false
        }else{
            DeleteSubscribeBtn.isEnabled = true
            FeedTextField.isEnabled = true
            TokenTextField.isEnabled = true
            GroupTextField.isEnabled = true
            MaxCountTextField.isEnabled = true
        }
    }
    
    func bindSubscribe(_ index:Int) {
        if index >= 0 && index < sbMgr.subscribes.count {
            editingSubscribe = sbMgr.subscribes[index]
            
            FeedTextField.bind("value", to: editingSubscribe, withKeyPath: "subscribeFeed", options: [NSContinuouslyUpdatesValueBindingOption: true])
            TokenTextField.bind("value", to: editingSubscribe, withKeyPath: "token", options: [NSContinuouslyUpdatesValueBindingOption: true])
            GroupTextField.bind("value", to: editingSubscribe, withKeyPath: "groupName", options: [NSContinuouslyUpdatesValueBindingOption: true])
            MaxCountTextField.bind("value", to: editingSubscribe, withKeyPath: "maxCount", options: [NSContinuouslyUpdatesValueBindingOption: true])
            
        } else {
            editingSubscribe = nil
            FeedTextField.unbind("value")
            TokenTextField.unbind("value")
            GroupTextField.unbind("value")
            MaxCountTextField.unbind("value")
        }
    }
    
    func getDataAtRow(_ index:Int) -> String {
        if sbMgr.subscribes[index].groupName != "" {
            return sbMgr.subscribes[index].groupName
        }
        return sbMgr.subscribes[index].subscribeFeed
    }
    
    // MARK: For NSTableViewDataSource
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if let mgr = sbMgr {
            return mgr.subscribes.count
        }
        return 0
    }
    
    func tableView(_ tableView: NSTableView
        , objectValueFor tableColumn: NSTableColumn?
        , row: Int) -> Any? {
        
        let title = getDataAtRow(row)
        
        if tableColumn?.identifier == "main" {
            if title != "" {return title}
            else {return "S"}
        } else if tableColumn?.identifier == "status" {
            return NSImage(named: "menu_icon")
        }
        return ""
    }
    
    // MARK: Drag & Drop reorder rows
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: tableViewDragType)
        return item
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int
        , proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return NSDragOperation()
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo
        , row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
        if let mgr = sbMgr {
            var oldIndexes = [Int]()
            info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) {
                if let str = ($0.0.item as! NSPasteboardItem).string(forType: self.tableViewDragType), let index = Int(str) {
                    oldIndexes.append(index)
                }
            }
            
            var oldIndexOffset = 0
            var newIndexOffset = 0
            
            // For simplicity, the code below uses `tableView.moveRowAtIndex` to move rows around directly.
            // You may want to move rows in your content array and then call `tableView.reloadData()` instead.
            tableView.beginUpdates()
            for oldIndex in oldIndexes {
                if oldIndex < row {
                    let o = mgr.subscribes.remove(at: oldIndex + oldIndexOffset)
                    mgr.subscribes.insert(o, at:row - 1)
                    tableView.moveRow(at: oldIndex + oldIndexOffset, to: row - 1)
                    oldIndexOffset -= 1
                } else {
                    let o = mgr.subscribes.remove(at: oldIndex)
                    mgr.subscribes.insert(o, at:row + newIndexOffset)
                    tableView.moveRow(at: oldIndex, to: row + newIndexOffset)
                    newIndexOffset += 1
                }
            }
            tableView.endUpdates()
            
            return true
        }
        return false
    }
    
    //--------------------------------------------------
    // For NSTableViewDelegate
    
    func tableView(_ tableView: NSTableView
        , shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if row < 0 {
            editingSubscribe = nil
            return true
        }
//        if editingSubscribe != nil {
//            if !editingSubscribe.isValid() {
//                return false
//            }
//        }
        
        return true
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if SubscribeTableView.selectedRow >= 0 {
            bindSubscribe(SubscribeTableView.selectedRow)
            if (SubscribeTableView.selectedRowIndexes.count > 1){
//                duplicateProfileButton.isEnabled = false
            } else {
//                duplicateProfileButton.isEnabled = true
            }
        } else {
            if !sbMgr.subscribes.isEmpty {
                let index = IndexSet(integer: sbMgr.subscribes.count - 1)
                SubscribeTableView.selectRowIndexes(index, byExtendingSelection: false)
            }
        }
    }
    
    func cleanField(){
        FeedTextField.stringValue = ""
        TokenTextField.stringValue = ""
        GroupTextField.stringValue = ""
        MaxCountTextField.stringValue = ""
    }
    
    func shakeWindows(){
        let numberOfShakes:Int = 8
        let durationOfShake:Float = 0.5
        let vigourOfShake:Float = 0.05
        
        let frame:CGRect = (window?.frame)!
        let shakeAnimation = CAKeyframeAnimation()
        
        let shakePath = CGMutablePath()
        
        shakePath.move(to: CGPoint(x:NSMinX(frame), y:NSMinY(frame)))
        
        for _ in 1...numberOfShakes{
            shakePath.addLine(to: CGPoint(x: NSMinX(frame) - frame.size.width * CGFloat(vigourOfShake), y: NSMinY(frame)))
            shakePath.addLine(to: CGPoint(x: NSMinX(frame) + frame.size.width * CGFloat(vigourOfShake), y: NSMinY(frame)))
        }
        
        shakePath.closeSubpath()
        shakeAnimation.path = shakePath
        shakeAnimation.duration = CFTimeInterval(durationOfShake)
        window?.animations = ["frameOrigin":shakeAnimation]
        window?.animator().setFrameOrigin(window!.frame.origin)
    }
}
