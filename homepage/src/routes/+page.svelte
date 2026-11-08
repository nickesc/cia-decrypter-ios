<script>
  import { resolve } from '$app/paths';
  import { appIcon, releases } from '#lib/product.js';
  import CopySourceButton from '#lib/CopySourceButton.svelte';
</script>

<svelte:head>
  <title>CIA Decrypter for iOS</title>
  <meta
    name="description"
    content="Convert Nintendo 3DS CIA files into decrypted .3ds files on your iPhone or iPad. Convert on your device, then save to Files for your emulator."
  />
</svelte:head>

<section class="hero" aria-labelledby="product-title">
  <img class="app-icon" src={appIcon} alt="CIA Decrypter app icon" width="112" height="112" />
  <p class="eyebrow">For iOS 26+</p>
  <h1 id="product-title">CIA to 3DS.<br />Right on your iPhone.</h1>
  <p class="lede">
    Convert your Nintendo 3DS CIA files into decrypted <code>.3ds</code> files.
    Queue your games, convert on your device, and save to Files for your emulator.
  </p>
  <div class="actions">
    <a class="button" href={resolve('altstore/')}>Install with AltStore <span aria-hidden="true">→</span></a>
    <a class="text-link" href={`${releases}/download/CIADecrypter.ipa`}>Download IPA <span aria-hidden="true">↗</span></a>
  </div>
  <CopySourceButton />
  <div class="conversion" aria-label="Convert .cia files to .3ds files on your device">
    <div class="conversion-file">
      <svg viewBox="0 0 40 48" width="40" height="48" aria-hidden="true">
        <path d="M6 1h19l14 14v29a3 3 0 0 1-3 3H6a5 5 0 0 1-5-5V6a5 5 0 0 1 5-5Z" />
        <path class="file-fold" d="M25 1v10a4 4 0 0 0 4 4h10M10 28h20M10 35h14" />
      </svg>
      <code>.cia</code>
      <small>Encrypted base game</small>
    </div>
    <div class="conversion-path">
      <svg viewBox="0 0 100 24" width="100" height="24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M1 12h96m-8-8 8 8-8 8" /></svg>
    </div>
    <div class="conversion-file output">
      <svg viewBox="0 0 40 48" width="40" height="48" aria-hidden="true">
        <path d="M6 1h19l14 14v29a3 3 0 0 1-3 3H6a5 5 0 0 1-5-5V6a5 5 0 0 1 5-5Z" />
        <path class="file-fold" d="M25 1v10a4 4 0 0 0 4 4h10m-14 11-9 10-5-5" />
      </svg>
      <code>.3ds</code>
      <small>Ready for your emulator</small>
    </div>
  </div>
</section>

<section class="getting-started" aria-labelledby="start-title">
  <h2 id="start-title">From Files to your emulator.</h2>
  <ol class="steps">
    <li><h3>Import your keys</h3><p>Add your AES keys, title seeds, or Boot9 dump in Keys. Reuse them for future conversions.</p></li>
    <li><h3>Add your CIA files</h3><p>Choose one or more base-game CIAs. Convert them in order, with pause and resume.</p></li>
    <li><h3>Save your games</h3><p>Save or share each ready result, or export them together. Import the <code>.3ds</code> files in your emulator.</p></li>
  </ol>
</section>

<aside class="note">
  <h2>Your files stay on your device.</h2>
  <p>Conversion runs locally without uploading your games or keys. Bring your own files; the app includes no games, firmware, or keys. Supports base games only.</p>
</aside>
