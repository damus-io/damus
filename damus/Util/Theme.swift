//
//  Theme.swift
//  damus
//
//  Created by Ben Weeks on 1/1/23.
//

import Foundation
import UIKit

class Theme {
    static func navigationBarColors(background : UIColor?, titleColor : UIColor? = nil, tintColor : UIColor? = nil) {
        
        let navigationAppearance = UINavigationBarAppearance()
        //navigationAppearance.backBarButtonItem = [.tintColor: .white]
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = background ?? .clear
        
        navigationAppearance.titleTextAttributes = [.foregroundColor: titleColor ?? .black]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: titleColor ?? .black]
       
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        
        UINavigationBar.appearance().tintColor = tintColor ?? titleColor ?? .black
    }
    
    static func barButtonColors(titleColor : UIColor? = nil, shadow: Bool) {
        UIBarButtonItem.appearance().tintColor = titleColor ?? .black
        
        // TO DO: Not yet implemented.
        /*
        let button = UIButton(type: .custom)

        if shadow {
            button.layer.shadowOffset = CGSizeMake(1.5, 1.5);
            button.layer.shadowRadius = 0.5;
            button.layer.shadowOpacity = 1.0;
            //button.layer.shadowColor =  [UIColor blackColor].CGColor;
        }
        
        let customButtom = UIBarButtonItem(customView: button)
         */
    }
}
