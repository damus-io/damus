//
//  AutoSaveIndicatorView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-12.
//
import SwiftUI

/// A small indicator view to indicate whether an item has been saved or not.
///
/// This view uses and observes an `AutoSaveViewModel`.
struct AutoSaveIndicatorView: View {
    @ObservedObject var saveViewModel: AutoSaveViewModel
    
    var body: some View {
        HStack {
            switch saveViewModel.savedState {
            case .needsSaving, .nothingToSave:
                EmptyView()
                    .accessibilityHidden(true)  // Probably no need to show this to users with visual impairment, might be too noisy.
            case .saving:
                HStack(spacing: 6) {
                    ProgressView()
                    Text(NSLocalizedString("Saving draft…", comment: "Text indicating that the draft is currently being saved."))
                        .font(.caption)
                }
                .accessibilityLabel(NSLocalizedString("Saving draft…", comment: "Accessibility label indicating that the draft is currently being saved."))
            case .saved:
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                Text("Saved", comment: "Small label indicating that the user's draft has been saved to storage.")
                    .accessibilityLabel(NSLocalizedString("Your draft has been saved to storage.", comment: "Accessibility label indicating that a user's post draft has been saved, meant to be read by screen reading technology."))
                    .font(.caption)
            }
        }
        .padding(6)
        .foregroundStyle(.secondary)
    }
}


extension AutoSaveIndicatorView {
    /// A simple data structure to model the saving state of an item that can be auto-saved every few seconds.
    enum SaveState: Equatable {
        /// There is nothing to save (e.g. A new empty item was just created, an item was just loaded)
        case nothingToSave
        /// The item has been modified and needs saving.
        /// Saving should occur in N seconds.
        case needsSaving(secondsRemaining: Int)
        /// A saving operation is in progress.
        case saving
        /// The item has been saved to disk.
        case saved
    }
    
    /// Models an auto-save mechanism, which automatically saves an item after N seconds.
    ///
    /// # Implementation notes
    ///
    /// - This runs on the main actor because running this on other actors causes issues with published properties.
    /// - Running on one actor helps ensure thread safety.
    @MainActor
    class AutoSaveViewModel: ObservableObject {
        /// The delay between the time something is marked as needing to save, and the actual saving operation.
        ///
        /// Should be low enough that the user does not lose significant progress, and should be high enough to avoid unnecessary disk writes and jittery, stress-inducing behavior
        let saveDelay: Int
        /// The current state of this model
        @Published private(set) var savedState: SaveState
        /// A timer which counts down the time to save the item
        private var timer: Timer?
        /// The function that performs the actual save operation
        var save: () async -> Void
        
        
        // MARK: Init/de-init
        
        /// Initializes a new auto-save model
        /// - Parameters:
        ///   - save: The function that performs the save operation
        ///   - initialState: Optional initial state
        ///   - saveDelay: The time delay between the item is marked as needing to be saved, and the actual save operation — denoted in seconds.
        init(save: @escaping () async -> Void, initialState: SaveState = .nothingToSave, saveDelay: Int = 3) {
            self.saveDelay = saveDelay
            self.savedState = initialState
            self.save = save
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { timer in
                Task { await self.tick() }  // Task { await ... } ensures the function is properly run on the main actor and avoids thread-safety issues
            })
            self.timer = timer
        }
        
        deinit {
            if let timer = self.timer {
                timer.isValid ? timer.invalidate() : ()
            }
        }
        
        
        // MARK: Internal logic
        
        /// Runs internal countdown-to-save logic
        private func tick() async {
            switch self.savedState {
            case .needsSaving(secondsRemaining: let secondsRemaining):
                if secondsRemaining <= 0 {
                    self.savedState = .saving
                    await save()
                    self.savedState = .saved
                }
                else {
                    self.savedState = .needsSaving(secondsRemaining: secondsRemaining - 1)
                }
            case .saving, .saved, .nothingToSave:
                break
            }
        }
        
        
        // MARK: External interface
        
        /// Marks item as needing to be saved.
        /// Call this whenever your item is modified.
        func needsSaving() {
            self.savedState = .needsSaving(secondsRemaining: self.saveDelay)
        }
        
        /// Marks item as saved.
        /// Call this when you know the item is already saved (e.g. when loading a saved item from memory).
        func markSaved() {
            self.savedState = .saved
        }

        /// Tells the auto-save logic that there is nothing to be saved.
        /// Call this when there is nothing to be saved (e.g. when opening a new empty item).
        func markNothingToSave() {
            self.savedState = .nothingToSave
        }
    }
}
