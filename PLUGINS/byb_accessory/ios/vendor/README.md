# Spike Recorder iOS reference sources

This folder is a **copy of selected sources** from your local Spike Recorder iOS tree (for example `Spike-Recorder-IOS-master/source/src`). It is **not compiled** by the `byb_accessory` pod (`exclude_files` in `byb_accessory.podspec`).

## Why

`Classes/BBAudioManager.{h,m}` is a **minimal stub** that implements only what `BybAccessoryPlugin` needs (`bbAudioManager`, `addMfiDevice…`, `removeMfiDevice…`) so the Flutter plugin builds without pulling in the whole app.

The real `BBAudioManager` in `Spike-Recorder-IOS-reference/Audio/BBAudioManager.mm` depends on:

- `DemoProtocol` / external accessory (see `Spike-Recorder-IOS-reference/accessory/`)
- `Novocaine`, `NVDSP`, ring buffers, file I/O
- `MyAppDelegate`, `BoardsConfigManager`, `InputDevice`, model classes under `source/src/Model`, controllers, etc.

Vendoring the full manager into this pod means vendoring a large slice of the native app and fixing includes, bundles, and initialization order.

## Using the real implementation later

1. Link a static library or framework that already contains the real `BBAudioManager` and its dependencies, **or**
2. Gradually move shared code into an iOS framework consumed by both the legacy app and Flutter, **or**
3. Port MFi registration into Flutter-only code and drop `BBAudioManager` from the plugin path.

Until then, keep the stub in `Classes/` and use this `vendor/` tree as the canonical reference while you integrate.
