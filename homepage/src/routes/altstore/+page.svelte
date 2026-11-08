<script>
  import { appIcon, addSourceURL, downloadURL, releases } from '#lib/product.js';
  import CopySourceButton from '#lib/CopySourceButton.svelte';
</script>

<svelte:head>
  <title>Install · CIA Decrypter for iOS</title>
  <meta
    name="description"
    content="Add the CIA Decrypter source to AltStore Classic to install and update the app on your iPhone or iPad. Requires iOS 26 or later."
  />
</svelte:head>

<section class="install" aria-labelledby="install-title">
  <img class="app-icon" src={appIcon} alt="CIA Decrypter app icon" width="88" height="88" />
  <h1 id="install-title">Install with AltStore.</h1>
  <p class="lede">Install CIA Decrypter on your iPhone or iPad and get updates through AltStore.</p>
  <div class="actions">
    <a class="button" href={addSourceURL}>Add to AltStore <span aria-hidden="true">↗</span></a>
    <a class="text-link" href="https://faq.altstore.io/altstore-classic">Set up AltStore Classic <span aria-hidden="true">↗</span></a>
  </div>
  <p class="hint">Requires iOS 26 or later and AltStore Classic.</p>
</section>

<section class="source" aria-labelledby="source-title">
  <h2 id="source-title">Add the source manually.</h2>
  <p>Copy the URL below, then paste it into <strong>Browse → Sources → +</strong> in AltStore Classic.</p>
  <CopySourceButton block />
</section>

<aside class="note">
  <h2>Prefer to sideload the IPA?</h2>
  <p><a href={downloadURL}>Download CIADecrypter.ipa</a> for manual installation with AltStore or LiveContainer. See the <a href={releases}>latest release</a> for release notes.</p>
</aside>

<style>
  .note p {
    max-inline-size: none;
  }
</style>
