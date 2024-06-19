//
//  VectorMath.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-06-17.
//

import Foundation

extension CGPoint {
    /// Summing a vector to a point
    static func +(lhs: CGPoint, rhs: CGVector) -> CGPoint {
        return CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }
    
    /// Subtracting a vector from a point
    static func -(lhs: CGPoint, rhs: CGVector) -> CGPoint {
        return CGPoint(x: lhs.x - rhs.dx, y: lhs.y - rhs.dy)
    }
}

extension CGVector {
    /// Multiplying a vector by a scalar
    static func *(lhs: CGVector, rhs: CGFloat) -> CGVector {
        return CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }
}
