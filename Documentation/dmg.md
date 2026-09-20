# Installable DMG

Users install Ukigumu Squeeze from GitHub Releases. They do not need to clone.

The disk image is a classic Finder layout: `Ukigumu Squeeze.app` next to an
`Applications` symlink. Drag the app onto Applications.

## Local build

On a Mac with Xcode:

```sh
make dmg
```

Optional version override:

```sh
make dmg VERSION=0.1.0
```

That runs `Scripts/create-dmg.sh`. It builds a universal Release app
(`arm64` and `x86_64`) and writes `dist/UkigumuSqueeze-<version>.dmg`.

`make app` stops after the Release `.app`. `make clean-dist` removes `dist`
and the derived data used for packaging.

There is no JavaScript toolchain and no `pnpm` step.

## Signing (v0)

v0 DMGs are **ad-hoc signed and not notarized**. No Apple Developer
certificate or CI secret is required.

If Gatekeeper blocks the app:

1. Open the DMG.
2. Drag **Ukigumu Squeeze** to **Applications**.
3. In Applications, Control-click (or right-click) the app and choose **Open**.
4. Confirm Open in the dialog.

Do not invent Developer ID certificates or repository secrets for this.

TODO: when a Developer ID certificate and Apple notarization secrets exist,
add them to the GitHub Actions workflow and sign/notarize the Release app
before `hdiutil create`. Until then, keep ad-hoc signing and the right-click
Open path.

## CI

`.github/workflows/release-dmg.yml` runs on `macos-latest` for pull requests,
tags `v*`, and `workflow_dispatch`. Pull requests build the DMG and upload it
as a workflow artifact. They do not create or update a GitHub Release.

Tag pushes and `workflow_dispatch` with **publish** enabled (the default)
create or update the GitHub Release and attach `UkigumuSqueeze-<version>.dmg`.

### Root cause of the v0.1.0 failure

Tag `v0.1.0` at `98856b3` failed in **Build Release DMG** (`make dmg`)
before `hdiutil` ran. The job was
https://github.com/ukigumu/ukigumu-squeeze/actions/runs/35503977413.

`xcodebuild` on Xcode 26.6 / Swift 6 stopped on
`Sources/UkigumuSqueezeCore/Models.swift`:

```
error: reference to member 'mp4' cannot be resolved without a contextual type
error: 'nil' requires a contextual type
```

`MediaFormat.from(extension:)` returned early for image extensions, then used
implicit switch results (`.mp4`, `.mov`, `nil`). That is not a single-expression
function body, so Swift 6 could not infer `MediaFormat?`. Signing, empty
`DEVELOPMENT_TEAM`, SPM libwebp, destination, and `PRODUCT_NAME` were not the
failure. Parallel libwebp `Failed frontend command` lines were the Swift
compile aborting other jobs.

The switch now uses explicit `return` statements.

### Publish v0.1.0 after this fix merges

Do not force-push the existing `v0.1.0` tag. After this change is on `main`:

1. Open https://github.com/ukigumu/ukigumu-squeeze/actions/workflows/release-dmg.yml
2. Run workflow, branch **main**.
3. Set **tag** to `v0.1.0` and leave **publish** checked.
4. Confirm the run attaches `UkigumuSqueeze-0.1.0.dmg` to
   https://github.com/ukigumu/ukigumu-squeeze/releases/latest

The README Download link already points at `releases/latest`. Users who see
Gatekeeper should Control-click (or right-click) **Ukigumu Squeeze** and choose
**Open**.
