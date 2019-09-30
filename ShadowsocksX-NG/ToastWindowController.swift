//
//  ToastWindowController.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 2017/3/20.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Cocoa

class ToastWindowController: NSWindowController {
    
    var message: String = ""
    
    @IBOutlet weak var titleTextField: NSTextField!
    @IBOutlet weak var panelView: NSView!
    
    let kHudFadeInDuration: Double = 0.35
    let kHudFadeOutDuration: Double = 0.35
    let kHudDisplayDuration: Double = 1.2

    let kHudAlphaValue: CGFloat = 0.75
    let kHudCornerRadius: CGFloat = 18.0
    let kHudHorizontalMargin: CGFloat = 30
    let kHudHeight: CGFloat = 90.0
    
    var timerToFadeOut: Timer? = nil
    var fadingOut: Bool = false

    override func windowDidLoad() {
        super.windowDidLoad()

        self.shouldCascadeWindows = false

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        if let win = self.window {
            win.isOpaque = false
            win.backgroundColor = .clear
            win.styleMask = NSWindow.StyleMask.borderless
            win.hidesOnDeactivate = false
            win.collectionBehavior = NSWindow.CollectionBehavior.canJoinAllSpaces
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
            win.orderFrontRegardless()
        }

        let viewLayer: CALayer = CALayer()
        viewLayer.backgroundColor = CGColor.init(red: 0.05, green: 0.05, blue: 0.05, alpha: kHudAlphaValue)
        viewLayer.cornerRadius = kHudCornerRadius
        panelView.wantsLayer = true
        panelView.layer = viewLayer
        panelView.layer?.opacity = 0.0
        
        self.titleTextField.stringValue = self.message
        
        setupHud()
    }
    
    func setupHud() -> Void {
        titleTextField.sizeToFit()

        var labelFrame: CGRect = titleTextField.frame
        var hudWindowFrame: CGRect = self.window!.frame
        hudWindowFrame.size.width = labelFrame.size.width + kHudHorizontalMargin * 2
        hudWindowFrame.size.height = kHudHeight

        let screenRect: NSRect = NSScreen.screens[0].visibleFrame
        hudWindowFrame.origin.x = (screenRect.size.width - hudWindowFrame.size.width) / 2
        hudWindowFrame.origin.y = (screenRect.size.height - hudWindowFrame.size.height) / 2
        self.window!.setFrame(hudWindowFrame, display: true)

        var viewFrame: NSRect = hudWindowFrame;
        viewFrame.origin.x = 0
        viewFrame.origin.y = 0
        panelView.frame = viewFrame

        labelFrame.origin.x = kHudHorizontalMargin
        labelFrame.origin.y = (hudWindowFrame.size.height - labelFrame.size.height) / 2
        titleTextField.frame = labelFrame
    }
    
    func fadeInHud() -> Void {
        if timerToFadeOut != nil {
            timerToFadeOut?.invalidate()
            timerToFadeOut = nil
        }

        fadingOut = false

        CATransaction.begin()
        CATransaction.setAnimationDuration(kHudFadeInDuration)
        CATransaction.setCompletionBlock { self.didFadeIn() }
        panelView.layer?.opacity = 1.0
        CATransaction.commit()
    }

    func didFadeIn() -> Void {
        timerToFadeOut = Timer.scheduledTimer(
            timeInterval: kHudDisplayDuration,
            target: self,
            selector: #selector(fadeOutHud),
            userInfo: nil,
            repeats: false)
    }

    @objc func fadeOutHud() -> Void {
        fadingOut = true

        CATransaction.begin()
        CATransaction.setAnimationDuration(kHudFadeOutDuration)
        CATransaction.setCompletionBlock { self.didFadeOut() }
        panelView.layer?.opacity = 0.0
        CATransaction.commit()
    }

    func didFadeOut() -> Void {
        if fadingOut {
            self.window?.orderOut(self)
        }
        fadingOut = false
    }
}
