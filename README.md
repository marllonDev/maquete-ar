# Maquete AR

Architects upload a 3D model, clients open it in augmented reality with a
six-digit code. No account for the client.

Flutter app, iOS (ARKit) and Android (ARCore).

## Screens

| # | Screen | File |
|---|--------|------|
| 1 | Welcome — architect / client fork | `lib/screens/welcome_screen.dart` |
| 1b | Architect profile | `lib/screens/architect_login_screen.dart` |
| 1c | Client access code | `lib/screens/client_code_screen.dart` |
| 2 | Project list | `lib/screens/architect_dashboard_screen.dart` |
| 2b | Project detail: code, share, 3D upload | `lib/screens/project_detail_screen.dart` |
| 3 | Client overview + miniature / 1:1 choice | `lib/screens/project_overview_screen.dart` |
| 4 | AR camera | `lib/screens/ar_screen.dart` |

## Running

```bash
flutter pub get
flutter run -d <device-id>
```

AR needs a **physical device**. The iOS Simulator has no ARKit: screens 1–3 work
there, screen 4 renders its overlay over a blank area.

A demo project ships with the app (access code `000000`) so the AR engine can be
tried before any upload exists.

### iOS

Deployment target is 15.0 (ARKit). `Podfile` enables only the
`PERMISSION_CAMERA` and `PERMISSION_PHOTOS` compile flags for
`permission_handler`.

### Android

`minSdk` is forced to 24 and the manifest declares
`android.hardware.camera.ar` as required, so the Play Store hides the app from
devices that cannot run it.

ARCore tracking stutters on some devices when the app is debuggable — judge AR
smoothness in a profile or release build, not in debug
([arcore-android-sdk#1750](https://github.com/google-ar/arcore-android-sdk/issues/1750)).

## AR engine

`ar_flutter_plugin_flash` 1.1.6 — the maintained fork of `ar_flutter_plugin`.

The PRD named `ar_flutter_plugin_2`; that package pins `sdk: ">=2.16.1 <3.0.0"`
and cannot resolve against Dart 3. Every other fork in that family
(`ar_flutter_plugin`, `_flutterflow`, `_engine`) has the same pin. `_flash` is
the same API surface on `>=3.0.0 <4.0.0`, with native ARKit/ARCore, plane
detection, anchors and scene snapshots.

What the plugin gives us, mapped to the PRD's technical requirements:

- **Plane detection** — `PlaneDetectionConfig.horizontal`, with a coaching
  string driven by `onPlanesUpdated`.
- **Anchor persistence** — the model is attached to an `ARPlaneAnchor`, not to
  the world origin, so it does not drift when the camera moves.
- **Gestures** — single-finger drag is handled natively (`handlePans: true`);
  pinch-to-scale and two-finger rotation are handled in Flutter
  (`handleRotation: false`) so the two never fight over the same fingers.
- **Reset** — removes the node and the anchor and returns to the coaching state.
- **Screenshot** — `ARSessionManager.snapshot()`, with detected-plane overlays
  hidden for the shot, saved to a "Maquete AR" album via `gal`.
- **File ceiling** — 30 MB hard limit, warning above 20 MB
  (`lib/core/constants.dart`).

### Known limitation: finish swatches

The swatch bar swaps the **whole model file**, not an individual material. The
plugin exposes no runtime material API, and neither ARCore's Sceneform
replacement nor ARKit's SceneKit bridge is reachable through it. Real per-material
swapping needs an embedded Unity scene (`flutter_unity_widget`) or custom native
code on both platforms.

So an architect who wants three finishes exports three `.glb` files. The bar
hides itself when a project has only one.

`.usdz` is rejected on upload: ARCore cannot render it, so accepting it would
produce projects that open on iOS and fail on Android.

## Data

Phase 1 stores everything on the device: project metadata in
`SharedPreferences`, model files in the app documents directory (which is what
the plugin's `fileSystemAppFolder*` node types read from).

No screen imports a concrete repository — they go through
`ProjectRepository` (`lib/data/project_repository.dart`) via `RepositoryScope`.
Phase 2 swaps `LocalProjectRepository` for a Firebase-backed one in `main.dart`
and the UI does not change.

The architect profile is likewise device-local: there is no backend to
authenticate against yet.

## Tests

```bash
flutter test
```

Covers project serialization, node-type mapping, scale bounds, formatting, and
the screen flows that do not need a camera.
