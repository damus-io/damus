//
//  ProfileDatabaseTests.swift
//  damusTests
//
//  Created by Bryan Montz on 5/13/23.
//

import XCTest
@testable import damus

class ProfileDatabaseTests: XCTestCase {
    
    static let cache_url = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("test-profiles"))!
    let database = ProfileDatabase(cache_url: ProfileDatabaseTests.cache_url)
    
    override func tearDownWithError() throws {
        // This method is called after the invocation of each test method in the class.
        try database.remove_all_profiles()
    }
    
    var test_profile: Profile {
        Profile(name: "test-name",
                display_name: "test-display-name",
                about: "test-about",
                picture: "test-picture",
                banner: "test-banner",
                website: "test-website",
                lud06: "test-lud06",
                lud16: "test-lud16",
                nip05: "test-nip05",
                damus_donation: 100)
    }

    func testStoreAndRetrieveProfile() async throws {
        let id = "test-id"
        
        let profile = test_profile
        
        // make sure it's not there yet
        XCTAssertNil(database.get(id: id))
        
        // store the profile
        try await database.upsert(id: id, profile: profile, last_update: .now)
        
        // read the profile out of the database
        let retrievedProfile = try XCTUnwrap(database.get(id: id))
        
        XCTAssertEqual(profile.name, retrievedProfile.name)
        XCTAssertEqual(profile.display_name, retrievedProfile.display_name)
        XCTAssertEqual(profile.about, retrievedProfile.about)
        XCTAssertEqual(profile.picture, retrievedProfile.picture)
        XCTAssertEqual(profile.banner, retrievedProfile.banner)
        XCTAssertEqual(profile.website, retrievedProfile.website)
        XCTAssertEqual(profile.lud06, retrievedProfile.lud06)
        XCTAssertEqual(profile.lud16, retrievedProfile.lud16)
        XCTAssertEqual(profile.nip05, retrievedProfile.nip05)
        XCTAssertEqual(profile.damus_donation, retrievedProfile.damus_donation)
    }
    
    func testRejectOutdatedProfile() async throws {
        let id = "test-id"
        
        // store a profile
        let profile = test_profile
        let profile_last_updated = Date.now
        try await database.upsert(id: id, profile: profile, last_update: profile_last_updated)
        
        // try to store a profile with the same id but the last_update date is older than the previously stored profile
        let outdatedProfile = test_profile
        let outdated_last_updated = profile_last_updated.addingTimeInterval(-60)
        
        do {
            try await database.upsert(id: id, profile: outdatedProfile, last_update: outdated_last_updated)
            XCTFail("expected to throw error")
        } catch let error as ProfileDatabaseError {
            XCTAssertEqual(error, ProfileDatabaseError.outdated_input)
        } catch {
            XCTFail("not the expected error")
        }
    }
    
    func testUpdateExistingProfile() async throws {
        let id = "test-id"
        
        // store a profile
        let profile = test_profile
        let profile_last_update = Date.now
        try await database.upsert(id: id, profile: profile, last_update: profile_last_update)
        
        // update the same profile
        let updated_profile = test_profile
        updated_profile.nip05 = "updated-nip05"
        let updated_profile_last_update = profile_last_update.addingTimeInterval(60)
        try await database.upsert(id: id, profile: updated_profile, last_update: updated_profile_last_update)
        
        // retrieve the profile and make sure it was updated
        let retrieved_profile = database.get(id: id)
        XCTAssertEqual(retrieved_profile?.nip05, "updated-nip05")
    }
    
    func testStoreMultipleAndRemoveAllProfiles() async throws {
        XCTAssertEqual(database.count, 0)
        
        // store a profile
        let id = "test-id"
        let profile = test_profile
        let profile_last_update = Date.now
        try await database.upsert(id: id, profile: profile, last_update: profile_last_update)
        
        XCTAssertEqual(database.count, 1)
        
        // store another profile
        let id2 = "test-id-2"
        let profile2 = test_profile
        let profile_last_update2 = Date.now
        try await database.upsert(id: id2, profile: profile2, last_update: profile_last_update2)
        
        XCTAssertEqual(database.count, 2)
        
        try database.remove_all_profiles()
        
        XCTAssertEqual(database.count, 0)
    }
}
