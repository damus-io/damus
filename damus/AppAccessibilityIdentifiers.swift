//
//  AppAccessibilityIdentifiers.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-11-18.
//

import Foundation

/// A collection of app-wide identifier constants used to facilitate UI tests to find the element they are looking for.
///
/// ## Implementation notes
///
/// - This is not an exhaustive list. Add more identifiers as needed.
/// - Organize this by separating each category with `MARK` comment markers and a unique prefix, each category separated by 2 empty lines
enum AppAccessibilityIdentifiers: String {
    // MARK: Login
    // Prefix: `sign_in`
    
    /// Sign in button at the very start of the app
    case sign_in_option_button
    /// A secure text entry field where the user can put their private key when logging in
    case sign_in_nsec_key_entry_field
    /// Button to sign in after entering private key
    case sign_in_confirm_button
    
    
    // MARK: Sign Up / Create Account
    // Prefix: `sign_up`
    
    /// Button to navigate to create account view
    case sign_up_option_button
    /// Text field for entering name during account creation
    case sign_up_name_field
    /// Text field for entering bio during account creation
    case sign_up_bio_field
    /// Button to proceed to the next step after entering profile info
    case sign_up_next_button
    /// Button to save keys after account creation
    case sign_up_save_keys_button
    /// Button to skip saving keys
    case sign_up_skip_save_keys_button
    
    
    // MARK: Onboarding
    // Prefix: `onboarding`
    
    /// Any interest option button on the "select your interests" page during onboarding
    case onboarding_interest_option_button
    
    /// The "next" button on the onboarding interest page
    case onboarding_interest_page_next_page
    
    /// The "next" button on the onboarding content settings page
    case onboarding_content_settings_page_next_page
    
    /// The skip button on the onboarding sheet
    case onboarding_sheet_skip_button
    
    
    // MARK: Post composer
    // Prefix: `post_composer`
    
    /// The cancel post button
    case post_composer_cancel_button
    
    // MARK: Main interface layout
    // Prefix: `main`
    
    /// Profile picture item on the top toolbar, used to open the side menu
    case main_side_menu_button
    
    
    // MARK: Side menu
    // Prefix: `side_menu`
    
    /// The profile option in the side menu
    case side_menu_profile_button
    
    /// The logout button in the side menu
    case side_menu_logout_button
    
    /// The logout confirmation button in the alert dialog
    case side_menu_logout_confirm_button
    
    
    // MARK: Items specific to the user's own profile
    // Prefix: `own_profile`
    
    /// The edit profile button
    case own_profile_edit_button
    
    /// The button to edit the banner image on the profile
    case own_profile_banner_image_edit_button
    
    /// The button to pick the new banner image from URL
    case own_profile_banner_image_edit_from_url
}
