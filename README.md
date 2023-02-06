[![Run Test Suite](https://github.com/damus-io/damus/actions/workflows/run-tests.yaml/badge.svg?branch=master)](https://github.com/damus-io/damus/actions/workflows/run-tests.yaml)

# damus

A twitter-like [nostr][nostr] client for iPhone, iPad and MacOS.

<img src="./ss.png" width="50%" height="50%" />

[nostr]: https://github.com/fiatjaf/nostr

## Spec Compliance

damus implements the following [Nostr Implementation Possibilities][nips]

- [NIP-01: Basic protocol flow][nip01]
- [NIP-08: Mentions][nip08]
- [NIP-10: Reply conventions][nip10]
- [NIP-12: Generic tag queries (hashtags)][nip12]

[nips]: https://github.com/nostr-protocol/nips
[nip01]: https://github.com/nostr-protocol/nips/blob/master/01.md
[nip08]: https://github.com/nostr-protocol/nips/blob/master/08.md
[nip10]: https://github.com/nostr-protocol/nips/blob/master/10.md
[nip12]: https://github.com/nostr-protocol/nips/blob/master/12.md

## Getting Started on Damus 

### Damus iOS
1) Get the Damus app on the iOS App Store: https://apps.apple.com/ca/app/damus/id1628663131

#### ⚙️ Settings (gear icon, top right)
- Relays: You can add more relays to send your notes to by tapping the "+". 
  - Find more relays to add: https://nostr.info/relays/ 
- Public Key (pubkey): Your public, personal address and how people can find and tag you
 - Secret Key: Your *private* key unique to you. Never share your private key publically and share with other clients at your own risk!
   - Save your keys somewhere safe
 - Log out

#### 🏠 Personal Feed (home icon, bottom navigation)
- Feed from everyone you follow
- Can post notes by tapping the blue + button

#### Notes (under 🏠 Personal Feed)
- Sending a Note is easy and it goes to both your 🏠 Personal and 🔍 Global Feeds 
- To tag a user you must grab their pubkey:
  1. Search their username in the search bar at the top of the 🔍 Global Feed and click their profile
  2. Tap the 🔑 icon which will copy their pubkey to your clipboard
  3. Go back to your 🏠 Personal Feed and tap the blue + button to compose your Note
  4. Add @ direcly followed by the pubkey (e.g., `@npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s`)
- You can also long-press a Note to grab their User ID aka pubkey or Note ID to link directly to a Note.
- Currently you can't delete your Notes in the iOS app
- Share images by pasting the image url which you can grab from imgbb, imgur, etc. (i.e., `https://i.ibb.co/2SHZbwm/alpha60.jpg`). Currently images only load for people you follow in the 🏠 Personal Feed. Images are not automatically loaded in 🔍 Global Feed
- Engaging with Notes
  - 💬 Replying to a Note: Tap the chat icon underneath the note. This will show up in the users’ notifications and in your 🏠 Personal and 🔍 Global Feeds
  - ♺ Reposts: Tap the repost icon which will show up in your 🏠 Personal and 🔍 Global Feeds
  - ♡ Likes: Tap the heart icon. Users will not get a notification, and cannot see who liked their note (currently, web clients can see your pfp only)
- Formatting Notes (may not format as intended in other web clients)
  - Italics: 1 asterisk `*italic*`
  - Bold: 2 asterisk `**bold**`
  - Strikethrough: 1 tildes `~strikethrough~`
  - Code: 1 back-tick `` `code` ``

#### 💬 Encrypted DMs (chat app, bottom navigation)
- Tap the chat icon and you'll notice there's nothing to see at first. Go to a user profile and tap the 💬 chat icon next to the follow button to begin a DM

#### 🔍 Global Feed (magnify glass, bottom navigation)
- View the Global Feed from all the relays you've added in ⚙️ Settings. Currently you can only search hashtags and user names and pubkeys

#### 🔔 Notifications
- All your notifications except 💬 DMs

#### 👤 Change Your Profile (PFP) and Bio
1. Go to your Profile Page on Damus app
2. Tap on Edit button at the top
3. You will see text fields to update your information and bio
4. For PFP, insert a URL containing your image (support video: https://cdn.jb55.com/vid/pfp-editor.mp4)
5. Save

#### ⚡️ Request Sats 
    (Sats or Satoshis are the smallest denomination of bitcoin)
	
**Alby (browser extension)**
- Get the [Alby](https://getalby.com/) browser extension and create your Alby address [yourname]@getalby.com or connect your existing Lightning wallet
- Convert your Damus secret key from nsec to hex at https://damus.io/key then go to Settings in Alby and under the Nostr section at the bottom of the page add your private hex key. You can also generate new address in the extension
- Click the Alby extension > click Receive > enter the amount of Sats > click Get Invoice > click Copy > then paste into Damus
- Note: On Damus Web it will appear as a string of characters but on Damus iOS it will appear as a clickable image

**Zeus (mobile app)**
- Download [Zeus](https://zeusln.app/) app (iOS, Google, APK)
- Tap Get Started button > tap Connect a node > click on + sign (top right) > select Indhub > press Scan Lndhub QR > (from the Alby browser extension… click your account on the top left > click Manage Accounts > click 3-dot menu to right of your account and click Export Account to get a QR code then go back to Zeus app) > scan the QR Code and tap Save Node Config button
- To create an invoice tap Lightning > tap Receive > type in amount > tap Create Invoice > tap Copy Invoice > paste into a new Damus note

## Contributing

Contributors welcome!

### Code

[Email patches][git-send-email] to jb55@jb55.com are preferred, but I accept PRs on GitHub as well.

[git-send-email]: http://git-send-email.io

### Translations

Translators welcome! Join the [Transifex][transifex] project.

All user-facing strings must have a comment in order to provide context to translators. If a SwiftUI component has a `comment` parameter, use that. Otherwise, wrap your string with `NSLocalizedString` with the `comment` field populated.

[transifex]: https://explore.transifex.com/damus/damus-ios/

#### Export Source Translations

If user-facing strings have been added or changed, please export them for translation as part of your pull request or commit by running:

```zsh
./devtools/export-source-translation.sh
```

This command will export source translations to `translations/en-US.xcloc/Localized Contents/en-US.xliff`, which the Transifex integration will read from the `master` branch and allow translators to translate those strings.

#### Import Translations

Once 100% of strings have been translated for a given locale, Transifex will open up a pull request with the `translations/<locale>.xliff` file changed. Currently, it must be manually imported into the project before merging the pull request by running:

```zsh
./devtools/import-translation.sh <locale_code_in_snake_case>
```

### Awards

There may be nostr badges awarded for contributors in the future... :)

First contributors:

1. @randymcmillan
2. @jcarucci27

### git log bot

npub1fjtdwclt9lspjy8huu3qklr7eklp5uq90u6yh8mec290pqxraccqlufnas
