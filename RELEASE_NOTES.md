# CIA Decrypter for iOS 0.1.0

Initial private build for iPhone and iPad on iOS 26.

- Convert encrypted or decrypted base-game CIAs into decrypted `.3ds` files on-device.
- Import AES keys, seed databases, and full/protected retail Boot9 dumps locally.
- Run a sequential queue with progress, cancellation, retry, persistent recovery, and continued background processing when iOS permits it.
- Save/share individual results or export completed files to a folder, retaining results until successful batch export or cancellation.
- Pause for low storage and continue past individual file failures.

The IPA is unsigned for AltStore or LiveContainer to re-sign. No keys, firmware, or game data are included.

Builds, 13 core tests, and local conversions of three real inputs passed. Physical-device playback, Files/Keychain behavior, and background execution in both installation modes remain to be checked. See VERIFICATION.md for scope and results.

This is a private draft. No public AltStore source or download has been published.
