<img src="../docs/icon.svg" alt="CIA Decrypter icon" width="64" height="64" />

# CIA Decrypter website

The SvelteKit product site for CIA Decrypter, hosted on [GitHub Pages](https://nickesc.io/cia-decrypter-ios/). The [AltStore page](https://nickesc.io/cia-decrypter-ios/altstore/) links to the [source feed](https://nickesc.io/cia-decrypter-ios/source.json). The site also hosts the published IPA and icon so source refreshes and installs don't depend on GitHub's release-download URLs.

## Local development

Use **Node.js 24 or later**, Python 3, and an authenticated [GitHub CLI](https://cli.github.com/). From the repository root, stage the latest published release before starting the site:

```sh
python3 Scripts/prepare-site.py
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

The preparation script downloads the published source, icon, and IPA through GitHub's API into the ignored `static/` directory. It preserves the published version, date, and size while changing asset URLs to the website. Run it again to pick up a new release.

The build writes static HTML and release assets to `build/`. Tests check the built routes, asset links, source URL, and IPA size, so build before running them. Use the same `BASE_PATH` for both commands; omit it when hosting at the domain root.

## Publish

Set the repository's **Settings → Pages → Build and deployment → Source** to **GitHub Actions** once.

The [Pages workflow](../.github/workflows/pages.yml) stages the latest release, builds, checks, and deploys on pushes to `main` that change `homepage/`, `docs/icon.svg`, `Scripts/prepare-site.py`, or the workflow itself. The release workflow also calls it after publishing a new version. You can run it manually from GitHub Actions without rebuilding or replacing the app release. The workflow uses the host and base path from GitHub Pages so links and assets work under the repository URL.

See the [SvelteKit static adapter](https://svelte.dev/docs/kit/adapter-static) and [GitHub Pages workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) for hosting details.
