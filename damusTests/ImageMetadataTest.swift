//
//  LocationStrippingTest.swift
//  damusTests
//
//  Created by KernelKind on 2/8/24.
//

import XCTest
@testable import damus

final class ImageMetadataTest : XCTestCase {
    func testRemoveGPSData() {
        let bundle = Bundle(for: type(of: self))
        guard let imageURL = bundle.url(forResource: "img_with_location", withExtension: "jpeg"),
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first 
        else {
            XCTFail("Failed to load test image from bundle")
            return
        }

        let testOutputURL = documentsDirectory.appendingPathComponent("img_with_location.jpeg")
        do {
            if FileManager.default.fileExists(atPath: testOutputURL.path) {
                try FileManager.default.removeItem(at: testOutputURL)
            }
            try FileManager.default.copyItem(at: imageURL, to: testOutputURL)
        } catch {
            XCTFail("Setup failed: Unable to copy test image to documents directory - \(error)")
            return
        }

        let removalSuccess = removeGPSDataFromImageAndWrite(fromImageURL: testOutputURL)

        XCTAssertTrue(removalSuccess, "GPS data removal was not successful")

        guard let sourceAfterRemoval = CGImageSourceCreateWithURL(testOutputURL as CFURL, nil),
              let imagePropertiesAfterRemoval = CGImageSourceCopyPropertiesAtIndex(sourceAfterRemoval, 0, nil) as? [String: Any],
              imagePropertiesAfterRemoval[kCGImagePropertyGPSDictionary as String] == nil else {
            XCTFail("GPS data was not removed from the image")
            return
        }
    }
}
