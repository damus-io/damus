//
//  AutoSaveViewModelTests.swift
//  damusTests
//
//  Created by Daniel D'Aquino on 2025-12-10.
//

import XCTest
@testable import damus

@MainActor
final class AutoSaveViewModelTests: XCTestCase {
    
    func testTimerStartsOnFirstEdit() async throws {
        // Given
        var saveCount = 0
        let viewModel = AutoSaveIndicatorView.AutoSaveViewModel(
            save: { saveCount += 1 },
            saveDelay: 2
        )
        
        // When - user starts typing
        viewModel.needsSaving()
        
        // Then - timer should be started
        if case .needsSaving(let secondsRemaining) = viewModel.savedState {
            XCTAssertEqual(secondsRemaining, 2)
        } else {
            XCTFail("Expected needsSaving state")
        }
    }
    
    func testTimerDoesNotResetOnContinuousTyping() async throws {
        // Given
        var saveCount = 0
        let viewModel = AutoSaveIndicatorView.AutoSaveViewModel(
            save: { saveCount += 1 },
            saveDelay: 3
        )
        
        // When - user starts typing
        viewModel.needsSaving()
        
        // Verify initial state
        if case .needsSaving(let secondsRemaining) = viewModel.savedState {
            XCTAssertEqual(secondsRemaining, 3)
        } else {
            XCTFail("Expected needsSaving state")
        }
        
        // Simulate timer countdown by waiting a bit
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // When - user continues typing (timer should be around 1-2 seconds now)
        viewModel.needsSaving()
        
        // Then - timer should NOT reset to 3 seconds
        if case .needsSaving(let secondsRemaining) = viewModel.savedState {
            XCTAssertLessThan(secondsRemaining, 3, "Timer should not reset on continuous typing")
        } else {
            XCTFail("Expected needsSaving state")
        }
    }
    
    func testTimerRestartsAfterSave() async throws {
        // Given
        var saveCount = 0
        let viewModel = AutoSaveIndicatorView.AutoSaveViewModel(
            save: {
                saveCount += 1
            },
            saveDelay: 1
        )
        
        // When - user starts typing
        viewModel.needsSaving()
        
        // Wait for save to complete
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Then - should have saved
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(viewModel.savedState, .saved)
        
        // When - user types again after save
        viewModel.needsSaving()
        
        // Then - timer should start again
        if case .needsSaving(let secondsRemaining) = viewModel.savedState {
            XCTAssertEqual(secondsRemaining, 1)
        } else {
            XCTFail("Expected needsSaving state after typing post-save")
        }
    }
    
    func testAutoSaveEveryFewSecondsWithContinuousTyping() async throws {
        // Given
        var saveCount = 0
        let viewModel = AutoSaveIndicatorView.AutoSaveViewModel(
            save: {
                saveCount += 1
            },
            saveDelay: 1
        )
        
        // When - user starts typing
        viewModel.needsSaving()
        
        // Simulate continuous typing every 0.5 seconds for 5 seconds
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            viewModel.needsSaving()
        }
        
        // Then - should have saved multiple times
        XCTAssertGreaterThan(saveCount, 1, "Should auto-save multiple times with continuous typing")
    }
}
