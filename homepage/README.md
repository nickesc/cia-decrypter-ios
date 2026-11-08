<img src="../docs/icon.svg" alt="CIA Decrypter icon" width="64" height="64" />

# CIA Decrypter website

The SvelteKit product site for CIA Decrypter, hosted on [GitHub Pages](https://nickesc.github.io/cia-decrypter-ios/). The [AltStore page](https://nickesc.github.io/cia-decrypter-ios/altstore/) links to the [release-generated source feed](https://github.com/nickesc/cia-decrypter-ios/releases/latest/download/source.json).

## Local development

Use **Node.js 24 or later**. From the repository root:

```sh
cd homepage
npm ci
npm run dev
```

Edit the pages in `src/routes/` and shared product links in `src/lib/product.js`. The site uses the app icon from `../docs/icon.svg`.

## Build and check

Run these commands from `homepage/`:

```sh
npm run check
BASE_PATH=/cia-decrypter-ios npm run build
BASE_PATH=/cia-decrypter-ios npm test
```

The build writes static HTML to `build/`. Tests check the built routes, asset links, and AltStore source URL, so build before running them. Use the same `BASE_PATH` for both commands; omit it when hosting at the domain root.

## Publish

Set the repository's **Settings → Pages → Build and deployment → Source** to **GitHub Actions** once.

The [Pages workflow](../.github/workflows/pages.yml) builds, checks, and deploys on pushes to `main` that change `homepage/`, `docs/icon.svg`, or the workflow itself. You can also run it manually from GitHub Actions. The workflow uses the base path from GitHub Pages so links and assets work under the repository URL.

See the [SvelteKit static adapter](https://svelte.dev/docs/kit/adapter-static) and [GitHub Pages workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) for hosting details.
