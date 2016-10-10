//
//  SystemThemeChangeHelper.swift
//  Up&Down
//
//  Created by 郭佳哲 on 5/20/16.
//  Copyright © 2016 郭佳哲. All rights reserved.
//

import Foundation

open class SystemThemeChangeHelper {
    
    static func addRespond(target aTarget: AnyObject, selector aSelector: Selector) {
        DistributedNotificationCenter.default().addObserver(aTarget, selector: aSelector, name: NSNotification.Name(rawValue: "AppleInterfaceThemeChangedNotification"), object: nil)
    }
    
    static func isCurrentDark() -> Bool {
        var result = false
        let dict = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let style:AnyObject = dict!["AppleInterfaceStyle"] as AnyObject? {
            if (style as! String).caseInsensitiveCompare("dark") == ComparisonResult.orderedSame {
                result = true
            }
        }
        return result
    }
    
}
