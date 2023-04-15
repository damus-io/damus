//
//  NavigationUtil.swift
//  damus
//
//  Created by Louis Saberhagen on 15/04/23.
//

import UIKit

public struct NavigationUtil {
    
    static func getNavigationStackSize() -> Int? {
        let navController = getNavigationController()
    
        let navigation_stack_size = navController?.viewControllers.count
        
        return navigation_stack_size
    }
    
    static func getNavigationController() -> UINavigationController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        return findNavigationController(viewController: rootViewController)
        
    }
    
    static func findNavigationController(viewController: UIViewController?) -> UINavigationController? {
        guard let viewController = viewController else {
            return nil
        }
        
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        
        for childViewController in viewController.children {
            return findNavigationController(viewController: childViewController)
        }
        
        return nil
    }
}
