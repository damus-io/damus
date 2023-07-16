//
//  TestData.swift
//  damus
//
//  Created by William Casarin on 2023-07-13.
//

import Foundation


let test_event_holder = EventHolder(events: [], incoming: [test_event])

let test_event =
        NostrEvent(
            content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
            pubkey: "pk",
            createdAt: Int64(Date().timeIntervalSince1970 - 100)
        )

func test_damus_state() -> DamusState {
    let pubkey = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
    let damus = DamusState.empty

    let prof = Profile(name: "damus", display_name: "damus", about: "iOS app!", picture: "https://damus.io/img/logo.png", banner: "", website: "https://damus.io", lud06: nil, lud16: "jb55@sendsats.lol", nip05: "damus.io", damus_donation: nil)
    let tsprof = TimestampedProfile(profile: prof, timestamp: 0, event: test_event)
    damus.profiles.add(id: pubkey, profile: tsprof)
    return damus
}


let longform_long_test_data = """
## CURRENT PROGRAMMING

### Click Vortex
Sam ([@ltngstore](https://primal.net/lightningstore)/[@wavlake](https://primal.net/wavlake)) and Jason (Aquarium Drunkard) stumble down a rabbit hole of hyperlinks, following trails of interconnection between music and wildly varied topics. Live every other week on [YouTube](https://www.youtube.com/@wastoidsdotcom) and in your [podcast feed](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0).

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=Click+Vortex" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

<iframe width="560" height="315" src="https://www.youtube.com/embed/hOJdo5TTk3w" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### The Spindle
The 7-inch record isn’t just a format–it’s an art form. On each episode of The Spindle podcast, Marc and John dive into a great 7-inch every other week, dissecting its background, impact, and the reasons why it stands out as a small plastic piece of music history.

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=The+Spindle" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

### HOTLINE
This bi-weekly video series features your favorite artists answering questions from the 1-877-WASTOIDS answering machine, sharing their fantasy world, records they can't live with out and anything else that comes in.

**Subscribe:** [**YouTube**](https://youtube.com/@wastoidsdotcom), [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=Hotline" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

<iframe width="560" height="315" src="https://www.youtube.com/embed/qtOKkeFY6qU" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### Midnight Music Review in the Attic
Monthly video series spotlighting experimental songwriters, garage rockers, avant-pop acts and more from the mind (and attic) of Argentinian artist Salvador Cresta.

**Subscribe:** [**YouTube**](https://youtube.com/@wastoidsdotcom)

<iframe width="560" height="315" src="https://www.youtube.com/embed/R4DBKDWYRwo" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### WASTOIDS Music News
Decoy Deloy brings you the latest in music news, each Friday from the WASTOIDS loft.

**Subscribe:** [**YouTube**](https://youtube.com/@wastoidsdotcom)

<iframe width="560" height="315" src="https://www.youtube.com/embed/ATgGjsAwgoo" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### HIGHLIGHTER
Jenny Nobody brings a weekly video roundup of what you may have missed last week on WASTOIDS.

**Subscribe:** [**YouTube**](https://youtube.com/@wastoidsdotcom)

<iframe width="560" height="315" src="https://www.youtube.com/embed/tN8fiPmv5RU" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### WASTOIDS DIGS
Handpicked new releases from the WASTOIDS staff every week on [WASTOIDS DOT COM](https://wastoids.com/tag/wastoids-digs/)

[![https://cdn.shopify.com/s/files/1/0015/2602/files/1-WEDNESDAY.png?v=1689528035](https://cdn.shopify.com/s/files/1/0015/2602/files/1-WEDNESDAY.png?v=1689528035)](https://wastoids.com/tag/wastoids-digs/)

## SPECIALS

### Nilsson Talks Nilsson
Olivia and Keifo share interesting tidbits, unknown stories, and personal experiences related to their father, legendary singer, producer, interpreter, and composer, Harry Nilsson.

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=Nilsson+Talks+Nilsson" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

### Special Podness
Four-part mini-series dedicated to the history of The Special Goodness by the three dudes who (probably) know it best: Pat Wilson of Weezer, drummer Atom Willard (Rocket From the Crypt, Plosivs, Against Me!) and Karl Koch, Weezer historian.

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=The+Special+Goodness" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

### In The Crates
In the early ’80s, skate punk roared out of Phoenix, led by a group of teenagers called Jodie Foster’s Army. On JFA’s 1983 full-length debut, Valley of the Yakes, vocalist Brian Brannon rails against preps, gossipers, cops, and Reagan. But he saves some of his gnarliest lyrics for a local radio deejay, a guy named Johnny D.

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe src="https://www.buzzsprout.com/1811884/8869688-in-the-crates-1-johnny-d-versus-jfa?client_source=small_player&iframe=true" loading="lazy" width="100%" height="200" frameborder="0" scrolling="no" title='WASTOIDS, In the Crates 1: Johnny D Versus JFA'></iframe>

## FROM THE ARCHIVES

### Clairaudience
A late night weekly mood music/paranormal radio show featuring kitschy and soothing music, far out stories from guests like John Darnielle of The Mountain Goats, plus calls from the WASTOIDS hotline.

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=Clairaudience" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

### WASTOIDS With
Interviews featuring Van Dyke Park, Keith Morris, Steve Keene, Roger manning Jr., Paul Leary, Laura Jane Grace, East Bay Ray from Dead Kennedys, CREEM Magazine, The Source Family, and more.

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=WASTOIDS+with" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

### Strange Gear
An exploration of unusual musical equipment and the stories behind it featuring artists like, A Place to Bury Strangers and Nick Reinhart of Tera Melos, and more.

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=Strange+Gear" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

### WASTOIDS, Season 1
Initially created for Night Flight, this 4 episode series is baked and fried in the Sonoran Desert and NYC, throwing back to the halcyon days when stoned teenagers could stay up all night watching music videos, loopy comedy, and arty strangeness on the TV set.

**Subscribe:** [**YouTube**](https://youtube.com/@wastoidsdotcom)

<iframe width="560" height="315" src="https://www.youtube.com/embed/videoseries?list=PLD-OQ-VUZ9Q6tF1dclI8eyxmg8QyVmOy1" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### Out of Site
Recurring live music video series, featuring Mute Swan, Supercrush, Dante Elephant, Beach Bums, Sydney Sprague, and more.

**Subscribe:** [**YouTube**](https://youtube.com/@wastoidsdotcom)

<iframe src="https://www.buzzsprout.com/1811884/10980891-out-of-site-smirk-denial-of-life-wednesday-supercrush-milly?client_source=small_player&iframe=true" loading="lazy" width="100%" height="200" frameborder="0" scrolling="no" title='WASTOIDS, Out of Site: Smirk, Denial of Life, Wednesday, Supercrush, Milly'></iframe>

<iframe width="560" height="315" src="https://www.youtube.com/embed/videoseries?list=PLD-OQ-VUZ9Q5gCBpBTTm2aJMzb8VRReGj" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### MIXTAPE
Curated playlists from WASTOIDS friends

**Subscribe:** [**Fountain**](https://www.fountain.fm/show/YIkzHR3GeaNPDLeHlgg0), [**Other**](https://wastoids.buzzsprout.com)

<iframe id="player_iframe" src="https://www.buzzsprout.com/1811884?artist=&client_source=large_player&iframe=true&referrer=https%3A%2F%2Fwww.buzzsprout.com%2F1811884%2Fpodcast%2Fembed&tags=Mixtape" loading="lazy" width="100%" height="375" frameborder="0" scrolling="no" title="WASTOIDS"></iframe>

## WHAT ELSE?

*WASTOIDS is a hotline: 1-877-WASTOIDS. We want to know: What’s the weirdest thing that’s ever happened to you? Has a stranger ever relayed a cryptic message? Have you witnessed something confounding in the sky? Found yourself stranded in a frightening location? Call WASTOIDS and tell us your strange tale.*

![https://i0.wp.com/wastoids.com/wp-content/uploads/2023/03/HOTLINE.gif?resize=1200%2C507&ssl=1](https://i0.wp.com/wastoids.com/wp-content/uploads/2023/03/HOTLINE.gif?resize=1200%2C507&ssl=1)

[Follow us on Nostr!](https://primal.net/wastoids)
"""

