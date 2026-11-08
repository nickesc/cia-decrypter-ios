# CIA Decrypter for iOS

Confirmed November 7, 2026. Build a personal, entirely on-device CIA-to-`.3ds` converter for iPhone and iPad, with iOS 26 as the minimum version. Keep the repository private until Nick chooses to publish it.

## Conversion

- V1 supports base-game/application CIAs, encrypted or decrypted, and produces fully decrypted `.3ds` files for Folium and Manic EMU.
- Reject updates, DLC, system titles, and malformed inputs with actionable errors. Keep the conversion core separate so other package workflows can be added later.
- Import `aes_keys.txt`, `seeddb.bin`, and `boot9.bin` locally. Remember imported material between sessions, protect secret keys in Keychain, and support replacement and removal. Never bundle retail keys or display secret values.
- Stream file processing with bounded memory, validate content and storage, and preserve original inputs.

## Queue and results

- Import one or several CIAs through Files and process one at a time without waiting for export decisions.
- Show per-file status and progress, overall batch progress, errors, retry, and cancellation. Completed outputs are available while later files convert.
- Provide individual Save to Files and Share actions. Use system handoff where supported; Folium can import files saved through Files.
- Stack Save All and Share All above Add CIA files. Save All writes separate unexported `.3ds` files to a chosen folder; Share All passes them together to the system share sheet. Use Save/Share for one result and Save Unsaved/Share Unsaved after any successful export. Both exclude already exported results. Mark exported results as Saved to Files or Shared and style saved rows distinctly.
- Updated November 8: clear the queue and temporary outputs once every remaining file has been successfully exported, individually or together. Keep pending/failed conversions; canceled files do not block cleanup. Canceled/failed exports retain unsaved results for retry, and partial folder exports mark each successfully saved file. Sharing counts as exported only when the system reports success. Remove only app-owned working files.
- Continue past file failures, including missing keys. Allow retry after fixing the cause.
- Allow individual and whole-batch cancellation. Confirm cancellation if it would remove completed, unexported results. Do not offer a separate Discard action.
- Pause on low storage, preserve completed outputs, remove the incomplete output, and allow retry after space becomes available.

## Background work and recovery

- Use iOS 26 continued processing for user-started conversions while the app is in the background, subject to system runtime limits.
- Persist the queue and completed outputs across interruptions. Interrupted files restart from the beginning on retry.
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
