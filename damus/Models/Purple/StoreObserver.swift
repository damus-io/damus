//
//  StoreObserver.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-12-08.
//

import Foundation
import StoreKit

class StoreObserver: NSObject, SKPaymentTransactionObserver {
    static let standard = StoreObserver()
    
    var delegate: StoreObserverDelegate?
    
    init(delegate: StoreObserverDelegate? = nil) {
        self.delegate = delegate
        super.init()
    }

    //Observe transaction updates.
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        //Handle transaction states here.
        
        Task {
            await self.delegate?.send_receipt()
        }
    }
}

protocol StoreObserverDelegate {
    func send_receipt() async
}
