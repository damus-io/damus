## [1.0.0-15] - 2023-02-10

### Added

- Relay Filtering (William Casarin)
- Japanese translations (Terry Yiu)
- Add password autofill on account login and creation (Terry Yiu)
- Show if relay is paid (William Casarin)
- Add "Follows You" indicator on profile (William Casarin)
- Add screen to select individual relays when posting/broadcasting (Andrii Sievrikov)
- Relay Detail View (Joel Klabo)
- Warn when attempting to post an nsec key (Terry Yiu)
- DeepL translation integration (Terry Yiu)
- Use local authentication (faceid) to access private key (Andrii Sievrikov)
- Add accessibility labels to action bar (Bryan Montz)
- Copy invoice button (Joel Klabo)
- Receive Lightning Zaps (William Casarin)
- Allow text selection in bio (Suhail Saqan)


### Changed

- Show "Follow Back" button on profile page (William Casarin)
- When on your profile page, open relay view instead for your own relays (Terry Yiu)
- Updated QR code view, include profile image, etc (ericholguin)
- Clicking relay numbers now goes to relay config (radixrat)

### Fixed

- Load zaps, likes and reposts when you open a thread (William Casarin)
- Fix bug where sidebar navigation fails to pop when switching timelines (William Casarin)
- Use lnaddress before lnurl for tip addresses to avoid Anigma scamming (William Casarin)
- Fix sidebar navigation bugs (OlegAba)
- Fix issue where navigation fails pop to root when switching timelines (William Casarin)
- Make @ mentions case insensitive (William Casarin)
- Fix some lnurls not getting decoded properly (William Casarin)
- Hide incoming DMs from blocked users (William Casarin)
- Hide blocked users from search results (William Casarin)
- Fix Cash App invoice payments (Rob Seward)
- DM Padding (OlegAba)
- Check for broken lnurls (William Casarin)



[1.0.0-15]: https://github.com/damus-io/damus/releases/tag/v1.0.0-15
## [1.0.0-13] - 2023-01-30

### Added

- LibreTranslate note translations (Terry Yiu)
- Added support for account deletion (William Casarin)
- User tagging and autocompletion in posts (Swift)


### Changed

- Remove redundant logout button from settings (Jonathan Milligan)
- Moved relay config to its own sidebar entry (William Casarin)
- New stylized tabs (ericholguin)


### Fixed

- Fix hidden profile action sheet when clicking ... (William Casarin)
- Fixed height of DM input (Terry Yiu)
- Fixed bug where copying pubkey from context menu only copied your own pubkey (Terry Yiu)



[1.0.0-13]: https://github.com/damus-io/damus/releases/tag/v1.0.0-13
## [1.0.0-12] - 2023-01-28

### Added

- Added Arabic and Portuguese translations (Barodane, Antonio Chagas)
- Add QRCode view for sharing your pubkey (ericholguin)
- Added nostr: uri handling (William Casarin)

### Changed

- Remove markdown link support from posts (Joel Klabo)


### Fixed

- Fixed crash on some SVG profile pictures (OlegAba)
- Localization fixes
- Don't allow blocking yourself (Terry)
- Hide muted users from global (William Casarin)
- Fixed profiles sometimes not loading from other clients (William Casarin)
- Fixed bug where `spam` was always the report type (William Casarin)



[1.0.0-12]: https://github.com/damus-io/damus/releases/tag/v1.0.0-12

## [1.0.0-11] - 2023-01-25

### Added

- Reposts view (Terry Yiu)
- Translations for it_IT, it_CH, fr_FR, de_DE, de_AT and lv_LV (Nicolò Carcagnì, Solobalbo, Gregor, Peter Gerstbach, SYX)
- Added ability to block users (William Casarin)
- Added a way to report content (William Casarin)
- Stretchable profile cover header (Swift)


### Changed

- Bump pfp/banner animated fize size limit to 5MiB/20MiB (William Casarin)
- Updated default boostrap relays (Ricardo Arturo Cabral Mejía)


### Fixed

- allow ws:// relays again (Steven Briscoe)



[1.0.0-11]: https://github.com/damus-io/damus/releases/tag/v1.0.0-11


## [1.0.0-8] - 2023-01-22

### Added

- Show website on profiles (William Casarin)
- Add the ability to choose participants when replying (Joel Klabo)
- Translations for de_AT, de_DE, tr_TR, fr_FR (Gregor, Peter Gerstbach, Taylan Benli, Solobalbo)
- Add DM Message Requests (William Casarin)


### Fixed

- Fix commands and emojis getting included in hashtags (William Casarin)
- Fix duplicate post buttons when swiping tabs (Thomas Rademaker)
- Show embedded note references (William Casarin)


[1.0.0-8]: https://github.com/damus-io/damus/releases/tag/v1.0.0-8


## [1.0.0-7] - 2023-01-20

### Added

- Drastically improved image viewer (OlegAba)
- Added pinch to zoom on images (Swift)
- Add Latin American Spanish translations (Nicolás Valencia)
- Added SVG profile picture support (OlegAba)


### Changed

- Makes both name and username clickable in sidebar to go to profile (Zach Hendel)
- Clicking pfp in sidebar opens profile as well (radixrat)
- Don't blur images if your friend boosted it (ericholguin)


### Fixed

- Fix ... when too many likes/reposts (Joel Klabo)
- Don't show report alert if logged in as a pubkey (Swift)
- Fix padding issue at top of home timeline (Ben Weeks)
- Fix absurdly large sidebar on Mac/iPad (John Bethancourt)
- Fix tab views moving after selecting from search result (OlegAba)
- Make follow/unfollow button a consistent width (OlegAba)
- Don't add events to notifications from buggy relays (William Casarin)
- Fixed some crashes with large images (OlegAba)
- Fix DM sorting on incoming messages (William Casarin)
- Fix text getting truncated next to link previews (William Casarin)


[1.0.0-7]: https://github.com/damus-io/damus/releases/tag/v1.0.0-7


## [1.0.0-6] - 2023-01-13

### Added

- Profile banner images (Jason Jōb)
- Added Reactions View (William Casarin)
- Left hand option for post button (Jonathan Milligan)
- Damus icon at the top (Ben Weeks)
- Make purple badges on profile page tappable (Joel Klabo)


### Changed

- Make Shaka button purple when liked (Joel Klabo)
- Move counts to right side like Birdsite (Joel Klabo)
- Use custom icon for shaka button (Joel Klabo)
- Renamed boost to repost (William Casarin)
- Removed nip05 domain from boosts/reposts (William Casarin)
- Make DMs only take up 80% of screen width (Jonathan Milligan)
- Hide Recommended Relays Section if Empty (Joel Klabo)


### Fixed

- Fixed shaka moving when you press it (Joel Klabo)
- Fixed issue with relays not keeping in sync when adding (Fredrik Olofsson)



[1.0.0-6]: https://github.com/damus-io/damus/releases/tag/v1.0.0-6


## [1.0.0-5] - 2023-01-06

### Added

- Added share button to profile (William Casarin)
- Added universal link sharing of notes (William Casarin)
- Added clear cache button to wipe pfp/image cache (OlegAba)
- Allow Adding Relay Without wss:// Prefix (Joel Klabo)
- Allow Saving Images to Library (Joel Klabo)


### Changed

- Added damus gradient to post button (Ben Weeks)
- Center the Post Button (Thomas)
- Switch yellow nip05 check to gray (William Casarin)
- Switch from bluecheck to purplecheck (William Casarin)


### Fixed

- Add system background color to profile pics (OlegAba)
- High res color pubkey on profile page (William Casarin)
- Don't spin forever if we're temporarily disconnected (William Casarin)
- Fixed a few issues with avatars not animating (OlegAba)
- Scroll to bottom when new DM received (Aidan O'Loan)
- Make reply view scrollable (Joel Klabo)
- Hide profile edit button when logged in with pubkey (Swift)


[1.0.0-5]: https://github.com/damus-io/damus/releases/tag/v1.0.0-5

## [1.0.0-4] - 2023-01-04

### Added

- Added NIP05 Verification (William Casarin)
- Downscale images if they are unreasonably large (OlegAba)


### Changed

- Revert to old style ln/dm buttons (William Casarin)


### Fixed

- Fix ascii shrug guy (Lionello Lunesu)
- Fix navigation popping in threads (William Casarin)


[1.0.0-4]: https://github.com/damus-io/damus/releases/tag/v1.0.0-4

## [1.0.0-2] - 2023-01-03

### Added

- Cache link previews (William Casarin)
- Added brb.io to recommended relay list (William Casarin)
- Add Blixt Wallet to Wallet Selector (Benjamin Hakes)
- Add River Wallet to Wallet Selector (Benjamin Hakes)


### Changed

- Added muted shaka images instead of thumbs up (CutClout)
- Updated profile page look and feel (Ben Weeks)
- Filter replies from global feed (Nitesh Balusu)
- Show non-image links inline (William Casarin)
- Add swipe gesture to switch between tabs (Thomas Rademaker)
- Parse links in profiles (Lionello Lunesu) (Lio李歐)


### Fixed

- Fix detection of email addresses in profiles (Lionello Lunesu)
- Fix padding on search results view (OlegAba)
- Fix home view moving after selecting from search result (OlegAba)
- Fix bug where boost event is loaded in the thread instead of the boosted event (William Casarin)
- Hide edit button on profile page when no private key (Swift)
- Fixed follows and relays getting out of sync on profile pages (William Casarin)



[1.0.0-2]: https://github.com/damus-io/damus/releases/tag/v1.0.0-2
## [1.0.0] - 2023-01-01

### Added

- Parse links in profiles (Lionello Lunesu)
- Added Breez wallet to wallet selector (Lee Salminen)
- Added Bitcoin Beach wallet to wallet selector (Lee Salminen)
- Added ability to copy relay urls (Matt Ward)
- Added option to choose default wallet (Suhail Saqan)


### Changed

- Switch like from ❤️  to 🤙 (William Casarin)
- Internationalize relative dates (Terry Yiu)


### Fixed

- Fix but where text was not showing after invoices (William Casarin)
- Load profiles in DMs and notifications (William Casarin)
- Fix expanding profile picture (nosestr bug) (Joel Klabo)
- Fix padding on threads and search results views (OlegAba)
- Don't badge DMs if sent by you (Joel Klabo)
- Reset relay in Add Relay view after adding (Joel Klabo)


[1.0.0]: https://github.com/damus-io/damus/releases/tag/v1.0.0

## [0.1.8-9] - 2022-12-29

### Added

- Relay list on user profiles

### Changed

- Show recommended relays in config. Currently just a fixed set. (William Casarin)
- Ensure contact relay list is kept in sync with internal relay pool (William Casarin)

### Fixed

- Fixed issue where contact list would sometimes revert to an older version (William Casarin)
- Don't show boosts in threads (Thomas)


[0.1.8-9]: https://github.com/damus-io/damus/releases/tag/v0.1.8-9

## [0.1.8-6] - 2022-12-28

### Added

- Lightning wallet selector (Suhail Saqan)
- Cmd-{1,2,3,4} to switch between tabs on MacOS (Jonathan Milligan)
- Shift-Cmd-N to create a post on MacOS (Jonathan Milligan)
- Link Previews! (Sam DuBois)
- Added paste and delete buttons to add relay field (Suhail Saqan)


### Changed

- Blur and opaque non-friend images rather than only display the link (Sam DuBois)
- Remove URLs in content text when image is displayed (Sam DuBois)
- Show non-image URLs as clickable link views (Sam DuBois)
- Adjusted Pay button on invoices. (Sam DuBois)


### Fixed

- Fix crash with @ sign in some posts (Pablo Fernandez)
- Swapped order of Logout and Cancel alert buttons (Terry Yiu)
- Fixed padding issue on tabbar on some devices (Sam DuBois)
- Fix post button moving after selecting from search result (OlegAba)
- Don't show white background on images in dark mode (William Casarin)



[0.1.8-6]: https://github.com/damus-io/damus/releases/tag/v0.1.8-6
## [0.1.8-5] - 2022-12-27

### Added

     - Added the ability to zoom profile pic on profile page


### Changed

     - Improve visual composition of threads
     - Show npub abbreviations instead of old-style hex
     - Added search placeholder and larger cancel button
     - Swap order of Boost and Cancel alert buttons
     - Rename "Copy Note" to "Copy Note JSON"


### Fixed

     - Don't cutoff gifs
     - Fixed bug where booster's names are not displayed



[0.1.8-5]: https://github.com/damus-io/damus/releases/tag/v0.1.8-5
## [0.1.8-4] - 2022-12-26

### Added

     - Long press lightning tip button to copy lnurl


### Changed

     - Only reload global view on pulldown refresh
     - Save privkey in keychain instead of user defaults
     - Also show inline images from friend-of-friends
     - Show rounded corners on inline images


### Fixed

     - Fix bug where typing the first character in the search box defocuses
     - Fixed nip05 identifier format in profile editor
     - Fix profile and event loading in global view
     - Fix lightning tip button sometimes not working
     - Make about me multi-line in profile editor


[0.1.8-4]: https://github.com/damus-io/damus/releases/tag/v0.1.8-4

## [0.1.8-3] - 2022-12-23

### Added

     - Added profile edit view

### Changed

     - Increase like boop intensity
     - Don't auto-load follower count
     - Don't fetch followers right away

### Fixed

     - Fix crash on some bolt11 invoices
     - Fixed issues when refreshing global view


## [0.1.8] - 2022-12-21

### Changed

     - Lots of overall design polish (Sam DuBois)
     - Added loading shimmering effect (Sam DuBois)
     - Show real name next to username in timelines (Sam DuBois)

### Added

     - Animated gif are now shown inline and in profile pictures (@futurepaul)
     - Added ability to copy and share image (@futurepaul)
     - Haptic feedback when liking for that sweet dopamine hit (radixrat)
     - Hide private key in config, make it easier to copy keys (Nitesh Balusu)

### Fixed

     - Disable autocorrection for username when creating account
     - Fixed issues with the post placeholder
     - Disable autocorrection on search
     - Disable autocorrection on add relay field
     - Parse lightning: prefixes on lightning invoice
     - Resize images to fill the space


## [0.1.7] - 2022-12-21

### Changed

     - Only show inline images from your friends
     - Improved look of profile view


### Fixed

     - Added ability to dismiss keyboard during account creation
     - Fixed crashed on lightning invoices with empty descriptions
     - Make dm chat area visible again



[0.1.7]: https://github.com/damus-io/damus/releases/tag/v0.1.7

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

