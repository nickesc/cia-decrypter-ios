# Verification — November 7, 2026

- `swift test`: 13 tests passed. Synthetic fixtures cover decrypted input, CIA + NCCH encryption, seeded/mixed-key ExeFS, corrupted data, missing keys/seeds, cancellation before and during work, unsupported titles, low-storage preflight, recovery, and safe export.
- Python release-metadata tests: three passed, covering packaged version/size/asset URLs, rejection of mismatched tags, and rejection of bundled key/game files.
- iOS 26 device Release build: passed with signing disabled for sideload packaging.
- iOS Simulator build: passed without launching the app.
- SteamWorld Dig: converted the supplied 44.3 MB CIA, validating both contents and decrypted-section hashes. A second run with Boot9-derived components produced an identical output.
- Xenoblade Chronicles 3D: converted a 3.78 GB CIA, validating all contents. After adding a per-chunk autorelease pool, peak macOS resident memory fell from over 1 GB to 72.7 MiB.
- Pokémon Ultra Moon: converted a 3.71 GB CIA. Peak macOS resident memory was 73.4 MiB and peak memory footprint was 24.5 MiB, below the 128 MiB local-check budget.
- IPA packaging and metadata checked against the actual app: bundle identifier `com.nickesc.ciadecrypter`, iOS 26 minimum, iPhone/iPad device families, matching version/build/size, continued-processing identifiers, launch configuration, and bundled acknowledgments.
- Local imported AES values were checked against staged source files; none were present. Key files, firmware archives, game inputs, and converted outputs are ignored by Git and excluded from the app target.

Physical-device acceptance checks remain for playback in Folium and Manic, device Keychain imports, remote Files providers, iOS background execution while locked, interruption/retry, and AltStore/LiveContainer installation. macOS memory measurements do not establish device-specific memory use.

The memory probe is repeatable with `Scripts/check-memory.py`; it uses an external local sample and deletes only its own temporary output. See README.md for commands. Game data and imported keys are not part of the test suite or release.

## Export behavior — November 8, 2026

- Core suite: 20 tests pass, including individual and mixed exports, pending/failed work, saved-state persistence, and receipts for partial batch exports.
- Simulator UI with two synthetic outputs: canceling Save leaves both ready; the first successful save shows a tinted Saved to Files row; saving the final output individually returns to the empty state without Export All.
- Filesystem checks confirm both destination copies remain, the persisted queue is empty, and the two app-owned result folders are gone.
- Save All and Share All skip results already exported. Shared results use a separate label; unsuccessful share callbacks do not mark a result exported.
- Stacked Save All / Share All / Add CIA files verified in Simulator. Share All shows two synthetic documents; canceling preserves both. After individually saving one file, Save Unsaved / Share Unsaved appear and the share sheet contains only the other file. Completing that share through Save to Files clears the queue automatically. Core tests remain at 20 passing; Simulator build passes.
- Manic's upstream `ApplicationSceneDelegate.scene(_:openURLContexts:)` accepts multiple file URLs and passes the copied files to its importer. A physical-device multi-file handoff to Manic still needs verification.
