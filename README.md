# CIA Decrypter for iOS

An entirely on-device CIA-to-`.3ds` converter for iPhone and iPad on iOS 26. Native SwiftUI, sequential batches, persistent results, background processing, local key imports, and individual or whole-batch export.

The agreed requirements are in [PLAN.md](PLAN.md). The repository and release artifacts stay private until Nick chooses to publish.

## Build

Requires Xcode 26 with the iOS 26 SDK. XcodeGen is needed only to regenerate the included Xcode project. No third-party runtime packages are required.

Open `CIADecrypter.xcodeproj`, choose the CIADecrypter scheme, select your signing team and device, and build in Xcode.

To package an unsigned device IPA for AltStore or LiveContainer to re-sign:

```sh
bash Scripts/build-ipa.sh
```

The result is `build/CIADecrypter.ipa`. This script builds and packages; it does not launch, install, upload, or publish the app.

## Use

1. Import `aes_keys.txt`, `seeddb.bin`, and/or `boot9.bin` in Keys. Decrypted content needs no keys; encrypted CIA contents require the relevant common key components. Boot9 alone does not contain every key needed for every title.
2. Add one or several base-game `.cia` files from Files. The queue starts immediately and converts one file at a time.
3. Save or share completed files while the queue continues. For Folium, save to Files and import within Folium. Manic can accept compatible file-sharing actions.
4. Export All chooses a folder and writes separate `.3ds` files without overwriting existing names. Results clear only after successful batch export or batch cancellation. A paused batch can export its completed subset to free working space.

Original CIAs and imported key files remain untouched. Inputs use persistent Files bookmarks; if a source moves or its provider revokes access, select it again. Keep source files available until conversion finishes.

Keys are normalized and stored in the device-only Keychain. Seeds use protected local storage excluded from backup. No keys, games, or network services are bundled. Local test inputs, results, and firmware in `Secrets/` and `build/` are ignored by Git and excluded from the app target.

## Scope and recovery

- Base-game application CIAs only; updates, DLC, and system titles receive an error.
- Output is a reconstructed, trimmed emulator card image, not a byte-identical cartridge dump or a physical-card deployment tool.
- Supports CIA AES-CBC and NCCH AES-CTR, original and newer NCCH crypto methods, seeded crypto, mixed-key ExeFS files, and zero-key homebrew. NCCH versions 0 and 2 with 512-byte media units are supported.
- Verifies TMD metadata, every CIA content hash, and decrypted extended-header, ExeFS file/header, and RomFS header hashes before publishing an output.
- Canceled or failed conversions remove partial outputs. Low storage pauses the queue and preserves finished files. File failures do not stop unrelated jobs.
- After an interruption, completed results and queued files survive. Interrupted work restarts from the beginning on retry. Foreground work uses the same core as background work.
- Background runtime remains subject to iOS. If the system cannot grant a continued-processing task, the app explains that it must stay open. Force-quitting does not guarantee background completion.
- LiveContainer background work requires a build containing its [background-processing fix](https://github.com/LiveContainer/LiveContainer/commit/53e83476f85837f0dfe1199ff402853cd0514d9b), and may require its per-app “Fix Background Processing Tasks” and “Fix File Picker” settings.

## Verification

```sh
swift test
xcodebuild -quiet -project CIADecrypter.xcodeproj -scheme CIADecrypter \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The tests use synthetic data and published NIST AES vectors, with no game assets or retail keys. They cover both encryption layers, seeded/mixed-key conversion, integrity failures, missing keys, cancellation, storage preflight, persistent recovery, and export failure/filename collisions.

The command-line target exercises the same conversion core for local validation:

```sh
swift run cia-convert /path/to/input.cia build/output.3ds \
  --boot9 Secrets/boot9.bin --aes Secrets/aes_keys.txt --seeds Secrets/seeddb.bin
```

Omit key arguments that are unnecessary for the input. The converter refuses to overwrite an existing output.

A separate large-file memory check requires an external local sample:

```sh
swift build -c release --product cia-convert
python3 Scripts/check-memory.py /path/to/large-input.cia \
  --boot9 Secrets/boot9.bin --aes Secrets/aes_keys.txt --seeds Secrets/seeddb.bin
```

Physical-device checks still required: Folium and Manic playback; on-device key import/Keychain behavior; Files/provider export and recovery; background work while locked; and direct AltStore versus LiveContainer installation. A build or desktop conversion does not establish those results.

## Test and release workflows

GitHub Actions runs the `Test` workflow on pushes to `main`, pull requests, and manual dispatch. It runs the Swift core tests, Python release-metadata tests, packaging-script syntax check, and an unsigned iOS Simulator build with Xcode 26.3.

The `Release` workflow runs on version tags such as `v0.1.0`, or manually for an existing tag. It first calls the same test workflow, then installs XcodeGen, builds the unsigned device IPA, checks that the tag matches the packaged version, and publishes a normal GitHub release with `CIADecrypter.ipa`, `source.json`, and `icon.png`. Releases remain accessible only to repository members while the repository is private. No signing certificates or game keys are needed in CI.

To release a new version, update version/build numbers in `project.yml`, regenerate the Xcode project, commit and push, then create and push the matching version tag. The workflow refuses to replace an already-published release. Failed runs can be retried; an existing draft for the tag is updated and published after checks pass.

## AltStore source

After building the IPA:

```sh
python3 Scripts/make-source.py build/CIADecrypter.ipa --output docs/source.json
```

This reads the real bundle version, build number, minimum OS, and IPA byte size. It prepares a local source snapshot and icon without publishing anything. CI generates fresh metadata from every release IPA and attaches it to the release.

When ready, make the repository public. The automatically updated source address is `https://github.com/nickesc/cia-decrypter-ios/releases/latest/download/source.json`. Each source points to the matching versioned IPA and icon. This URL does not provide unauthenticated installation while the repository is private.

Recheck source permissions if entitlements or privacy usage descriptions change. Test keys and game outputs stay outside the build and release artifacts.

## Code

- `Sources/CIAKit`: bounded-memory conversion, key parsing, queue persistence, and export.
- `Sources/CCrypto`: small bridge to Apple's CommonCrypto AES implementation.
- `App`: SwiftUI interface, Keychain storage, document pickers, and iOS background tasks.
- `Tests/CIAKitTests`: portable core behavior checks.
- `Scripts`: local IPA packaging, source metadata, icon generation, and memory verification.

Attribution and license text for referenced MIT-licensed implementations ship in `App/ThirdPartyNotices.txt`. CryptoKit and CommonCrypto perform cryptographic primitives; no desktop converter, GPL compression library, or static retail key table is included.
