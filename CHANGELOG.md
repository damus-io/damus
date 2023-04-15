## [1.4.2-2] - 2023-04-12

### Added

- Include #btc in custom #bitcoin hashtag (William Casarin)
- Make notification dots configurable (William Casarin)


### Changed

- Display follows in most recent to oldest (Luis Cabrera)

### Fixed

- Fix hitches caused by syncronous loading of cached images (William Casarin)
- Fix tabs sometimes not switching (William Casarin)


[1.4.2-2]: https://github.com/damus-io/damus/releases/tag/v1.4.2-2

## [1.4.1-8] - 2023-04-10

### Added

- Add support for nostr: bech32 urls in posts and DMs (NIP19) (Bartholomew Joyce)

### Fixed

- Don't leak mentions in DMs (William Casarin)
- Fix tap area when mentioning users (OlegAba)

[1.4.1-8]: https://github.com/damus-io/damus/releases/tag/v1.4.1-8
## [1.4.1-7] - 2023-04-07

### Added

- Add #zap and #zapathon custom hashtags (William Casarin)
- Add custom #plebchain icon (William Casarin)


### Changed

- Add validation to prevent whitespaces be inputted on NIP-05 input field (Terry Yiu)
- Change reply color from blue to purple. Blue is banned from Damus. (William Casarin)


### Fixed

- Fix padding in post view (OlegAba)
- Show most recently bookmarked notes at the top (Bryan Montz)


[1.4.1-7]: https://github.com/damus-io/damus/releases/tag/v1.4.1-7

## [1.4.1-6] - 2023-04-06

### Added

- Custom hashtags for #bitcoin, #nostr and #coffeechain (William Casarin)

### Changed

- Disable translations in DMs by default (William Casarin)

### Fixed

- Don't show Translating... if we're not actually translating (William Casarin)


[1.4.1-6]: https://github.com/damus-io/damus/releases/tag/v1.4.1-6

## [1.4.1-4] - 2023-04-06

### Added

- Cache translations (William Casarin)

### Fixed

- Fix translation text popping (William Casarin)
- Fix broken auto-translations (William Casarin)
- Fix extraneous padding on some image posts (William Casarin)
- Fix crash in relay list view (William Casarin)

[1.4.1-4]: https://github.com/damus-io/damus/releases/tag/v1.4.1-4

## [1.4.1-3] - 2023-04-05

### Added

- Added text truncation settings (William Casarin)

### Changed

- Rename block to mute (William Casarin)

### Fixed

- Reduce chopping of images (mainvolume)
- Fix some notification settings not saving (William Casarin)
- Fix broken camera uploads (again) (Joel Klabo)


[1.4.1-3]: https://github.com/damus-io/damus/releases/tag/v1.4.1-3

## [1.4.1-2] - 2023-04-04

### Added

- Reply counts (William Casarin)
- Add option to only show notification from people you follow (Swift)
- Added local notifications for other events (Swift)
- Show a custom view when tagged user isn't found (ericholguin)
- Show referenced notes in DMs (William Casarin)


### Changed

- Show full bleed images on selected events in threads (William Casarin)
- Improvement to square image displaying (mainvolume)


### Fixed

- Fix broken website links that have missing https:// prefixes (William Casarin)
- Get around CCP bootstrap relay banning by caching user's relays as their bootstrap relays (William Casarin)


[1.4.1-2]: https://github.com/damus-io/damus/releases/tag/v1.4.1-2

## [1.4.1] - 2023-04-03

### Added

- Profile Picture Upload (Joel Klabo)
- Enable offline posting (William Casarin)
- Add auto-translation caching to ruduce api usage (Terry Yiu)
- Added support for gif uploads (Swift)
- Add a Divider in the Follows List for Large Screens (Joel Klabo)
- Upload Photos and Videos from Camera (Joel Klabo)
- Added ability to lookup users by nip05 identifiers (William Casarin)

### Changed

- Only truncate timeline text if enabled in settings (William Casarin)
- Make mentions wide in notifications like in timeline (William Casarin)
- Broadcast events you are replying to (William Casarin)
- Broadcast now also broadcasts event user's profile (William Casarin)
- Improved look of reply view (ericholguin)
- Remove gradient in some places for visibility (ericholguin)


### Fixed

- Fix cropped images (mainvolume)
- Truncate long text in notification items (William Casarin)
- Restore missing reply description on selected events (William Casarin)
- Show sent DMs immediately (William Casarin)
- Fixed size of translated text (William Casarin)
- Fix crash when reposting (William Casarin)
- Fix unclickable image dismiss button (OlegAba)


[1.4.1]: https://github.com/damus-io/damus/releases/tag/v1.4.1
## [1.4.0] - 2023-03-27

### Added

- Local zap notifications (Swift)
- Add support for video uploads (Swift)
- Auto Translation (Terry Yiu)
- Portuguese (Brazil) translations (Andressa Munturo)
- Spanish (Spain) translations (Max Pleb)
- Vietnamese translations (ShiryoRyo)


### Fixed

- Fixed small notification hit boxes (Terry Yiu)

[1.4.0]: https://github.com/damus-io/damus/releases/tag/v1.4.0

## [1.3.0-7] - 2023-03-24

- New experimental timeline view

[1.3.0-7]: https://github.com/damus-io/damus/releases/tag/v1.3.0-7

## [1.3.0-6] - 2023-03-21

### Fixed

- Fix bug where nostr: links and QRs stopped working (William Casarin)


[1.3.0-6]: https://github.com/damus-io/damus/releases/tag/v1.3.0-6

## [1.3.0-5] - 2023-03-20

### Added

- Add Time Ago to DM View (Joel Klabo)


### Fixed

- Fixed internal links opening in other nostr clients (William Casarin)
- Remove authentication for copying npub (Swift)


[1.3.0-5]: https://github.com/damus-io/damus/releases/tag/v1.3.0-5

## [1.3.0-4] - 2023-03-17

### Changed

- It's much easier to tag users in replies and posts (William Casarin)


### Fixed

- Fix bug where small black text appears during image upload (William Casarin)


[1.3.0-4]: https://github.com/damus-io/damus/releases/tag/v1.3.0-4

## [1.3.0-3] - 2023-03-17

### Fixed

- Fix image upload url delay after progress bar disappears (William Casarin)
- Fix issue where damus stops trying to reconnect (William Casarin)

[1.3.0-3]: https://github.com/damus-io/damus/releases/tag/v1.3.0-3

## [1.3.0-2] - 2023-03-16

### Added

- Add image uploader (Swift)
- Add option to always show images (never blur) (William Casarin)
- Canadian French (Pierre - synoptic_okubo)
- Hungarian translations (Zoltan)
- Korean translations (sogoagain)
- Swedish translations (Pextar)


### Changed

- Fixed embedded note popping (William Casarin)
- Bump notification limit from 100 to 500 (William Casarin)


### Fixed

- Fix zap button preventing scrolling (William Casarin)


[1.3.0-2]: https://github.com/damus-io/damus/releases/tag/v1.3.0-2

## [1.3.0] - 2023-03-15

### Added

- Extend user tagging search to all local profiles (William Casarin)
- Vibrate when a zap is received (Swift)
- New and Improved Share sheet (ericholguin)
- Bulgarian translations (elsat)
- Persian translations (Mahdi Taghizadeh)
- Ukrainian translations (Valeriia Khudiakova, Tony B)


### Changed

- Reduce battery usage by using exp backoff on connections (Bryan Montz)
- Don't show both realname and username if they are the same (William Casarin)
- Show error on invalid lightning tip address (Swift)
- Make DM Content More Visible (Joel Klabo)
- Remove spaces from hashtag searches (gladiusKatana)


### Fixed

- Show @ mentions for users with display_names and no username (William Casarin)
- Make user search case insensitive (William Casarin)
- Fix repost button sometimes not working (OlegAba)
- Don't show follows you for your own profile (benthecarman)
- Fix json appearing in profile searches (gladiusKatana)
- Fix unexpected font size when posting (Bryan Montz)
- Fix keyboard sticking issues (OlegAba)
- Fixed tab bar background color on macOS (Joel Klabo)
- Fix some links getting interpreted as images (gladiusKatana)


[1.3.0]: https://github.com/damus-io/damus/releases/tag/v1.3.0

## [1.2.0-4] - 2023-03-05

### Added

- Add ellipsis button to notes (ericholguin)


### Changed

- Immediately search for events and profiles (William Casarin)
- Use long-press for custom zaps (William Casarin)
- Make shaka animation smoother (Swift)


### Fixed

- Fixed hit detection bugs on profile page (OlegAba)
- Fix disappearing text on Thread view (Bryan Montz)
- Render links in notification summaries (Joel Klabo)
- Don't show notifications from ourselves (William Casarin)
- Fix issue where navbar back button would show the wrong text (Jack Chakany)
- Fix case sensitivity when searching hashtags (randymcmillan)
- Fix issue where opening reposts shows json (William Casarin)


[1.2.0-4]: https://github.com/damus-io/damus/releases/tag/v1.2.0-4

## [1.2.0-3] - 2023-03-04

### Added

- Add additional info to recommended relay view (ericholguin)
- Add shaka animation (Swift)
- Add option to disable image animation (OlegAba)
- Add additional warning when deleting account (ericholguin)
- Threads now load instantly and are cached (William Casarin)


### Fixed

- Wrap long profile display names (OlegAba)
- Fixed weird scaling on profile pictures (OlegAba)
- Fixed width of copy pubkey on profile page (Joel Klabo)
- Make damus purple use more consistent in mentions (Joel Klabo)



[1.2.0-3]: https://github.com/damus-io/damus/releases/tag/v1.2.0-3

## [1.1.0-10] - 2023-03-01

### Added

- Truncate large posts and add a show more button (OlegAba)
- Private Zaps (William Casarin)


### Fixed

- Fix default zap amount setting not getting updated (William Casarin)
- Fix issue where keyboard covers custom zap comment (William Casarin)


[1.1.0-10]: https://github.com/damus-io/damus/releases/tag/v1.1.0-10

## [1.1.0-9] - 2023-02-26

### Added

- Customized zaps (William Casarin)
- Add new Notifications View (William Casarin)
- Bookmarking (Joel Klabo)
- Chinese, Traditional (Hong Kong) translations (rasputin)
- Chinese, Traditional (Taiwan) translations (rasputin)

### Changed

- No more inline npubs when tagging users (Swift)


### Fixed

- Fix alignment of side menu labels (Joel Klabo)
- Fix duplicated participants in reply-to view (Joel Klabo)
- Load missing profiles in Zaps view (William Casarin)
- Fix memory leak with inline videos (William Casarin)
- Eliminate popping when scrolling (William Casarin)


[1.1.0-9]: https://github.com/damus-io/damus/releases/tag/v1.1.0-9

## [1.1.0-3] - 2023-02-20

### Added

- Add a "load more" button instead of always inserting events in timelines (William Casarin)
- Added the ability to select text on posts (OlegAba)
- Added Posts or Post & Replies selector to Profile (ericholguin)
- Improved profile navbar (OlegAba)
- Czech translations (Martin Gabrhel)
- Indonesian translations (johnybergzy)
- Russian translations (Tony B)


### Changed

- Rename global feed to universe (William Casarin)
- Improve look of post view (ericholguin)
- Added a 20MB content length limit for all image files (OlegAba)
- Improved EventActionBar button spacing (Bryan Montz)
- Polished profile key copy buttons, added animation (Bryan Montz)
- Format large numbers of action bar actions (Joel Klabo)
- Improved blur on images, especially in dark mode (Bryan Montz)


### Fixed

- Remove trailing slash when adding a relay (middlingphys)
- Scroll to top of events instead of the bottom (OlegAba)
- Fix lag on startup when you have lots of DMs (William Casarin)
- Fix an issues where dm notifications appear without any new events (William Casarin)
- Fix some hangs when scrolling by images (OlegAba)
- Force default zap amount text field to accept only numbers (Terry Yiu)



[1.1.0-3]: https://github.com/damus-io/damus/releases/tag/v1.1.0-3

## [1.1.0-2] - 2023-02-14

### Added

- Save drafts to posts, replies and DMs (Terry Yiu)

### Fixed

- Ensure stats get updated in realtime on action bars (William Casarin)
- Fix reposts not getting counted properly (William Casarin)
- Fix a bug where zaps on other people's posts weren't showing (William Casarin)
- Fix punctuation getting included in some urls (Gert Goet)
- Improve language detection (Terry Yiu)
- Fix some animated image crashes (William Casarin)


[1.1.0-2]: https://github.com/damus-io/damus/releases/tag/v1.1.0-2
## [1.0.0-15] - 2023-02-10

### Added

- Relay Filtering (William Casarin)
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
- Chinese, Simplified (China mainland) translations (haolong, rasputin)
- Dutch translations (Heimen Stoffels - Vistaus)
- Greek translations (milicode)
- Japanese translations (akiomik, foxytanuki, Guetsu Ren - Nighthaven, h3y6e, middlingphys)


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
- Polish translations (pysiak)


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

- Arabic translations (Barodane)
- Portuguese translations (Antonio Chagas)
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
- Italian translations (Nicolò Carcagnì)
- Latvian translations (SYX)
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
- German translations (Gregor, Peter Gerstbach)
- Turkish translations (Taylan Benli)
- French (France) translations (Solobalbo)
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

