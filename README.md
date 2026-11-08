<div align="center">

<img src="docs/icon.svg" alt="CIA Decrypter icon" width="112" height="112" />

# CIA Decrypter for iOS

Convert Nintendo 3DS CIA files into decrypted `.3ds` files on your iPhone or iPad.

**iOS 26+ · SwiftUI · On-device conversion**

[Get started](#get-started) · [Usage](#usage) · [Command line](#command-line) · [Development](#development)

</div>

Choose a game or a batch, convert on your device, and export to Files for your emulator. Bring your own CIA files and keys; the app includes neither and needs no conversion server.

## Features

- **Batch conversion.** Queue several games, track progress, and save finished files while the next one converts.
- **Local keys.** Import AES keys, title seeds, and Boot9 from Files and keep them between sessions.
- **Background processing.** Continue user-started conversions when iOS grants background time.
- **Recovery.** Keep queued files and completed results across interruptions. Retry failed files without stopping the rest of the queue.
- **Safe exports.** Save or share one result, or export completed files to a folder without overwriting existing names.
- **Large-file support.** Process data in chunks, check free storage, and verify hashes before making an output available.

## Get started

You need an iPhone or iPad running **iOS 26 or later**. To build the app, use a Mac with **Xcode 26 and the iOS 26 SDK**. The project uses Apple's frameworks with no third-party runtime packages.

### Build in Xcode

1. Clone this repository and open `CIADecrypter.xcodeproj`.
2. Select the **CIADecrypter** scheme, your signing team, and your device.
3. Build and run from Xcode.

### Package for sideloading

With [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed, run:

```sh
bash Scripts/build-ipa.sh
```

The script regenerates the project and writes an unsigned IPA to `build/CIADecrypter.ipa` for AltStore or LiveContainer to re-sign. Building the checked-in Xcode project does not require XcodeGen.

> [!NOTE]
> The repository is private. Release downloads and the AltStore source require repository access. See [verification results](VERIFICATION.md) for completed checks and pending physical-device testing, including emulator playback, installation, key imports, Files providers, and background execution.

## Usage

1. Open **Keys** and import the files your game needs. Already-decrypted games need no keys.
2. Tap **Add CIA files** and select one or more base-game `.cia` files. Conversion starts with one file at a time.
3. Use **Save to Files** or **Share** on any ready result. For Folium, save to Files, then import from within Folium. Use Share for apps that accept `.3ds` files, such as Manic.
4. When the queue finishes or pauses, tap **Export All** and choose a folder. The app saves separate `.3ds` files and clears the exported results from its working storage.

Individual saves and shares keep the result in the batch for Export All. Failed or canceled exports keep results for retry; files already copied remain in the destination folder. Canceling a batch removes its working results, with a confirmation for unexported files.

Keep source files available until conversion finishes. The app leaves original CIAs and imported key files untouched.

### Key files

| File | Purpose |
| --- | --- |
| `aes_keys.txt` | AES key components or normal common keys for encrypted content. |
| `seeddb.bin` | Per-title seeds for games that use seeded encryption. |
| `boot9.bin` | Key components from a valid full or protected retail Boot9 dump. |

Boot9 alone does not supply all keys for all games. If a conversion reports a missing key or seed, import the required file in **Keys**, then tap **Retry**. You can replace or remove imports from the same screen.

The app stores secret key material in the device-only Keychain and seeds in protected local storage excluded from backup. Conversion exports contain no imported key material.

### Supported content

The converter accepts encrypted or decrypted **base-game application CIAs** and creates trimmed, reconstructed card images for emulator use. It rejects updates, DLC, and system titles. Outputs are not byte-identical cartridge dumps.

Supported encryption includes CIA AES-CBC, NCCH AES-CTR methods `0`, `1`, `0x0A`, and `0x0B`, seeded encryption, mixed-key ExeFS, and zero-key homebrew. NCCH versions 0 and 2 must use 512-byte media units. Before completing an output, the converter checks TMD metadata, CIA content hashes, and decrypted extended-header, ExeFS, and RomFS header hashes.

### Recovery and background work

| Situation | Next step |
| --- | --- |
| Low storage | Export completed results or free space, then resume the batch. |
| Missing keys or a failed file | Fix the reported cause and tap **Retry**. Other files can continue. |
| Interrupted conversion | Reopen the app and resume. The interrupted file starts from the beginning. |
| Source moved or Files access expired | Select the CIA again through Files. |
| Background processing unavailable | Keep the app open while converting. |

iOS controls background runtime; force-quitting can interrupt a conversion. With LiveContainer, use a build containing its [background-processing fix](https://github.com/LiveContainer/LiveContainer/commit/53e83476f85837f0dfe1199ff402853cd0514d9b). Its per-app **Fix Background Processing Tasks** and **Fix File Picker** settings may also be needed.

## Command line

On macOS 14 or later, use the same conversion core from the terminal:

```sh
swift run cia-convert /path/to/input.cia build/output.3ds \
  --aes /path/to/aes_keys.txt \
  --seeds /path/to/seeddb.bin \
  --boot9 /path/to/boot9.bin
```

Omit key arguments your input does not need. The converter refuses to overwrite an existing output.

## Development

Run the core tests, release-metadata tests, and unsigned device build:

```sh
swift test
python3 -m unittest discover -s Tests/Python
xcodebuild -quiet -project CIADecrypter.xcodeproj -scheme CIADecrypter \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Tests use synthetic data and NIST AES vectors. They cover encryption, integrity failures, missing keys, cancellation, storage checks, recovery, and export collisions. [VERIFICATION.md](VERIFICATION.md) records build results, local conversions, memory measurements, and remaining device checks.

<details>
<summary>Check memory use with a local game file</summary>

```sh
swift build -c release --product cia-convert
python3 Scripts/check-memory.py /path/to/large-input.cia \
  --aes /path/to/aes_keys.txt \
  --seeds /path/to/seeddb.bin \
  --boot9 /path/to/boot9.bin
```

Omit unused key arguments. The script checks macOS memory use against a 128 MiB budget and removes its temporary output. Device memory use still needs separate testing.

</details>

### Project layout

| Path | Contents |
| --- | --- |
| `App/` | SwiftUI screens, Keychain storage, Files integration, and background tasks. |
| `Sources/CIAKit/` | Conversion, key parsing, persistent batches, and export. |
| `Sources/CCrypto/` | Bridge to Apple's CommonCrypto AES implementation. |
| `Sources/CIAConvert/` | Command-line converter. |
| `Tests/` | Swift core tests and Python release-metadata tests. |
| `Scripts/` | IPA packaging, source metadata, icon rendering, and memory checks. |

Edit [docs/icon.svg](docs/icon.svg) to change the icon, then run `swift Scripts/GenerateIcon.swift` to update the app and distribution PNGs. Icon rendering requires `rsvg-convert` from librsvg to preserve SVG filters and shadows. Third-party notices ship in [App/ThirdPartyNotices.txt](App/ThirdPartyNotices.txt).

### Releases and AltStore

The [Test workflow](.github/workflows/test.yml) runs Swift and Python tests, checks packaging-script syntax, and builds for iOS Simulator with Xcode 26.3. It runs on pushes to `main`, pull requests, and manual dispatch.

To release, update the version and build in `project.yml`, run `xcodegen generate`, commit the changes, and push a matching version tag such as `v0.1.0`. The [Release workflow](.github/workflows/release.yml) runs the tests, builds the unsigned IPA, validates the tag, and publishes `CIADecrypter.ipa`, `source.json`, and `icon.png`. It also accepts manual runs for an existing tag and refuses to replace a published release.

To prepare source metadata from a local IPA:

```sh
python3 Scripts/make-source.py build/CIADecrypter.ipa
```

This writes `build/distribution/source.json` and `icon.png` using the packaged version, build, minimum OS, and byte size. CI generates these files for each release. Once public releases are available, the AltStore source address is [releases/latest/download/source.json](https://github.com/nickesc/cia-decrypter-ios/releases/latest/download/source.json).
