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

## Earlier export behavior — November 8, 2026 (superseded below)

- Core suite: 20 tests pass, including individual and mixed exports, pending/failed work, saved-state persistence, and receipts for partial batch exports.
- Simulator UI with two synthetic outputs: canceling Save leaves both ready; the first successful save shows a tinted Saved to Files row; saving the final output individually returns to the empty state without Export All.
- Filesystem checks confirm both destination copies remain, the persisted queue is empty, and the two app-owned result folders are gone.
- Save All and Share All skip results already exported. Shared results use a separate label; unsuccessful share callbacks do not mark a result exported.
- Stacked Save All / Share All / Add CIA files verified in Simulator. Share All shows two synthetic documents; canceling preserves both. After individually saving one file, Save Unsaved / Share Unsaved appear and the share sheet contains only the other file. Completing that share through Save to Files clears the queue automatically. Core tests remain at 20 passing; Simulator build passes.
- Manic's upstream `ApplicationSceneDelegate.scene(_:openURLContexts:)` accepts multiple file URLs and passes the copied files to its importer. A physical-device multi-file handoff to Manic still needs verification.

## Per-file cleanup and Saved history — November 8, 2026 (controls superseded below)

- Core suite: 22 tests pass. Coverage includes active/history separation, receipt persistence and recovery without a local output, Redo state reset, progress excluding history, idle-session reset, and preservation of unfinished/unsaved work.
- Simulator: saving one of two synthetic results moves it into a subdued Saved row with Redo and no save/share buttons. Filesystem assertions confirm only that result's working folder is deleted; the other output stays available.
- Relaunching with an unsaved output preserves both the active result and Saved history. Redo resolves the original CIA bookmark, recreates the working folder, and converts a valid synthetic CIA successfully.
- Save All removes each remaining working folder and leaves the conversion page open with two Saved rows. Redo from this idle page returns a row to the active list. Clear confirms before removing the unsaved result, preserves the other Saved row, and keeps the conversion page open.
- Backgrounding and returning preserves idle history. A fresh launch with only Saved history resets to the initial screen. Original CIAs and destination copies remain untouched.
- Save All and Share All remain side by side above Add CIA files, with fixed labels for single and mixed results. Physical-device SMB/LiveContainer Redo and emulator handoff still need testing.

## Independent pause, delete, and Clear — November 8, 2026 (Clear interaction superseded below)

- Core suite: 27 tests pass. New coverage checks section membership, pausing all jobs without losing progress, resume after persistence, Clear preserving running/queued/paused jobs, deletion into Finished followed by Redo, and protecting a worker while its files close.
- Restart recovery recognizes a fully verified final output even if the queue recorded a late pause or interruption, while preserving an explicit deletion request.
- Encrypted and decrypted multi-chunk fixtures pause after writing a prefix, retain their partial output, then resume to a complete verified image. Damaged partial output is rejected and removed. Interruption retains usable output; explicit cancellation removes it and takes precedence over later pause/interruption requests.
- Resume reconstructs integrity hashes and compares retained output to decrypted source bytes before writing the missing suffix. It rereads the saved prefix, so resuming a large remote CIA still needs time and access to the original file. Partial output never becomes exportable before full verification.
- Simulator with synthetic conversions: the all-jobs pause action stopped the current file and held the remaining queue. A retained partial output and all paused states survived a process restart; the UI restored the partial file at 2% progress. X removed that working folder, kept a Deleted history record, and left the other paused jobs intact.
- Simulator Clear confirmed before removing three unsaved results, error history, and deleted history. Filesystem checks showed all finished outputs removed and all 28 remaining paused jobs preserved. Running-job preservation is also covered by the core Clear test.
- Final UI places labeled Pause All / Resume All in the overview card, keeps Clear in the toolbar, and uses In Progress / Finished sections. Per-file Pause/Resume and X are separate controls; deleted and exported entries have Redo. The app no longer derives list behavior from global cancellation flags.
- Physical-device background expiration, low-storage pause, and SMB/LiveContainer resume still need testing.

## Inline Clear confirmation — November 8, 2026

- Clear is a small button aligned to the right of the Finished heading. The first tap changes its label to red Confirm?; the second clears the section without a confirmation popup.
- Simulator with paused, ready, and saved synthetic rows: the first tap kept all three entries and the ready output intact. The second removed both Finished entries and the unsaved working folder while preserving the paused row and partial output.
- Backgrounding and returning resets Confirm? to Clear. Section membership changes also reset confirmation. The Simulator build passes.
