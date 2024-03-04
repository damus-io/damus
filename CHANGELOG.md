## [1.7-rc2] - 2024-02-28

### Added

- Add support for Apple In-App purchases (Daniel D’Aquino)
- Notification reminders for Damus Purple impending expiration (Daniel D’Aquino)
- Damus Purple membership! (William Casarin)
- Fixed minor spacing and padding issues in onboarding views (ericholguin)


### Changed

- Disable inline text suggestions on 17.0 as they interfere with mention generation (William Casarin)
- EULA is not shown by default (ericholguin)


### Fixed

- Fix welcome screen not showing if the user enters the app directly after a successful checkout without going through the link (Daniel D’Aquino)
- Fix profile not updating bug (William Casarin)
- Fix nostrscripts not loading (William Casarin)
- Fix crash when accessing cached purple accounts (William Casarin)
- Hide member signup date on reposts (kernelkind)
- Fixed previews not rendering (ericholguin)
- Fix load media formatting on small screens (kernelkind)
- Fix shared nevents that are too long (kernelkind)
- Fix many nostrdb transaction related crashes (William Casarin)


### Removed

- Removed copying public key action (ericholguin)



[1.7-rc2]: https://github.com/damus-io/damus/releases/tag/v1.7-rc2

## [1.7-2] - 2024-01-24

### Added

- New fulltext search engine (William Casarin)

- Add "Always show onboarding suggestions" developer setting (Daniel D’Aquino)
- Add NIP-42 relay auth support (Charlie Fish)
- Add ability to hide suggested hashtags (ericholguin)
- Add ability to mute hashtag from SearchView (Charlie Fish)
- Add ability to preview media taken with camera (Suhail Saqan)
- Add ability to search for naddr, nprofiles, nevents (kernelkind)
- Add experimental push notification support (Daniel D’Aquino)
- Add naddr link support (kernelkind)
- Add regional relay recommendations to Relay configuration view (currently for Japanese users only) (Daniel D’Aquino)
- Add regional relays for Germany (Daniel D’Aquino)
- Add regional relays for Thailand (Daniel D’Aquino)
- Added a custom camera view (Suhail Saqan)
- Always convert damus.io links to inline mentions (William Casarin)
- Unfurl profile name on remote push notifications (Daniel D’Aquino)
- Zap notification support for push notifications (Daniel D’Aquino)


### Changed

- Generate nprofile/nevent links in share menus (kernelkind)
- Improve push notification support to match local notification support (Daniel D’Aquino)
- Move mute thread in menu so it's not clicked by accident (alltheseas)
- Prioritize friends when autocompleting (Charlie Fish)


### Fixed

- Add workaround to fix note language recognition and reduce wasteful translation requests (Terry Yiu)
- Allow mentioning users with punctuation characters in their names (kernelkind)
- Fix broken mentions when there is text is directly after (kernelkind)
- Fix crash on very large notes (Daniel D’Aquino)
- Fix crash when logging out and switching accounts (William Casarin)
- Fix duplicate notes getting written to nostrdb (William Casarin)
- Fix issue where adding relays might not work on corrupted contact lists (Charlie Fish)
- Fix onboarding post view not being dismissed under certain conditions (Daniel D’Aquino)
- Fix performance issue with gifs (William Casarin)
- Fix persistent local notifications even after logout (William Casarin)
- Fixed bug where sometimes notes from other profiles appear on profile pages (Charlie Fish)
- Remove extra space at the end of DM messages (kernelkind)
- Save current viewed image index when switching to fullscreen (kernelkind)


### Removed

- Removed old nsec key warning, nsec automatically convert to npub when posting (kernelkind)



[1.7-2]: https://github.com/damus-io/damus/releases/tag/v1.7-2
## [1.6-25] - 2023-10-31

### Added

- Tap to dismiss keyboard on user status view (ericholguin)
- Add setting that allows users to optionally disable the new profile action sheet feature (Daniel D’Aquino)
- Add follow button to profile action sheet (Daniel D’Aquino)
- Added reaction counters to nostrdb (William Casarin)
- Record when profile is last fetched in nostrdb (William Casarin)


### Changed

- Automatically load extra regional Japanese relays during account creation if user's region is set to Japan. (Daniel D’Aquino)
- Updated customize zap view (ericholguin)
- Users are now notified when you quote repost them (William Casarin)
- Save bandwidth by only fetching new profiles after a certain amount of time (William Casarin)
- Zap button on profile action sheet now zaps with a single click, while a long press brings custom zap view (Daniel D’Aquino)


### Fixed

- Use white font color in qrcode view (ericholguin)
- Fixed an issue where zapping would silently fail on default settings if the user does not have a lightning wallet preinstalled on their device. (Daniel D’Aquino)


[1.6-25]: https://github.com/damus-io/damus/releases/tag/v1.6-25
## [1.6-24] - 2023-10-22 - AppStore Rejection Cope

### Added

- Improve discoverability of profile zaps with zappability badges and profile action sheets (Daniel D’Aquino)
- Add suggested hashtags to universe view (Daniel D’Aquino)
- Suggest first post during onboarding (Daniel D’Aquino)
- Add expiry date for images in cache to be auto-deleted after a preset time to save space on storage (Daniel D’Aquino)
- Add QR scan nsec logins. (Jericho Hasselbush)


### Changed

- Improved status view design (ericholguin)
- Improve clear cache functionality (Daniel D’Aquino)


### Fixed

- Reduce size of event menu hitbox (William Casarin)
- Do not show DMs from muted users (Daniel D’Aquino)
- Add more spacing between display name and username, and prefix username with `@` character (Daniel D’Aquino)
- Broadcast quoted notes when posting a note with quotes (Daniel D’Aquino)


[1.6-24]: https://github.com/damus-io/damus/releases/tag/v1.6-24

## [1.6-23] - 2023-10-06 - Appstore Release

### Added

- Added merch store button to sidebar menu (Daniel D’Aquino)

### Changed

- Damus icon now opens sidebar (Daniel D’Aquino)

### Fixed

- Stop tab buttons from causing the root view to scroll to the top unless user is coming from another tab or already at the root view (Daniel D’Aquino)
- Fix profiles not updating (William Casarin)
- Fix issue where relays with trailing slashes cannot be removed (#1531) (Daniel D’Aquino)


[1.6-23]: https://github.com/damus-io/damus/releases/tag/v1.6-23

## [1.6-20] - 2023-10-04

### Changed

- Improve UX around clearing cache (Daniel D’Aquino)
- Show muted thread replies at the bottom of the thread view (#1522) (Daniel D’Aquino)

### Fixed

- Fix situations where the note composer cursor gets stuck in one place after tagging a user (Daniel D’Aquino)
- Fix some note composer issues, such as when copying/pasting larger text, and make the post composer more robust. (Daniel D’Aquino)
- Apply filters to hashtag search timeline view (Daniel D’Aquino)
- Hide quoted or reposted notes from people whom the user has muted. (#1216) (Daniel D’Aquino)
- Fix profile not updating (William Casarin)
- Fix small graphical toolbar bug when scrolling profiles (Daniel D’Aquino)
- Fix localization issues and export strings for translation (Terry Yiu)


[1.6-20]: https://github.com/damus-io/damus/releases/tag/v1.6-20

## [1.6-18] - 2023-09-21

### Added

- Add followed hashtags to your following list (Daniel D’Aquino)
- Add "Do not show #nsfw tagged posts" setting (Daniel D’Aquino)
- Hold tap to preview status URL (Jericho Hasselbush)
- Finnish translations (etrikaj)


### Changed

- Switch to nostrdb for @'s and user search (William Casarin)
- Use nostrdb for profiles (William Casarin)
- Updated relay view (ericholguin)
- Increase size of the hitbox on note ellipsis button (Daniel D’Aquino)
- Make carousel tab dots tappable (Bryan Montz)
- Move the "Follow you" badge into the profile header (Grimless)


### Fixed

- Fix text composer wrapping issue when mentioning npub (Daniel D’Aquino)
- Make blurred videos viewable by allowing blur to disappear once tapped (Daniel D’Aquino)
- Fix parsing issue with NIP-47 compliant NWC urls without double-slashes (Daniel D’Aquino)
- Fix padding of username next to pfp on some views (William Casarin)
- Fixes issue where username with multiple emojis would place cursor in strange position. (Jericho Hasselbush)
- Fixed audio in video playing twice (Bryan Montz)
- Fix crash when long pressing custom reactions (William Casarin)
- Fix random crashom due to old profile database (William Casarin)

[1.6-18]: https://github.com/damus-io/damus/releases/tag/v1.6-18

## [1.6-17] - 2023-08-23

### Added

- Add support for status URLs (William Casarin)
- Click music statuses to display in spotify (William Casarin)
- Add settings for disabling user statuses (William Casarin)

### Changed

- clear statuses if they only contain whitespace (William Casarin)

### Fixed

- Fix long status lines (William Casarin)
- Fix status events not expiring locally (William Casarin)

[1.6-17]: https://github.com/damus-io/damus/releases/tag/v1.6-17

## [1.6-16] - 2023-08-23

### Added

- Added live music statuses (William Casarin)
- Added generic user statuses (William Casarin)

### Fixed

- Avoid notification for zaps from muted profiles (tappu75e@duck.com)
- Fix text editing issues on characters added right after mention link (Daniel D’Aquino)
- Mute hellthreads everywhere (William Casarin)


[1.6-16]: https://github.com/damus-io/damus/releases/tag/v1.6-16

## [1.6-13] - 2023-08-18

### Fixed

- Fix bug where it would sometimes show -1 in replies (tappu75e@duck.com)
- Fix images and links occasionally appearing with escaped slashes (Daniel D‘Aquino)
- Fixed nostrscript not working on smaller phones (William Casarin)
- Fix zaps sometimes not appearing (William Casarin)
- Fixed issue where reposts would sometimes repost the wrong thing (William Casarin)
- Fixed issue where sometimes there would be empty entries on your profile (William Casarin)

[1.6-13]: https://github.com/damus-io/damus/releases/tag/v1.6-13


## [1.6-11]: "Bugfix Sunday" - 2023-08-07

### Added

- Add close button to custom reactions (Suhail Saqan)
- Add ability to change order of custom reactions (Suhail Saqan)
- Adjustable font size (William Casarin)


### Changed

- Show renotes in Notes timeline (William Casarin)

### Fixed

- Ensure the person you're replying to is the first entry in the reply description (William Casarin)
- Don't cutoff text in notifications (William Casarin)
- Fix wikipedia url detection with parenthesis (William Casarin)
- Fixed old notifications always appearing on first start (William Casarin)
- Fix issue with slashes on relay urls causing relay connection problems (William Casarin)
- Fix rare crash triggered by local notifications (William Casarin)
- Fix crash when long-pressing reactions (William Casarin)
- Fixed nostr reporting decoding (William Casarin)
- Dismiss qr screen on scan (Suhail Saqan)
- Show QRCameraView regardless of same user (Suhail Saqan)
- Fix wiggle when long press reactions (Suhail Saqan)
- Fix reaction button breaking scrolling (Suhail Saqan)
- Fix crash when muting threads (Bryan Montz)


[1.6-11]: https://github.com/damus-io/damus/releases/tag/v1.6-11

## [1.6-8]: "nostrdb prep" 2023-08-03

### Added

- Suggested Users to Follow (Joel Klabo)
- Add support for multiple reactions (Suhail Saqan)


### Changed

- Improved memory usage and performance when processing events (William Casarin)


### Fixed

- Fixed disappearing text on iOS17 (cr0bar)
- Fix UTF support for hashtags (Daniel D‘Aquino)
- Fix compilation error on test target in UserSearchCacheTests (Daniel D‘Aquino)
- Fix nav crashing and buggyness (William Casarin)
- Allow relay logs to be opened in dev mode even if relay (Daniel D'Aquino)
- endless connection attempt loop after user removes relay (Bryan Montz)


[1.6-8]: https://github.com/damus-io/damus/releases/tag/v1.6-8

## 1.6 (7): "Less bad" - 2023-07-16

### Added

- Show nostr address username and support abbreviated _ usernames (William Casarin)
- Re-add nip05 badges to profiles (William Casarin)
- Add space when tagging users in posts if needed (William Casarin)
- Added padding under word count on longform account (William Casarin)


### Fixed

- Don't spam lnurls when validating zaps (William Casarin)
- Eliminate nostr address validation bandwidth on startup (William Casarin)
- Allow user to login to deleted profile (William Casarin)
- Fix issue where typing cc@bob would produce brokenb ccnostr:bob mention (William Casarin)



[1.6-7]: https://github.com/damus-io/damus/releases/tag/v1.6-7

## [1.6-6] - 2023-07-16

### Added

- New markdown renderer (William Casarin)
- Added feedback when user adds a relay that is already on the list (Daniel D'Aquino)

### Changed

- Hide nsec when logging in (cr0bar)
- Remove nip05 on events (William Casarin)
- Rename NIP05 to "nostr address" (William Casarin)

### Fixed

- Fixed issue where hashtags were leaking in DMs (William Casarin)
- Fix issue with emojis next to hashtags and urls (William Casarin)
- relay detail view is not immediately available after adding new relay (Bryan Montz)
- Fix nostr:nostr:... bugs (William Casarin)


[1.6-6]: https://github.com/damus-io/damus/releases/tag/v1.6-6

## [1.6-4] - 2023-07-13

### Added

- Add the ability to follow hashtags (William Casarin)

### Changed

- Remove note size restriction for longform events (William Casarin)

### Fixed

- Hide users and hashtags from home timeline when you unfollow (William Casarin)
- Fixed a bug where following a user might not work due to poor connectivity (William Casarin)
- Icon color for developer mode setting is incorrect in low-light mode (Bryan Montz)
- Fixed nav bar color on login, eula, and account creation (ericholguin)


### Removed

- Remove following Damus Will by default (William Casarin)

[1.6-4]: https://github.com/damus-io/damus/releases/tag/v1.6-4

## [1.6-3] - 2023-07-11

### Changed

- Start at top when reading longform events (William Casarin)
- Allow reposting and quote reposting multiple times (William Casarin)


### Fixed

- Show longform previews in notifications instead of the entire post (William Casarin)
- Fix padding on longform events (William Casarin)
- Fix action bar appearing on quoted longform previews (William Casarin)


[1.6-3]: https://github.com/damus-io/damus/releases/tag/v1.6-3
## [1.6-2] - 2023-07-11

### Added

- Add support for multilingual hashtags (cr0bar)
- Add r tag when mentioning a url (William Casarin)
- Add initial longform note support (William Casarin)
- Enable banner image editing (Joel Klabo)
- Add relay log in developer mode (Bryan Montz)


### Fixed

- Fix lag when creating large posts (William Casarin)
- Fix npub mentions failing to parse in some cases (William Casarin)
- Fix PostView initial string to skip mentioning self when on own profile (Terry Yiu)
- Fix freezing bug when tapping Developer settings menu (Terry Yiu)
- Fix potential fake profile zap attacks (William Casarin)
- Fix issue where malicious zappers can send fake zaps to another user's posts (William Casarin)
- Fix profile post button mentions (cr0bar)
- Fix icons on settings view (cr0bar)
- Fix Invalid Zap bug in reposts (William Casarin)


### Removed

- Remove old @ and & hex key mentions (William Casarin)


[1.6-2]: https://github.com/damus-io/damus/releases/tag/v1.6-2
## [1.6] - 2023-07-04

### Added

- Speed up user search (Terry Yiu)
- Add post button to profile pages (William Casarin)
- Add post button when logged in with private key and on own profile view (Terry Yiu)

### Changed

- Drop iOS15 support (Scott Penrose)

### Fixed

- Load more content on profile view (William Casarin)
- Fix reports to conform to NIP-56 (Terry Yiu)
- Fix profile navigation bugs from muted users list and relay list views (Terry Yiu)
- Fix navigation to translation settings view (Terry Yiu)
- Fixed all navigation issues (Scott Penrose)
- Disable post button when media upload in progress (Terry Yiu)
- Fix taps on mentions in note drafts to not redirect to other Nostr clients (Terry Yiu)
- Fix missing profile zap notification text (Terry Yiu)


[1.6]: https://github.com/damus-io/damus/releases/tag/v1.6

## [1.5-5] - 2023-06-24

### Fixed

- Remove note zaps to fit apples appstore guidelines
- Fix zap sheet popping (William Casarin)
- Fix CustomizeZapView from randomly disappearing (William Casarin)
- Fix "zapped your profile" strings to say "zapped you" (Terry Yiu)
- Fix reconnect loop issues on iOS17 (William Casarin)
- Fix some more thread jankiness (William Casarin)
- Fix spelling of Nostr to use Titlecase instead of lowercase (Terry Yiu)
- Rename all usages of the term Post as a noun to Note to conform to the Nostr spec (Terry Yiu)
- Fix text cutoff on login with npub (gladiusKatana)
- Fix hangs due to video player (William Casarin)


[1.5-5]: https://github.com/damus-io/damus/releases/tag/v1.5-5

## [1.5-2] - 2023-05-30

### Added

- Add new full-bleed video player (William Casarin)
- Add ability to show multiple posts per user in Universe (Ben Weeks)
- Custom iconography added for other areas of the app. (Ben Weeks)
- Custom iconography for the left navigation. (Ben Weeks)
- Custom iconography for the tab buttons. (Ben Weeks)
- Added dots under image carousel (Ben Weeks)
- Add profile caching (Bryan Montz)
- Add mention parsing and fine-grained text selection on description in ProfileView (Terry Yiu)


### Changed

- Redesign phase 1 (text, icons)
- Updated UI to use custom font (Ben Weeks)

### Fixed

- Fix side menu bug in landscape (OlegAba)
- Use "Follow me on nostr" text when looking at someone else's QR code (Ben Weeks)
- Fix issue where cursor dissapears when typing long message (gladiusKatana)
- Attempt fix for randomly broken animated gifs (William Casarin)
- Fix cursor jumping when pressing return (gladius)
- Fix side menu label size so that translations in longer languages fit without wrapping (Terry Yiu)
- Fix reaction notification title to be consistent with ReactionView (Terry Yiu)
- Fix nostr URL scheme to open properly even if there's already a different view open (Terry Yiu)
- Fix crash related to preloading events (Bryan Montz)


## v1.4.3 - 2023-05-08

### Added

- Add #zaps and #onlyzaps to custom hashtags (William Casarin)
- Add OnlyZaps mode: disable reactions, only zaps! (William Casarin)
- Add QR Code in profiles (ericholguin)
- Add confirmation alert when clearing all bookmarks (Swift)
- Add deep links for local notifications (Swift)
- Add friends filter to DMs (William Casarin)
- Add image metadata to image uploads (William Casarin)
- Add nokyctranslate translation option (symbsrcool)
- Add partial support for different repost variants (William Casarin)
- Add paste button to login (Suhail Saqan)
- Add q tag to quoted renotes (William Casarin)
- Add setting to hide reactions (Terry Yiu)
- Add thread muting (Terry Yiu)
- Add unmute option in profile view (Joshua Jiang)
- Add webp image support (William Casarin)
- Added event preloading when scrolling (William Casarin)
- Colorize friend icons (William Casarin)
- Friends filter for notifications (William Casarin)
- Preload images so they don't pop in (William Casarin)
- Preload profile pictures while scrolling (William Casarin)
- Preview media uploads when posting (Swift)
- Save keys when logging in and when creating new keypair (Bryan Montz)
- Show blurhash placeholders from image metadata (William Casarin)
- Top-level tab state restoration (Bryan Montz)
- You can now change the default zap type (William Casarin)
- new iconography (Roberto Agreda)


### Changed

- Add number formatting for sats entry and use selected zaps amount from picker as placeholder (Terry Yiu)
- Adjust attachment images placement when posting (Swift)
- Always check signatures of profile events (William Casarin)
- Ask permission before uploading media (Swift)
- Cached various UI elements so its not as laggy (William Casarin)
- Change 500 custom zap to 420 (William Casarin)
- Changed look of Repost and Quote buttons (ericholguin)
- Enable like button on OnlyZaps profiles for people who don't have OnlyZaps mode on (William Casarin)
- Load zaps instantly on events (William Casarin)
- New looks to the custom zaps view (ericholguin)
- Only show friends, not friend-of-friend in friend filter (William Casarin)
- Preload events when they are queued (William Casarin)
- Search hashtags automatically (William Casarin)
- Show DM message in local notification (William Casarin)
- replace Vault dependency with @KeychainStorage property wrapper (Bryan Montz)


### Fixed

- Dismiss bookmarks view when switching tabs (William Casarin)
- Do not allow non-numeric characters for sats amount and fix numeric entry for other number systems for all locales (Terry Yiu)
- Do not translate own notes if logged in with private key (Terry Yiu)
- Don't process blurhash if we already have image cached (William Casarin)
- Fix "translated from english" bugs (William Casarin)
- Fix Copy Link action does not dismiss ShareAction view (Bryan Montz)
- Fix auto-translations bug where languages in preferred language still gets translated (Terry Yiu)
- Fix bug where you could only mention users at the end of a post (Swift)
- Fix bug with reaction notifications referencing the wrong event (Terry Yiu)
- Fix buggy zap amounts and wallet selector settings (William Casarin)
- Fix camera not dismissing (Swift)
- Fix crash when loading DMs in the background (William Casarin)
- Fix crash when you have invalid relays in your relay list (William Casarin)
- Fix crash with LibreTranslate server setting selection and remove delisted vern server (Terry Yiu)
- Fix having to set onlyzaps mode every time on restart (William Casarin)
- Fix invalid DM author notifications (William Casarin)
- Fix issue where uploaded images were from someone else (Swift)
- Fix npub search fails on the first try (Bryan Montz)
- Fix parse mention without space in content (Joshua Jiang)
- Fix posts with no uploadedURLs always get two blank spaces at the end (Bryan Montz)
- Fix relay signal indicator, properly show how many relays you are connected to (William Casarin)
- Fix shuffling when choosing users to reply to (Joshua Jiang)
- Fix slow reconnection issues (Bryan Montz)
- Fix tap area when mentioning users (OlegAba)
- Fix thread incompatibility for clients that add more than one reply tag (William Casarin)
- Fix user notifications from old events immediately shown on install and login (Bryan Montz)
- Fix weird #\[0] artifacts appearing in posts (William Casarin)
- Fix wrong relative times on events (William Casarin)
- Fixed blurhash appearing behind loaded images when swiping on carousel (William Casarin)
- Fixed glitchy preview (William Casarin)
- Fixed preview elements popping in (William Casarin)
- Fixed repost turning green too early and not reposting sometimes (Swift)
- Home now dismisses reactions view (William Casarin)
- Load missing profiles from boosts on home view (Gísli Kristjánsson)
- Load missing profiles from boosts on profile view (Gísli Kristjánsson)
- Load profiles in hashtag searched (William Casarin)
- Made DMs less poppy (William Casarin)
- Preserve order of bookmarks when saving (William Casarin)
- Properly scroll DM view when keyboard is open (William Casarin)
- Saved Jack's soul. (Ben Weeks)
- Zap type selection on smaller phones (ericholguin)

[1.4.3-21]: https://github.com/damus-io/damus/releases/tag/v1.4.3-21

## [1.4.3-20] - 2023-05-04

### Added

- Add webp image support (William Casarin)
- Preload profile pictures while scrolling (William Casarin)
- Save keys when logging in and when creating new keypair (Bryan Montz)
- Top-level tab state restoration (Bryan Montz)
- Added event preloading when scrolling (William Casarin)
- Preload images so they don't pop in (William Casarin)


### Changed

- Preload events when they are queued (William Casarin)
- Search hashtags automatically (William Casarin)
- Cached various UI elements so its not as laggy (William Casarin)


### Fixed

- Don't process blurhash if we already have image cached (William Casarin)
- Home now dismisses reactions view (William Casarin)
- Fix auto-translations bug where languages in preferred language still gets translated (Terry Yiu)
- Fix wrong relative times on events (William Casarin)
- Load profiles in hashtag searched (William Casarin)
- Fix weird #\[0] artifacts appearing in posts (William Casarin)
- Fix "translated from english" bugs (Terry)
- Fix crash when loading DMs in the background (William Casarin)
- Fixed blurhash appearing behind loaded images when swiping on carousel (William Casarin)
- Fix camera not dismissing (Swift)
- Fix bug with reaction notifications referencing the wrong event (Terry Yiu)
- Fix Copy Link action does not dismiss ShareAction view (Bryan Montz)
- Saved Jack's soul. (Ben Weeks)
- Fixed preview elements popping in (William Casarin)
- Fixed glitchy preview (William Casarin)



[1.4.3-20]: https://github.com/damus-io/damus/releases/tag/v1.4.3-20
## [1.4.3-15] - 2023-04-29

### Added

- Add q tag to quoted renotes (William Casarin)
- Add confirmation alert when clearing all bookmarks (Swift)
- Show blurhash placeholders from image metadata (William Casarin)
- Add image metadata to image uploads (William Casarin)


### Changed

- Load zaps instantly on events (William Casarin)


### Fixed

- Fix thread incompatibility for clients that add more than one reply tag (amethyst, plebstr)
- Preserve order of bookmarks when saving (William Casarin)
- Fix crash when you have invalid relays in your relay list (William Casarin)



[1.4.3-14]: https://github.com/damus-io/damus/releases/tag/v1.4.3-14

## [1.4.3-10] - 2023-04-25

### Added

- Add paste button to login (Suhail Saqan)
- Add nokyctranslate translation option (symbsrcool)
- You can now change the default zap type (William Casarin)
- Add partial support for different repost variants (William Casarin)


### Changed

- Change 500 custom zap to 420 (William Casarin)
- New looks to the custom zaps view (ericholguin)
- Adjust attachment images placement when posting (Swift)
- Only show friends, not friend-of-friend in friend filter (William Casarin)


### Fixed

- Fix reposts on macos and ipad (William Casarin)
- Fix slow reconnection issues (Bryan Montz)
- Fix issue where uploaded images were from someone else (Swift)
- Fix crash with LibreTranslate server setting selection and remove delisted vern server (Terry Yiu)
- Fix buggy zap amounts and wallet selector settings (William Casarin)


[1.4.3-10]: https://github.com/damus-io/damus/releases/tag/v1.4.3-10

## [1.4.3-2] - 2023-04-17

### Added

- Add deep links for local notifications (Swift)
- Add thread muting (Terry Yiu)
- Preview media uploads when posting (Swift)
- Add QR Code in profiles (ericholguin)


### Changed

- Always check signatures of profile events (William Casarin)
- Ask permission before uploading media (Swift)
- Show DM message in local notification (William Casarin)


### Fixed

- Fixed repost turning green too early and not reposting sometimes (Swift)
- Fix shuffling when choosing users to reply to (Joshua Jiang)
- Do not translate own notes if logged in with private key (Terry Yiu)
- Load missing profiles from boosts on home view (Gísli Kristjánsson)
- Load missing profiles from boosts on profile view (Gísli Kristjánsson)
- Fix tap area when mentioning users (OlegAba)
- Fix invalid DM author notifications (William Casarin)
- Fix relay signal indicator, properly show how many relays you are connected to (William Casarin)


[1.4.3-2]: https://github.com/damus-io/damus/releases/tag/v1.4.3-2

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
