# Verification — November 7, 2026

- `swift test`: 13 tests passed. Synthetic fixtures cover decrypted input, CIA + NCCH encryption, seeded/mixed-key ExeFS, corrupted data, missing keys/seeds, cancellation before and during work, unsupported titles, low-storage preflight, recovery, and safe export.
- iOS 26 device Release build: passed with signing disabled for sideload packaging.
- iOS Simulator build: passed without launching the app.
- SteamWorld Dig: converted the supplied 44.3 MB CIA, validating both contents and decrypted-section hashes. A second run with Boot9-derived components produced an identical output.
- Xenoblade Chronicles 3D: converted a 3.78 GB CIA, validating all contents. After adding a per-chunk autorelease pool, peak macOS resident memory fell from over 1 GB to 72.7 MiB.
- Pokémon Ultra Moon: converted a 3.71 GB CIA. Peak macOS resident memory was 73.4 MiB and peak memory footprint was 24.5 MiB, below the 128 MiB local-check budget.
- IPA packaging and metadata checked against the actual app: bundle identifier `com.nickesc.ciadecrypter`, iOS 26 minimum, iPhone/iPad device families, matching version/build/size, continued-processing identifiers, launch configuration, and bundled acknowledgments.
- Local imported AES values were checked against staged source files; none were present. Key files, firmware archives, game inputs, and converted outputs are ignored by Git and excluded from the app target.

No physical-device or UI runtime checks have been performed. Still verify actual playback in Folium and Manic, device Keychain imports, Files providers, iOS background execution while locked, interruption/retry, and AltStore/LiveContainer installation. The private draft is for those checks. macOS memory measurements do not establish device-specific memory use.

The memory probe is repeatable with `Scripts/check-memory.py`; it uses an external local sample and deletes only its own temporary output. See README.md for commands. Game data and imported keys are not part of the test suite or release.
