//
//  StatusItemView.swift
//  Up&Down
//
//  Created by 郭佳哲 on 5/16/16.
//  Copyright © 2016 郭佳哲. All rights reserved.
//

import AppKit
import Foundation

public class StatusItemView: NSControl {
    static let KB:Float = 1024
    static let MB:Float = KB*1024
    static let GB:Float = MB*1024
    static let TB:Float = GB*1024
    
    var fontSize:CGFloat = 9
    var fontColor = NSColor.blackColor()
    var darkMode = false
    var mouseDown = false
    var statusItem:NSStatusItem
    
    var upRate = "- - KB/s"
    var downRate = "- - KB/s"
    var image = NSImage(named: "menu_icon")

    var showSpeed:Bool = false
    
    init(statusItem aStatusItem: NSStatusItem, menu aMenu: NSMenu) {
        statusItem = aStatusItem
        super.init(frame: NSMakeRect(0, 0, statusItem.length, 30))
        menu = aMenu
        menu?.delegate = self
        
        darkMode = SystemThemeChangeHelper.isCurrentDark()
        
        SystemThemeChangeHelper.addRespond(target: self, selector: #selector(changeMode))
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func drawRect(dirtyRect: NSRect) {
        statusItem.drawStatusBarBackgroundInRect(dirtyRect, withHighlight: mouseDown)
        
        fontColor = (darkMode||mouseDown) ? NSColor.whiteColor() : NSColor.blackColor()
        let fontAttributes = [NSFontAttributeName: NSFont.systemFontOfSize(fontSize), NSForegroundColorAttributeName: fontColor]
        if showSpeed{
            let upRateString = NSAttributedString(string: upRate+" ↑", attributes: fontAttributes)
            let upRateRect = upRateString.boundingRectWithSize(NSSize(width: 100, height: 100), options: .UsesLineFragmentOrigin)
            upRateString.drawAtPoint(NSMakePoint(bounds.width - upRateRect.width - 5, 10))

            let downRateString = NSAttributedString(string: downRate+" ↓", attributes: fontAttributes)
            let downRateRect = downRateString.boundingRectWithSize(NSSize(width: 100, height: 100), options: .UsesLineFragmentOrigin)
            downRateString.drawAtPoint(NSMakePoint(bounds.width - downRateRect.width - 5, 0))
        }
        image?.drawAtPoint(NSPoint(x: 0, y: 0), fromRect: NSRect(x: 0, y: 0, width: bounds.height, height: bounds.height), operation: .CompositeSourceOver, fraction: 1.0)
    }
    
    public func setRateData(up up:Float, down: Float) {
        upRate = formatRateData(up)
        downRate = formatRateData(down)
        setNeedsDisplay()
    }
    
    func formatRateData(data:Float) -> String {
        var result:Float
        var unit: String
        
        if data < StatusItemView.KB/100 {
            result = 0
            return "0 KB/s"
        }
            
        else if data < StatusItemView.MB{
            result = data/StatusItemView.KB
            unit = " KB/s"
        }
            
        else if data < StatusItemView.GB {
            result = data/StatusItemView.MB
            unit = " MB/s"
        }
            
        else if data < StatusItemView.TB {
            result = data/StatusItemView.GB
            unit = " GB/s"
        }
            
        else {
            result = 1023
            unit = " GB/s"
        }
        
        if result < 100 {
            return String(format: "%0.2f", result) + unit
        }
        else if result < 999 {
            return String(format: "%0.1f", result) + unit
        }
        else {
            return String(format: "%0.0f", result) + unit
        }
    }
    
    func changeMode() {
        darkMode = SystemThemeChangeHelper.isCurrentDark()
        setNeedsDisplay()
    }
    
    func setIcon(image: NSImage) {
        self.image = image
        setNeedsDisplay()
    }

}

//action
extension StatusItemView: NSMenuDelegate{
    public override func mouseDown(theEvent: NSEvent) {
        statusItem.popUpStatusItemMenu(menu!)
    }
    
    public func menuWillOpen(menu: NSMenu) {
        mouseDown = true
        setNeedsDisplay()
    }
    
    public func menuDidClose(menu: NSMenu) {
        mouseDown = false
        setNeedsDisplay()
    }
}
