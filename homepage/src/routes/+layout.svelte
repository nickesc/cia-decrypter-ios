<script>
  import { resolve } from '$app/paths';
  import { appIcon, repository } from '#lib/product.js';
  import ThemeToggle from '#lib/ThemeToggle.svelte';
  import '../app.css';

  let { children } = $props();
</script>

<svelte:head>
  <link rel="icon" type="image/svg+xml" href={appIcon} />
</svelte:head>

<a class="skip-link" href="#main">Skip to content</a>

<div class="site">
  <header class="site-header">
    <a class="brand" href={resolve('/')}>
      <img src={appIcon} alt="" width="36" height="36" />
      CIA Decrypter
    </a>
    <nav aria-label="Main navigation">
      <a href={resolve('altstore/')}>Install</a>
      <a href={repository}>GitHub <span aria-hidden="true">↗</span></a>
      <ThemeToggle />
    </nav>
  </header>

  <main id="main">
    {@render children()}
  </main>

  <footer class="site-footer">
    <span>Made by <a href="https://github.com/nickesc">nickesc</a></span>
    <a href={`${repository}#usage`}>Usage & support <span aria-hidden="true">↗</span></a>
  </footer>
</div>
