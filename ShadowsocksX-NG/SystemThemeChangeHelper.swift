//
//  SystemThemeChangeHelper.swift
//  Up&Down
//
//  Created by 郭佳哲 on 5/20/16.
//  Copyright © 2016 郭佳哲. All rights reserved.
//

import Foundation

public class SystemThemeChangeHelper {
    
    static func addRespond(target aTarget: AnyObject, selector aSelector: Selector) {
        NSDistributedNotificationCenter.defaultCenter().addObserver(aTarget, selector: aSelector, name: "AppleInterfaceThemeChangedNotification", object: nil)
    }
    
    static func isCurrentDark() -> Bool {
        var result = false
        let dict = NSUserDefaults.standardUserDefaults().persistentDomainForName(NSGlobalDomain)
        if let style:AnyObject = dict!["AppleInterfaceStyle"] {
            if (style as! String).caseInsensitiveCompare("dark") == NSComparisonResult.OrderedSame {
                result = true
            }
        }
        return result
    }
    
}
