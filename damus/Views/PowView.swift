//
//  PowView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import Foundation
import SwiftUI

func PowView(_ mpow: Int?) -> some View
{
    let pow = mpow ?? 0
    return Text("\(pow)")
        .font(.callout)
        .foregroundColor(calculate_pow_color(pow))
}

// TODO: make this less saturated on white theme
func calculate_pow_color(_ pow: Int) -> Color
{
    let x = Double(pow) / 30.0;
    return Color(.sRGB, red: 2.0 * (1.0 - x), green: 2.0 * x, blue: 0, opacity: 0.5)
}

