<div align="center">

<img src="./damus/Assets.xcassets/damus-home.imageset/damus-home@2x.png" alt="Damus Logo" title="Damus logo" width=""/>

# Damus

The social network you control

A twitter-like [nostr][nostr] client for iPhone, iPad and MacOS. 

[![License: GPL-3.0](https://img.shields.io/github/license/damus-io/damus?labelColor=27303D&color=0877d2)](/LICENSE)

## Download and Install

[![Apple](https://img.shields.io/badge/Apple-%23000000.svg?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/us/app/damus/id1628663131)

## Supported Platforms

iOS 16.0+ • macOS 13.0+

<img src="./demo1.png" width="70%" height="50%" />

</div>

[nostr]: https://github.com/fiatjaf/nostr

## How is Damus better than X/Twitter?
There are no toxic algorithms.\
You can send or receive zaps (satoshis) without asking for permission.\
[There is no central database](https://fiatjaf.com/nostr.html). Therefore, Damus is censorship resistant.\
There are no ads.\
You don't have to reveal sensitive personal information to sign up.\
No email is required. \
No phone number is required. \
Damus is free and open source software. \
There is no Big Tech moat. Therefore, seamless interoperability with thousands or millions of other nostr apps is possible, and is how [Damus and nostr win](https://www.youtube.com/watch?v=qTixqS-W1yo).

## If there are no ads, how is Damus funded?
Damus offers a paid subscription 🟣 purple 🟣 https://damus.io/purple/. \
Initial benefits include a unique subscriber number, subscriber badge, and auto-translate powered by DeepL.

Damus has also graciously received donations or grants from hundreds of Damus users, [Opensats](https://opensats.org/), and the [Human Rights Foundation](https://hrf.org/).

## Spec Compliance

damus implements the following [Nostr Implementation Possibilities][nips]

- [NIP-01: Basic protocol flow][nip01]
- [NIP-04: Encrypted direct message][nip04]
- [NIP-08: Mentions][nip08]
- [NIP-10: Reply conventions][nip10]
- [NIP-12: Generic tag queries (hashtags)][nip12]
- [NIP-19: bech32-encoded entities][NIP19]
- [NIP-21: nostr: URI scheme][NIP21]
- [NIP-25: Reactions][NIP25]
- [NIP-42: Authentication of clients to relays][nip42]
- [NIP-56: Reporting][nip56]

[nips]: https://github.com/nostr-protocol/nips
[nip01]: https://github.com/nostr-protocol/nips/blob/master/01.md
[nip04]: https://github.com/nostr-protocol/nips/blob/master/04.md
[nip08]: https://github.com/nostr-protocol/nips/blob/master/08.md
[nip10]: https://github.com/nostr-protocol/nips/blob/master/10.md
[nip12]: https://github.com/nostr-protocol/nips/blob/master/12.md
[nip19]: https://github.com/nostr-protocol/nips/blob/master/19.md
[nip21]: https://github.com/nostr-protocol/nips/blob/master/21.md
[nip25]: https://github.com/nostr-protocol/nips/blob/master/25.md
[nip42]: https://github.com/nostr-protocol/nips/blob/master/42.md
[nip56]: https://github.com/nostr-protocol/nips/blob/master/56.md


## Getting Started on Damus 

### Damus iOS
1) Get the Damus app on the iOS App Store: https://apps.apple.com/ca/app/damus/id1628663131

#### ⚙️ Settings (gear icon, top right)
- Relays: You can add more relays to send your notes to by tapping the "+". 
  - Find more relays to add: https://nostr.info/relays/ 
- Public Key (pubkey): Your public, personal address and how people can find and tag you
 - Secret Key: Your *private* key unique to you. Never share your private key publicly and share with other clients at your own risk!
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
  4. Add @ directly followed by the pubkey (e.g., `@npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s`)
- You can also tap the ellipsis menu of a Note (three dots in top right of note) to grab their User ID aka pubkey or Note ID to link directly to a Note.
- Currently you can't delete your Notes in the iOS app
- Share images by pasting the image url which you can grab from nostr.build, imgbb, imgur, etc. (i.e., `https://i.ibb.co/2SHZbwm/alpha60.jpg`). Currently images only load for people you follow in the 🏠 Personal Feed. Images are not automatically loaded in 🔍 Global Feed
- Engaging with Notes
  - 💬 Replying to a Note: Tap the chat icon underneath the note. This will show up in the users’ notifications and in your 🏠 Personal and 🔍 Global Feeds
  - ♺ Reposts: Tap the repost icon which will show up in your 🏠 Personal and 🔍 Global Feeds
  - ♡ Likes: Tap the heart icon. Users will not get a notification, and cannot see who liked their note (currently, web clients can see your pfp only)


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
Paste an invoice from your favorite LN wallet.
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

Contributors welcome! Start by examining known issues: https://github.com/damus-io/damus/issues.

### Mailing lists

We have a few mailing lists that anyone can join to get involved in damus development:

- [dev][dev-list] - development discussions
- [patches][patches-list] - code submission and review
- [product][product-list] - product discussions
- [design][design-list] - design discussions

[dev-list]: https://damus.io/list/dev
[patches-list]: https://damus.io/list/patches
[product-list]: https://damus.io/list/product
[design-list]: https://damus.io/list/design

### Contributing

See [docs/CONTRIBUTING.md](./docs/CONTRIBUTING.md)

### Privacy
Your internet protocol (IP) address is exposed to the relays you connect to, and third party media hosters (e.g. nostr.build, imgur.com, giphy.com, youtube.com etc.) that render on Damus. If you want to improve your privacy, consider utilizing a service that masks your IP address (e.g. a VPN) from trackers online.

The relay also learns which public keys you are requesting, meaning your public key will be tied to your IP address.

It is public information which other profiles (npubs) you are exchanging DMs with. The content of the DMs is encrypted.

### Translations

Translators welcome! Join the [Transifex][transifex] project.

All user-facing strings must have a comment in order to provide context to translators. If a SwiftUI component has a `comment` parameter, use that. Otherwise, wrap your string with `NSLocalizedString` with the `comment` field populated.

[transifex]: https://explore.transifex.com/damus/damus-ios/

### Awards

Damus lead dev and founder Will awards developers with satoshis!
There may be nostr badges awarded for contributors in the future... :)


First contributors:

1. @randymcmillan
2. @jcarucci27

### git log bot

npub1fjtdwclt9lspjy8huu3qklr7eklp5uq90u6yh8mec290pqxraccqlufnas
