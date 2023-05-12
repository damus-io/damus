//
//  AlbyGradient.swift
//  damus
//
//  Created by William Casarin on 2023-05-09.
//

import SwiftUI

fileprivate let alby_grad_c1 = hex_col(r: 226, g: 168, b: 122)
fileprivate let alby_grad_c2 = hex_col(r: 249, g: 223, b: 127)
fileprivate let alby_grad = [alby_grad_c2, alby_grad_c1]

let AlbyGradient: LinearGradient =
    LinearGradient(colors: alby_grad, startPoint: .bottomLeading, endPoint: .topTrailing)
