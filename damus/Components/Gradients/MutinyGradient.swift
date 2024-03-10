//
//  MutinyGradient.swift
//  damus
//
//  Created by eric on 3/9/24.
//

import SwiftUI

fileprivate let mutiny_grad_c1 = hex_col(r: 39, g: 95, b: 161)
fileprivate let mutiny_grad_c2 = hex_col(r: 13, g: 33, b: 56)
fileprivate let mutiny_grad = [mutiny_grad_c2, mutiny_grad_c1]

let MutinyGradient: LinearGradient =
    LinearGradient(colors: mutiny_grad, startPoint: .top, endPoint: .bottom)
