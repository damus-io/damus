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
    
    
    // MARK: Onboarding
    // Prefix: `onboarding`
    
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
    
    
    // MARK: Items specific to the user's own profile
    // Prefix: `own_profile`
    
    /// The edit profile button
    case own_profile_edit_button
    
    /// The button to edit the banner image on the profile
    case own_profile_banner_image_edit_button
    
    /// The button to pick the new banner image from URL
    case own_profile_banner_image_edit_from_url
}
