// https://github.com/Tunous/DebouncedOnChange/blob/5670ea13e8ad33e9cc3197f6d13ce492dc0e46ab/Sources/DebouncedOnChange/DebouncedChangeViewModifier.swift

import SwiftUI
import Foundation

extension View {

    /// Adds a modifier for this view that fires an action only when a time interval in seconds represented by
    /// `debounceTime` elapses between value changes.
    ///
    /// Each time the value changes before `debounceTime` passes, the previous action will be cancelled and the next
    /// action /// will be scheduled to run after that time passes again. This mean that the action will only execute
    /// after changes to the value /// stay unmodified for the specified `debounceTime` in seconds.
    ///
    /// - Parameters:
    ///   - value: The value to check against when determining whether to run the closure.
    ///   - debounceTime: The time in seconds to wait after each value change before running `action` closure.
    ///   - action: A closure to run when the value changes.
    /// - Returns: A view that fires an action after debounced time when the specified value changes.
    public func onChange<Value>(
        of value: Value,
        debounceTime: TimeInterval,
        perform action: @escaping (_ newValue: Value) -> Void
    ) -> some View where Value: Equatable {
        self.modifier(DebouncedChangeViewModifier(trigger: value, debounceTime: debounceTime, action: action))
    }
}

private struct DebouncedChangeViewModifier<Value>: ViewModifier where Value: Equatable {
    let trigger: Value
    let debounceTime: TimeInterval
    let action: (Value) -> Void

    @State private var debouncedTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onChange(of: trigger) { value in
            debouncedTask?.cancel()
            debouncedTask = Task.delayed(seconds: debounceTime) { @MainActor in
                action(value)
            }
        }
    }
}

extension Task {

    /// Asynchronously runs the given `operation` in its own task after the specified number of `seconds`.
    ///
    /// The operation will be executed after specified number of `seconds` passes. You can cancel the task earlier
    /// for the operation to be skipped.
    ///
    /// - Parameters:
    ///   - time: Delay time in seconds.
    ///   - operation: The operation to execute.
    /// - Returns: Handle to the task which can be cancelled.
    @discardableResult
    public static func delayed(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) -> Self where Success == Void, Failure == Never {
        Self {
            do {
                try await Task<Never, Never>.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await operation()
            } catch {}
        }
    }
}
