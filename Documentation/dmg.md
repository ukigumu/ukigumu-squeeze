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

`.github/workflows/release-dmg.yml` runs on `macos-latest` for tags `v*` and
for `workflow_dispatch`. It builds the DMG, uploads it as a workflow artifact,
and creates or updates the GitHub Release with that `.dmg` attached.
