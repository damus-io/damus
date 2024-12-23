//
//  EditPictureControlTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2024-12-28.
//

import XCTest
import SnapshotTesting
@testable import damus
import SwiftUI

final class EditPictureControlTests: XCTestCase {
    typealias ViewModel = EditPictureControlViewModel<MockImageUploadModel>
    typealias SelectionState = ViewModel.PictureSelectionState
    
    let mock_uploader = MockMediaUploader()
    let mock_url = URL(string: get_test_uploaded_url())!
    let test_image = UIImage(named: "bitcoin-p2p")!
    let mock_keypair = test_keypair
    let mock_pubkey = test_keypair.pubkey
    
    override func setUp() {
        super.setUp()
    }
    
    @MainActor
    func testPFPLibrarySelection() async {
        let expectation = XCTestExpectation(description: "Received URL")
        let view_model = ViewModel(
            context: .profile_picture,
            pubkey: mock_pubkey,
            current_image_url: .constant(mock_url),
            state: .ready,
            keypair: mock_keypair,
            uploader: mock_uploader,
            callback: { url in
                XCTAssertEqual(url, URL(string: get_test_uploaded_url()))
                expectation.fulfill()
            }
        )
        
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        view_model.select_image_from_library()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.selecting_picture_from_library)
        
        view_model.request_upload_authorization(.uiimage(test_image))
        XCTAssertEqual(view_model.state.step, SelectionState.Step.confirming_upload)
        
        view_model.confirm_upload_authorization()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.cropping)
        
        view_model.finished_cropping(croppedImage: test_image.resized(to: CGSize(width: 10, height: 10)))
        XCTAssertEqual(view_model.state.step, SelectionState.Step.uploading)
        
        // Wait to receive URL
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
    }
    
    @MainActor
    func testBannerLibrarySelection() async {
        let expectation = XCTestExpectation(description: "Received URL")
        let view_model = ViewModel(
            context: .normal,
            pubkey: mock_pubkey,
            current_image_url: .constant(mock_url),
            state: .ready,
            keypair: mock_keypair,
            uploader: mock_uploader,
            callback: { url in
                XCTAssertEqual(url, URL(string: get_test_uploaded_url()))
                expectation.fulfill()
            }
        )
        
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        view_model.select_image_from_library()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.selecting_picture_from_library)
        
        let test_image = UIImage(named: "bitcoin-p2p")!
        view_model.request_upload_authorization(.uiimage(test_image))
        XCTAssertEqual(view_model.state.step, SelectionState.Step.confirming_upload)
        
        view_model.confirm_upload_authorization()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.uploading)
        
        // Wait to receive URL
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
    }
    
    @MainActor
    func testPFPCameraSelection() async {
        let expectation = XCTestExpectation(description: "Received URL")
        let view_model = ViewModel(
            context: .profile_picture,
            pubkey: mock_pubkey,
            current_image_url: .constant(mock_url),
            state: .ready,
            keypair: mock_keypair,
            uploader: mock_uploader,
            callback: { url in
                XCTAssertEqual(url, URL(string: get_test_uploaded_url()))
                expectation.fulfill()
            }
        )
        
        // Ready
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        // Take picture
        view_model.select_image_from_camera()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.selecting_picture_from_camera)
        XCTAssertEqual(view_model.state.show_camera, true)
        
        // Confirm upload
        view_model.request_upload_authorization(.uiimage(test_image))
        XCTAssertEqual(view_model.state.step, SelectionState.Step.confirming_upload)
        XCTAssertEqual(view_model.state.is_confirming_upload, true)
        XCTAssertEqual(view_model.state.show_camera, false)
        
        // Confirm and crop
        view_model.confirm_upload_authorization()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.cropping)
        XCTAssertEqual(view_model.state.show_image_cropper, true)
        XCTAssertEqual(view_model.state.is_confirming_upload, false)
        
        // Finish cropping and upload
        view_model.finished_cropping(croppedImage: test_image.resized(to: CGSize(width: 10, height: 10)))
        XCTAssertEqual(view_model.state.step, SelectionState.Step.uploading)
        XCTAssertEqual(view_model.state.show_image_cropper, false)
        
        // Wait to receive URL
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
    }
    
    @MainActor
    func testBannerCameraSelection() async {
        let expectation = XCTestExpectation(description: "Received URL")
        let view_model = ViewModel(
            context: .normal,
            pubkey: mock_pubkey,
            current_image_url: .constant(mock_url),
            state: .ready,
            keypair: mock_keypair,
            uploader: mock_uploader,
            callback: { url in
                XCTAssertEqual(url, URL(string: get_test_uploaded_url()))
                expectation.fulfill()
            }
        )
        
        // Ready
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        // Take picture
        view_model.select_image_from_camera()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.selecting_picture_from_camera)
        XCTAssertEqual(view_model.state.show_camera, true)
        
        // Confirm upload
        view_model.request_upload_authorization(.uiimage(test_image))
        XCTAssertEqual(view_model.state.step, SelectionState.Step.confirming_upload)
        XCTAssertEqual(view_model.state.is_confirming_upload, true)
        XCTAssertEqual(view_model.state.show_camera, false)
        
        // Confirm and upload
        view_model.confirm_upload_authorization()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.uploading)
        XCTAssertEqual(view_model.state.show_image_cropper, false)
        XCTAssertEqual(view_model.state.is_confirming_upload, false)
        
        // Wait to receive URL
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
    }
    
    @MainActor
    func testPFPUrlSelection() async {
        let expectation = XCTestExpectation(description: "Received URL")
        let view_model = ViewModel(
            context: .profile_picture,
            pubkey: mock_pubkey,
            current_image_url: .constant(mock_url),
            state: .ready,
            keypair: mock_keypair,
            uploader: mock_uploader,
            callback: { url in
                if url == self.mock_url {
                    expectation.fulfill()
                }
            }
        )
        
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        view_model.select_image_from_url()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.selecting_picture_from_url)
        
        view_model.choose_url(mock_url)
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        let current_image_url = view_model.current_image_url
        XCTAssertEqual(current_image_url, mock_url)
        
        // Wait to receive URL
        await fulfillment(of: [expectation], timeout: 5)
    }
    
    @MainActor
    func testPFPSelectionWithCancellation() async {
        let expectation = XCTestExpectation(description: "Received URL")
        let view_model = ViewModel(
            context: .profile_picture,
            pubkey: mock_pubkey,
            current_image_url: .constant(mock_url),
            state: .ready,
            keypair: mock_keypair,
            uploader: mock_uploader,
            callback: { url in
                XCTAssertEqual(url, URL(string: get_test_uploaded_url()))
                expectation.fulfill()
            }
        )
        
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        // Open camera
        view_model.select_image_from_camera()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.selecting_picture_from_camera)
        XCTAssertTrue(view_model.show_camera.wrappedValue)
        
        // Dismiss camera
        view_model.show_camera.wrappedValue = false
        XCTAssertFalse(view_model.show_camera.wrappedValue)
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        // Open library
        view_model.select_image_from_library()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.selecting_picture_from_library)
        XCTAssertTrue(view_model.show_library.wrappedValue)
        
        // Dismiss library
        view_model.show_library.wrappedValue = false
        XCTAssertFalse(view_model.show_library.wrappedValue)
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        // Select from URL
        view_model.select_image_from_url()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.selecting_picture_from_url)
        XCTAssertTrue(view_model.show_url_sheet.wrappedValue)
        
        // Dismiss URL sheet
        view_model.show_url_sheet.wrappedValue = false
        XCTAssertFalse(view_model.show_url_sheet.wrappedValue)
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
        
        // Select from library and start cropping
        view_model.select_image_from_library()
        view_model.request_upload_authorization(.uiimage(test_image))
        view_model.confirm_upload_authorization()
        XCTAssertEqual(view_model.state.step, SelectionState.Step.cropping)
        XCTAssertTrue(view_model.show_image_cropper.wrappedValue)
        
        // Cancel during cropping
        view_model.show_image_cropper.wrappedValue = false
        XCTAssertEqual(view_model.state.step, SelectionState.Step.ready)
    }
    
    @MainActor
    func testEditPictureControlFirstTimeSetup() async {
        var current_image_url: URL? = nil
        
        let view_model = EditPictureControl.Model(
            context: .profile_picture,
            pubkey: mock_pubkey,
            current_image_url: Binding(get: { return current_image_url }, set: { current_image_url = $0 }),
            state: .ready,
            keypair: mock_keypair,
            uploader: mock_uploader,
            callback: { url in
                return
            }
        )
        
        // Setup the test view
        let test_view = EditPictureControl(
            model: view_model,
            style: .init(size: 25, first_time_setup: true),
            callback: { url in return }
        )
        let hostView = UIHostingController(rootView: test_view)
        
        sleep(2)    // Wait a bit for things to load
        assertSnapshot(matching: hostView, as: .image(on: .iPhoneSe(.portrait)))
    }
    
    @MainActor
    func testEditPictureControlNotFirstTimeSetup() async {
        var current_image_url: URL? = nil
        
        let view_model = EditPictureControl.Model(
            context: .profile_picture,
            pubkey: mock_pubkey,
            current_image_url: Binding(get: { return current_image_url }, set: { current_image_url = $0 }),
            state: .ready,
            keypair: mock_keypair,
            uploader: mock_uploader,
            callback: { url in
                return
            }
        )
        
        // Setup the test view
        let test_view = EditPictureControl(
            model: view_model,
            style: .init(size: nil, first_time_setup: false),
            callback: { url in return }
        )
        let hostView = UIHostingController(rootView: test_view)
        
        sleep(2)    // Wait a bit for things to load
        assertSnapshot(matching: hostView, as: .image(on: .iPhoneSe(.portrait)))
    }
    
    // MARK: Mock classes
    
    class MockMediaUploader: MediaUploaderProtocol {
        var nameParam: String { return "name_param" }
        var mediaTypeParam: String { return "media_type_param" }
        var supportsVideo: Bool { return true }
        var requiresNip98: Bool { return true }
        var postAPI: String { return "http://localhost:8000" }
        
        func getMediaURL(from data: Data) -> String? {
            return "http://localhost:8000"
        }
        
        func mediaTypeValue(for mediaType: damus.ImageUploadMediaType) -> String? {
            return "media_type_value"
        }
        
        var uploadCalled = false
        var uploadCompletion: (() -> Void)?
    }
    
    class MockImageUploadModel: ImageUploadModelProtocol {
        required init() {}
        
        func start(media: damus.MediaUpload, uploader: any damus.MediaUploaderProtocol, mediaType: damus.ImageUploadMediaType, keypair: damus.Keypair?) async -> damus.ImageUploadResult {
            return damus.ImageUploadResult.success(get_test_uploaded_url())
        }
    }
}

fileprivate func get_test_uploaded_url() -> String {
    return "https://example.com/newimage.jpg"
}

fileprivate extension UIImage {
    static func from(url: URL) throws -> UIImage? {
        let data = try Data(contentsOf: url)
        return UIImage(data: data)
    }
}
