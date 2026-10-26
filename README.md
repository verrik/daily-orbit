# Daily Orbit

A native macOS menu bar app that downloads NASA’s Astronomy Picture of the Day (APOD) and sets it as your desktop wallpaper. Includes an optional animated screen saver.

## Features

- Daily wallpaper updates on connected displays, with manual refresh and apply controls.
- Full-resolution downloads, normalized to JPEG with a maximum dimension of 7680 pixels.
- Still-image fallback for video or embedded-media days.
- Offline cache and recovery from API or download failures.
- Fill and Fit layouts, plus restoration of previous wallpaper paths.
- Optional launch at login through macOS Service Management.
- Screen saver with a gentle pan and zoom, image title, credits, and Reduce Motion support.

## Requirements

- macOS 13 or later.
- Apple Command Line Tools or Xcode, including `swiftc` and the macOS SDK.
- An internet connection for new pictures. Saved pictures work offline.

There are no third-party package dependencies. Builds target the architecture of the Mac running the build (Apple silicon or Intel).

## Build and run

From the repository root:

```sh
./build.sh
open "dist/Daily Orbit.app"
```

The app downloads a picture and applies it on first launch. Daily updates are enabled by default. Closing the window keeps the app in the menu bar; use its sparkle menu to reopen it, pause updates, refresh, or quit.

Move the app to Applications if you want to keep it. Enable **Preferences → Launch at login** to start it after signing in. macOS may require you to allow the login item in System Settings.

Local builds are ad-hoc signed for local use. They are not Developer ID signed or notarized. The source and build scripts are available for inspection before running.

`ORBIT_BUILD_DIR` changes the intermediate build folder (default `.build/`). `ORBIT_OUTPUT_DIR` changes the app output folder (default `dist/`).

### Screen saver

Choose **Preferences → Install screen saver…**, complete the macOS installation prompt, then select **Daily Orbit** in **System Settings → Screen Saver**. Choose your idle time in macOS settings.

The screen saver reads the app’s saved image. It does not make network requests. Keep the app running to supply new pictures. The module has been loaded and rendered in a local preview; its behavior inside every supported macOS screen saver host has not been verified.

### Download once from the command line

Download and cache the latest image without changing the desktop:

```sh
"dist/Daily Orbit.app/Contents/MacOS/DailyOrbit" --sync-once
```

Add `--apply` to set the wallpaper and check the resulting desktop image path. Add `--storage /absolute/folder` to use a separate cache for a download test.

## NASA API and credentials

Daily Orbit uses NASA’s public endpoint:

```text
https://science.nasa.gov/wp-json/wp/v2/apod-basic
```

No API key, account, token, or embedded credential is required by this implementation. There are no credentials to configure or publish. See [NASA’s API documentation](https://api.nasa.gov/) for endpoint details.

The app checks locally every 15 minutes while running. Until a new APOD appears, successful API checks and failed attempts are spaced by about an hour. Once it has today’s entry, it waits until the next day in NASA’s Eastern Time zone. Manual refresh bypasses this schedule. Video days use the latest available still from the preceding two weeks. Publication delays or outages leave the last saved picture in place.

## Privacy and image rights

The app stores pictures, metadata, and wallpaper backup paths under:

```text
~/Library/Application Support/Daily Orbit/
```

Preferences use the standard macOS preferences system. There is no analytics or application backend. Network requests go to NASA’s API and the image URLs it returns.

This repository contains source code and synthetic test data. It does not contain downloaded APOD images, personal wallpaper backups, local configuration, or compiled app bundles. APOD images retain their original credits and copyright; do not assume every APOD image is public domain. Daily Orbit is an independent project and is not endorsed by NASA.

## Tests and publication checks

```sh
./test.sh
python3 Scripts/check-publication.py
```

The core tests cover both API response formats, URL handling, text decoding, date calculations, caching, video fallback, image normalization, and preservation of saved data after an HTTP error. They use synthetic data and stubbed networking, so they do not contact NASA or change your wallpaper.

The publication check scans tracked source files for common secret patterns, private local paths, personal email addresses, and forbidden generated files. It is a useful guard, not a guarantee that every possible secret format will be detected.

GitHub Actions builds the app and runs these checks on macOS. Neither the build nor core tests launch the app, register login items, or change the runner’s wallpaper.

## Known limitations

- Daily updates require the app to be running and the Mac to be awake and online. Launch at login is optional and has not been verified across all supported macOS versions.
- Wallpaper changes use Apple’s public API for connected displays’ current desktops. Other Spaces may require a separate application of the wallpaper. Apple does not expose an all-Spaces setter through this API; see [Apple’s clarification](https://developer.apple.com/forums/thread/834630).
- Restore saves the previous image path and layout; the original image file must still exist. Some dynamic wallpaper behavior and background-color settings may not be fully restored.
- Installing and selecting the screen saver is a separate macOS step.

## Source map

| File | Purpose |
| --- | --- |
| `Sources/APODCore.swift` | NASA API, media fallback, image validation, and atomic cache |
| `Sources/Desktop.swift` | Wallpaper application and per-display backups |
| `Sources/DailyOrbitApp.swift` | Native UI, menu bar, scheduling, login item, and CLI |
| `Sources/OrbitScreenSaver.swift` | Animated screen saver using the saved image |
| `Resources/MakeIcon.swift` | Procedural AppKit icon generation |
| `Tests/CoreTests.swift` | Offline integration and image tests |
| `Tests/RenderPreview.swift` | Optional offscreen UI and screen saver rendering helper |
