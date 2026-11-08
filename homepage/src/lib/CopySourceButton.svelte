<script>
  import { sourceURL } from '#lib/product.js';

  let { block = false } = $props();
  let status = $state('');

  async function copySource() {
    try {
      await navigator.clipboard.writeText(sourceURL);
      status = 'copied';
    } catch {
      status = 'failed';
    }
  }
</script>

<div class="copy-source">
  <button
    class={block ? 'source-url' : 'text-link copy-button'}
    type="button"
    aria-label="Copy source URL"
    onclick={copySource}
  >
    {#if block}<code>{sourceURL}</code>{/if}
    <span class="copy-label">
      <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
        <rect x="8" y="8" width="12" height="13" rx="2" /><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3" />
      </svg>
      {block ? (status === 'copied' ? 'Copied' : 'Copy') : 'Copy source URL'}
    </span>
  </button>
  <span class="copy-feedback" role="status">
    {#if status === 'copied'}Copied to clipboard.{/if}
    {#if status === 'failed'}Copy failed. Select this URL to copy it: <span class="selectable-url">{sourceURL}</span>{/if}
  </span>
</div>
