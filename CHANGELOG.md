
## [0.1.6] - 2022-10-30

### Added

     - Add lightning tipping button for lud06 profiles
     - Display bolt11 invoice widgets on posts
     - Added inline image loading
     - Show relay connection status in config
     - Search hashtags, profiles, events

### Changed

     - Use an optimized library for image loading

### Fixed

     - Damus will now stay connected at all times


## [0.1.3] - 2022-08-19

### Added

     - Support kind 42 chat messages (ArcadeCity).
     - Added ability to hide replies on home timeline
     - Friend icons next to names on some views. Check is friend. Arrows are friend-of-friends
     - Load chat view first if content contains #chat
     - Cancel button on search box
     - Added profile picture cache
     - Multiline DM messages


### Changed

     - #hashtags now use the `t` tag instead of `hashtag`
     - Clicking a chatroom quote reply will now expand it instead of jumping to it
     - Clicking on a note will now always scroll it to the top
     - Check note ids and signatures on every note
     - use bech32 ids everywhere
     - Don't animate scroll in chat view
     - Post button is not shown if the content is only whitespace


### Fixed

     - Fixed thread loading issue when clicking on boosts
     - Fixed various issues with chatroom view
     - Fix bug where sometimes nested navigation views weren't dismissed when tapping the tab bar
     - Fixed minor carousel spacing issue on homescreen
     - You can now reference users, notes hashtags in DMs
     - Profile pics are now loaded in the background
     - Limit post sizes to max 32,000 as an upper bound sanity limit.
     - Missing profiles are now loaded everywhere
     - No longer parse hashtags in urls
     - Logging out now resets your keypair and actually logs out
     - Copying text in DMs will now copy the decrypted text

[0.1.3]: https://github.com/damus-io/damus/releases/tag/v0.1.3


## [0.1.2] - 2022-07-03

### Added

     - Clicking boost text will go to that users profile
     - Implement NIP04: Encrypted Direct Messages
     - Add blue dot notification to home tab


### Fixed

     - Fixed crash when unfollowing users
     - Clicking tabs now clear blue dots immediately
     - Cancel button on add relay view



[0.1.2]: https://github.com/damus-io/damus/releases/tag/v0.1.2

