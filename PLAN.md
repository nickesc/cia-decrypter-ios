# CIA Decrypter for iOS

Confirmed November 7, 2026. Build a personal, entirely on-device CIA-to-`.3ds` converter for iPhone and iPad, with iOS 26 as the minimum version. Keep the repository private until Nick chooses to publish it.

## Conversion

- V1 supports base-game/application CIAs, encrypted or decrypted, and produces fully decrypted `.3ds` files for Folium and Manic EMU.
- Reject updates, DLC, system titles, and malformed inputs with actionable errors. Keep the conversion core separate so other package workflows can be added later.
- Import `aes_keys.txt`, `seeddb.bin`, and `boot9.bin` locally. Remember imported material between sessions, protect secret keys in Keychain, and support replacement and removal. Never bundle retail keys or display secret values.
- Stream file processing with bounded memory, validate content and storage, and preserve original inputs.

## Queue and results

- Import one or several CIAs through Files and process one at a time without waiting for export decisions.
- Show per-file status and progress, overall queue progress, errors, retry, and cancellation. Completed outputs are available while later files convert.
- Provide individual Save to Files and Share actions. Use system handoff where supported; Folium can import files saved through Files.
- Place Save All and Share All side by side in one row above Add CIA files. Keep these labels for any result count. Save All writes separate unexported `.3ds` files to a chosen folder; Share All passes them together to the system share sheet. Both exclude exported results.
- Group queued, running, paused, interrupted, and storage-paused jobs under In Progress. Group ready results, saved/shared history, errors, and deleted jobs under Finished. The core queue model owns section membership and pause/resume/delete/clear transitions.
- After each successful export, persist its receipt and delete only that file's app-owned working folder. Saved/shared and deleted rows look subdued and show Redo rather than save/share actions. Redo uses the original CIA bookmark for a fresh conversion and returns the row to In Progress.
- Keep the conversion page after exports or Clear, even with no active files. Accumulate Finished history as more CIAs are added. Keep it through backgrounding and relaunches with unfinished or unsaved work; reset on a fresh idle launch. Never clear history just because the app enters the background.
- Canceled/failed exports retain unsaved results for retry. Sharing counts as exported only when the system reports success.
- Continue past file failures, including missing keys. Allow retry after fixing the cause.
- Put a labeled Pause All / Resume All control in the overview card beside progress. Pause All pauses running and queued jobs without deleting progress. Per-file Pause retains progress; Resume continues that file. X deletes its working files and moves it to Finished with Redo, without stopping other jobs.
- Place a small Clear button at the right of the Finished heading. The first tap changes it to red Confirm?; the second clears Finished entries and their working files, including unexported results, saved history, errors, and deleted rows, without a popup. Reset confirmation if section membership changes or the app leaves the foreground. Preserve running, queued, and paused jobs, and protect a worker that is still closing its files.
- Pause on low storage while keeping completed and usable partial outputs. Resume after space becomes available.

## Background work and recovery

- Use iOS 26 continued processing for user-started conversions while the app is in the background, subject to system runtime limits.
- Persist the queue and retain partial outputs across pauses and interruptions. On resume, rebuild integrity hashes and check saved output bytes against the CIA before writing the missing suffix. Reject damaged or mismatched partial files; never present them as finished outputs.
- Test background behavior with a LiveContainer build containing its background-processing fix.

## Interface

- Native SwiftUI with polished typography, restrained color, clear status and progress, accessible text sizes, and light/dark appearance.
- Support iPhone and an iPad layout that uses the extra space. Put key management on a separate screen.

## Distribution

- Supply an Xcode project and a native IPA for AltStore and LiveContainer.
- Prepare versioned release packaging and an AltStore source JSON. Keep source and artifacts private for now; publish the download/source URL when the repository is made public.
- Do not publish or change repository visibility automatically.

## Build and verification

1. Prove the native conversion core with decrypted, encrypted, and seed-encrypted inputs, including all three key import formats.
2. Add persistent queueing, exports, cancellation, recovery, and background tasks.
3. Build and polish the SwiftUI interface and package the IPA.
4. Verify malformed input handling, cryptographic operations, storage failures, cancellation, recovery, large-file memory behavior, and output structure.
5. Verify real outputs in Folium and Manic on physical hardware, including direct installation and LiveContainer import/export/background behavior. Do not claim device compatibility before those checks.

Reuse code only under clear, suitable licenses and retain required notices. Existing desktop tools are not drop-in iOS libraries: streaming conversion, progress, cancellation, and user-supplied keys need dedicated integration. This is the principal technical risk to prove first.

## Reference sources

- [CIA format](https://www.3dbrew.org/wiki/CIA)
- [NCCH format](https://www.3dbrew.org/wiki/NCCH)
- [NCSD format](https://www.3dbrew.org/wiki/NCSD)
- [Project CTR](https://github.com/3DSGuy/Project_CTR)
- [3dsconv](https://github.com/ihaveamac/3dsconv)
- [Folium](https://github.com/folium-app/Folium)
- [Manic EMU](https://github.com/Manic-EMU/ManicEMU)
- [Apple continued processing](https://developer.apple.com/documentation/BackgroundTasks/performing-long-running-tasks-on-ios-and-ipados)
- [LiveContainer background fix](https://github.com/LiveContainer/LiveContainer/commit/53e83476f85837f0dfe1199ff402853cd0514d9b)
- [AltStore source specification](https://faq.altstore.io/developers/make-a-source)
