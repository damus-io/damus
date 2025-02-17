# Dev tips

A collection of tips when developing or testing Damus.


## Logging

- Info and debug messages must be activated in the macOS Console to become visible, they are not visible by default. To activate, go to Console > Action > Include Info Messages.


## Testing push notifications

- Dev builds (i.e. anything that isn't an official build from TestFlight or AppStore) only work with the development/sandbox APNS environment. If testing push notifications on a local damus build, ensure that:
    - Damus is configured to use the "staging" push notifications environment, under Settings > Developer settings.
    - Ensure that Nostr events are sent to `wss://notify-staging.damus.io`.

