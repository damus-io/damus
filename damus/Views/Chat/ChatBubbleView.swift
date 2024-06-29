//
//  ChatBubbleView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-06-17.
//

import Foundation
import SwiftUI

/// Use this view to display content inside of a custom-designed chat bubble shape.
struct ChatBubble<T: View, U: ShapeStyle, V: View>: View {
    /// The direction at which the chat bubble tip will be pointing towards
    let direction: Direction
    let stroke_content: U
    let stroke_style: StrokeStyle
    let background_style: V
    @ViewBuilder let content: T
    
    // Constants, which are loosely tied to `OFFSET_X` and `OFFSET_Y`
    let OFFSET_X_PADDING: CGFloat = 6
    let OFFSET_Y_BOTTOM_PADDING: CGFloat = 3
    
    var body: some View {
        self.content
            .padding(direction == .left ? .leading : .trailing, OFFSET_X_PADDING)
            .padding(.bottom, OFFSET_Y_BOTTOM_PADDING)
            .background(self.background_style)
            .clipShape(
                BubbleShape(direction: self.direction)
            )
            .overlay(
                BubbleShape(direction: self.direction)
                    .stroke(self.stroke_content, style: self.stroke_style)
            )
            .padding(direction == .left ? .leading : .trailing, -OFFSET_X_PADDING)
            .padding(.bottom, -OFFSET_Y_BOTTOM_PADDING)
    }
    
    enum Direction {
        case right
        case left
    }
    
    struct BubbleShape: Shape {
        /// The direction at which the chat bubble tip will be pointing towards
        let direction: Direction
        
        // MARK: Constant parameters that defines the shape and look of the chat bubbles
        
        /// The corner radius of the round edges
        let CORNER_RADIUS: CGFloat = 10
        /// The height of the chat bubble tip detail
        let DETAIL_HEIGHT: CGFloat = 10
        /// The horizontal distance between the chat bubble tip and the vertical edge of the bubble
        let OFFSET_X: CGFloat = 7
        /// The vertical distance between the chat bubble tip and the bottom edge of the bubble
        let OFFSET_Y: CGFloat = 5
        /// Value between 0 and 1 that determines curvature of the upper chat bubble curve detail
        let DETAIL_CURVE_FACTOR: CGFloat = 0.75
        /// Value between 0 and 1 that determines curvature of the lower chat bubble curve detail
        let LOWER_DETAIL_CURVE_FACTOR: CGFloat = 0.4
        /// The horizontal distance between the chat bubble tip and the point at which the lower chat bubble curve detail attaches to the bottom of the chat bubble
        let LOWER_DETAIL_ATTACHMENT_OFFSET_X: CGFloat = 20
        
        func path(in rect: CGRect) -> Path {
            return self.direction == .left ? self.draw_left_bubble(in: rect) : self.draw_right_bubble(in: rect)
        }
        
        func draw_left_bubble(in rect: CGRect) -> Path {
            return Path { p in
                // Start at the top left, just below the end of the corner radius
                let start = CGPoint(x: OFFSET_X, y: CORNER_RADIUS)
                // Left edge
                p.move(to: start)
                p.addLine(to: CGPoint(x: OFFSET_X, y: rect.height - DETAIL_HEIGHT))
                // Draw the chat bubble tip
                p.addLine(to: CGPoint(x: OFFSET_X, y: rect.height - DETAIL_HEIGHT))
                let tip_of_bubble = CGPoint(x: 0, y: rect.height)
                p.addQuadCurve(
                    to: tip_of_bubble,
                    control: CGPoint(x: 0, y: rect.height - DETAIL_HEIGHT) + CGVector(dx: OFFSET_X, dy: DETAIL_HEIGHT) * DETAIL_CURVE_FACTOR
                )
                let lower_detail_attachment = CGPoint(x: LOWER_DETAIL_ATTACHMENT_OFFSET_X, y: rect.height - OFFSET_Y)
                p.addCurve(
                    to: lower_detail_attachment,
                    control1: tip_of_bubble + CGVector(dx: LOWER_DETAIL_ATTACHMENT_OFFSET_X, dy: 0) * LOWER_DETAIL_CURVE_FACTOR,
                    control2: lower_detail_attachment - CGVector(dx: LOWER_DETAIL_ATTACHMENT_OFFSET_X, dy: 0) * LOWER_DETAIL_CURVE_FACTOR
                )
                // Draw the bottom edge
                p.addLine(to: CGPoint(x: rect.width - CORNER_RADIUS, y: rect.height - OFFSET_Y))
                // Draw the bottom right round corner
                p.addQuadCurve(
                    to: CGPoint(x: rect.width, y: rect.height - OFFSET_Y - CORNER_RADIUS),
                    control: CGPoint(x: rect.width, y: rect.height - OFFSET_Y)
                )
                // Draw right edge
                p.addLine(to: CGPoint(x: rect.width, y: CORNER_RADIUS))
                // Draw top right round corner
                p.addQuadCurve(
                    to: CGPoint(x: rect.width - CORNER_RADIUS, y: 0),
                    control: CGPoint(x: rect.width, y: 0)
                )
                // Draw top edge
                p.addLine(to: CGPoint(x: CORNER_RADIUS + OFFSET_X, y: 0))
                // Draw top left round corner
                p.addQuadCurve(
                    to: start,
                    control: CGPoint(x: OFFSET_X, y: 0)
                )
            }
        }
        
        func draw_right_bubble(in rect: CGRect) -> Path {
            return Path { p in
                // Start at the top right, just below the end of the corner radius
                let right_edge = rect.width - OFFSET_X
                let start = CGPoint(x: right_edge, y: CORNER_RADIUS)
                p.move(to: start)
                // Right edge
                p.addLine(to: CGPoint(x: right_edge, y: rect.height - DETAIL_HEIGHT))
                // Draw the chat bubble tip
                let tip_of_bubble = CGPoint(x: rect.width, y: rect.height)
                p.addQuadCurve(
                    to: tip_of_bubble,
                    control: CGPoint(x: rect.width, y: rect.height - DETAIL_HEIGHT) + CGVector(dx: -OFFSET_X, dy: DETAIL_HEIGHT) * DETAIL_CURVE_FACTOR
                )
                let lower_detail_attachment = CGPoint(x: rect.width - LOWER_DETAIL_ATTACHMENT_OFFSET_X, y: rect.height - OFFSET_Y)
                p.addCurve(
                    to: lower_detail_attachment,
                    control1: tip_of_bubble - CGVector(dx: LOWER_DETAIL_ATTACHMENT_OFFSET_X, dy: 0) * LOWER_DETAIL_CURVE_FACTOR,
                    control2: lower_detail_attachment + CGVector(dx: LOWER_DETAIL_ATTACHMENT_OFFSET_X, dy: 0) * LOWER_DETAIL_CURVE_FACTOR
                )
                // Draw the bottom edge
                p.addLine(to: CGPoint(x: CORNER_RADIUS, y: rect.height - OFFSET_Y))
                // Draw the bottom left round corner
                p.addQuadCurve(
                    to: CGPoint(x: 0, y: rect.height - OFFSET_Y - CORNER_RADIUS),
                    control: CGPoint(x: 0, y: rect.height - OFFSET_Y)
                )
                // Draw left edge
                p.addLine(to: CGPoint(x: 0, y: CORNER_RADIUS))
                // Draw top right round corner
                p.addQuadCurve(
                    to: CGPoint(x: CORNER_RADIUS, y: 0),
                    control: CGPoint(x: 0, y: 0)
                )
                // Draw top edge
                p.addLine(to: CGPoint(x: rect.width - CORNER_RADIUS - OFFSET_X, y: 0))
                // Draw top left round corner
                p.addQuadCurve(
                    to: start,
                    control: CGPoint(x: rect.width - OFFSET_X, y: 0)
                )
            }
        }
    }
}

#Preview {
    VStack {
        ChatBubble(
            direction: .left,
            stroke_content: Color.accentColor.opacity(0),
            stroke_style: .init(lineWidth: 4),
            background_style: Color.accentColor
        ) {
            Text(verbatim: "Hello there")
                .padding()
        }
        .foregroundColor(.white)
        
        ChatBubble(
            direction: .right,
            stroke_content: Color.accentColor.opacity(0),
            stroke_style: .init(lineWidth: 4),
            background_style: Color.accentColor
        ) {
            Text(verbatim: "Hello there")
                .padding()
        }
        .foregroundColor(.white)
    }
}
