# Builds and validation

## Annual community lab — October 4, 2026

The default entry point is **Warm homes, shared systems**. The earlier evening game is available with `--evening`, and the foundation with `--foundation`; their save files and model paths are preserved. See the [lab guide](lab.md) for the data contract and numerical boundaries.

| Check | Observed result |
| --- | --- |
| Simulation and mod API | 765 checks passed, including annual stock/energy/cash reconciliation, analytical thermal fixtures, capacity failures, supported loads, schema/dependency rejection, full weather CSVs, archive bounds and exact replay |
| Evening scene regression | 14 checks passed |
| Annual scene/controller | 56 checks passed: form-created mod, layout/undo, pause/continue, matched year, import/replay, rejected import preservation, rendered temperature binding, and all five panels at 390×844, 844×390 and 1440×900 |
| Native rendered lab | Desktop and portrait annual smoke runs completed and inspected; rendering uses the active run rather than the original draft |
| Browser | WebGL 2 load, wall selection, complete annual comparison, ZIP download and file-chooser reimport completed; no console errors or warnings observed; portrait comparison inspected |
| Portable file exchange | The browser download was found in Downloads and replayed by the native headless runner. Its two reports matched the native reference run. The browser then imported that ZIP and returned to the same displayed annual results |
| CLI and packaging | Full-year JSON output and experiment ZIP round trip reproduced both reports; v1 and v2 packaging passed; v2 archive validated with the host compiler |
| Exports | Updated Web, macOS and Android development builds completed without script/export errors |

Local simulation timing on this Apple M1 Max: one 24-person year took **900 ms** in the headless test; two matched years through the CLI took **1,755 ms**, excluding startup/compilation and output serialization. These are individual local observations, not low-end hardware or sustained-phone benchmarks. The UI uses a bounded work budget between frames.

The default continental example produced 42,783 occupied cold person-hours for light timber and 4,551 for insulated timber. Insulation increased construction from €471,141 to €499,639. These values demonstrate the declared synthetic model and are regression evidence, **not predictions about real buildings**. Utility funding shortages contribute to year-end failures; the household inspector exposes the shared reserve, maintenance state and storage levels.

The browser's automated download event observer timed out, but the actual archive was saved and successfully replayed. Native and browser float bit identity is not generally guaranteed; this one exported case and its displayed outcomes matched. Physical Android/iOS devices, Safari, accessibility/screen-reader coverage, native mobile file pickers, long thermal-soak tests and empirical calibration remain unverified. Prior iOS runtime limitations below still apply. No marketplace, arbitrary asset/code loading, general model modules or century simulation is implied by this slice.

```sh
python3 scripts/check.py
godot --headless --path . --script scripts/run_lab.gd -- --assembly=core:warm_wall --hours=8760
godot --path . -- --lab-smoke --screenshot=artifacts/lab-desktop.png
godot --path . --resolution 390x844 -- --lab-smoke --screenshot=artifacts/lab-phone.png
# Browser QA without modifying saves: http://localhost:8060/?lab-test
```

## Evening playable validation — October 2, 2026

At that milestone the default entry point ran **An evening back**; it is now selected with `--evening`. The original sandbox and its measured rendering baseline remain available with `--foundation` (the existing `--smoke` / `--benchmark` flags still select that model).

| Check | Result |
| --- | --- |
| Simulation/extension suite | 608 checks passed, including service alternatives, stock and money reconciliation, utility failures, worker tradeoffs, invalid definitions/reports and deterministic mid-service save continuation |
| Actual scene/controller suite | 14 checks passed: scenario startup, service placement, incremental reference comparison, reset/notebook, custom recipe, portrait inspector/rotation and landscape control separation |
| Native rendered scenario | 1440×900 desktop and 390×844 portrait smoke runs completed; final result and responsive layout inspected |
| In-app browser | Initial load, route preview, six-hour trial, matched comparison, save reload, workshop JSON validation/placement and fresh-start backup flow exercised; no reported browser warnings/errors |
| Web, macOS and Android | Updated debug exports completed without export/script errors |

The browser mod-export action reported a ready download, but the automation download observer did not capture the archive. Archive delivery and mobile file pickers still need ordinary-browser/device testing. The new scene smoke runs are short functional checks, not a new performance benchmark or physical-phone measurement. Physical phones and the prior iOS runtime blocker remain outstanding.

```sh
python3 scripts/check.py
godot --headless --path . --script tests/playable.gd -- --evening-smoke
godot --path . -- --evening-smoke --screenshot=artifacts/evening-desktop.png
godot --path . --resolution 390x844 -- --evening-smoke --screenshot=artifacts/evening-phone.png
```

See [the playable guide](evening.md) for implemented mechanics, synthetic balancing assumptions, data-mod boundaries and remaining work. AI creation currently uses exported prompts and validated pasted definitions; no model provider is integrated.

Godot 4.7.2 standard (GDScript), using Compatibility/OpenGL/WebGL 2. Run from the repository root. Export templates must match the installed editor; the official 4.7.2 archive was checked against its published SHA-512 checksum.

## Build

```sh
mkdir -p exports/web exports/macos exports/android exports/ios exports/windows exports/linux
python3 scripts/check.py
godot --headless --path . --export-debug Web exports/web/index.html
python3 scripts/serve.py
# Open http://localhost:8060 in a WebGL 2 browser.

godot --headless --path . --export-debug macOS exports/macos/CourtyardBlock.zip
godot --headless --path . --export-debug Android exports/android/courtyard-block.apk
godot --headless --path . --export-debug Windows exports/windows/CourtyardBlock.exe
godot --headless --path . --export-debug Linux exports/linux/courtyard-block.x86_64
```

Android requires a JDK, current Android SDK platform/build tools, Godot's Android SDK editor setting, and a debug keystore. This machine's old build-tools 27 signing utility failed on modern Java; installing build-tools 36.0.0 resolved signing. The APK is a development build. Use current platform-tools/ADB to install it; old ADB versions caused emulator connection failures.

```sh
adb install -r exports/android/courtyard-block.apk
adb shell monkey -p org.courtyardblock.game -c android.intent.category.LAUNCHER 1
```

Web exports are single-threaded with no GDExtension dependency and do not require cross-origin isolation headers. Serve HTTP locally or HTTPS remotely; do not open `index.html` as a `file:` URL. Source GDScript export is intentional: the loader reads entry scripts for pack fingerprints, and runtime trusted source mods must remain supported. Do not switch to bytecode export without updating that contract.

## iOS

The checked-in iOS preset exports an Xcode project. Real device development needs your Apple team ID and provisioning; the preset intentionally leaves that identity empty.

For an unsigned simulator project:

```sh
python3 scripts/export_ios_simulator.py
xcodebuild -project exports/ios/CourtyardBlock.xcodeproj \
  -scheme CourtyardBlock -configuration Debug -sdk iphonesimulator \
  -derivedDataPath exports/ios/build CODE_SIGNING_ALLOWED=NO \
  ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO
```

The script uses a temporary project with a `SIMULATOR` placeholder solely to pass Godot's project-export validation. It does not sign or invent a development identity. The installed official template has an x86_64 simulator library; an arm64 simulator link failed with architecture errors. The x86_64 build succeeds and installs on an iOS 17.2 iPhone 15 Pro simulator, but execution stalled at OpenGL ES context initialization. A launch with the Mobile renderer also failed to produce a playable scene. **iOS runtime support is not yet validated.** Resolve the simulator/template graphics path and test a provisioned physical device before declaring iOS ready.

## Original foundation verification record

Tested on an Apple M1 Max Mac running macOS 26.7, October 2, 2026. Browser: headed Chromium 154, device pixel ratio 1, 1440×900 canvas.

| Check | Result |
| --- | --- |
| Headless simulation/extension suite | 550 checks passed |
| Seven-day seeded replay with 150 residents | Identical outcomes across two runs |
| JSON round trip and continuation | Preserved outcomes at full precision |
| Malformed data, missing/cyclic dependencies and duplicate IDs | Rejected; live state and successful registrations preserved |
| External zipped GDScript pack | Installed and loaded at runtime |
| Native rendered game | Rendering, furnishing, floor cutaway and simulation smoke passed |
| Chromium WebGL 2 game | Loaded with no console errors; resident inspection, furnishing, fork/switch/week comparison and JSON export exercised |
| Landscape mobile layout | 844×390 browser/native layout inspected; Android menu and touch exercised |
| Android development APK | Exported, signed, verified, installed and rendered on an ARM64 API 35 emulator |
| Windows/Linux x86_64 | Exported successfully; execution not tested on this Mac |
| iOS project/simulator build | Export and x86_64 build passed; runtime graphics blocked |
| Physical phones, thermal soak, Safari and low-end PCs | Not tested |

The API 35 emulator uses SwiftShader/ANGLE; its rendering performance is not a phone GPU measurement. iOS simulator success would likewise not establish physical-device performance.

## Performance protocol

```sh
godot --path . -- --smoke --benchmark
# Browser: http://localhost:8060/?benchmark
```

Reference load: 150 residents, seven storeys, 5,000 extra primitive objects and 10,000 extra catalogue definitions (10,007 total). All floors are visible; simulation runs at 20×. Static geometry is instanced; these objects are not 5,000 independent physics bodies. The stress objects are synthetic geometry, not 5,000 persisted furnishing slots. This measures steady-state overview rendering and active simulation, not construction spikes, arbitrary custom meshes or catalogue-search latency. The benchmark records monotonic wall-clock intervals between frames after 120 warm-up frames, then samples 3,600 frames. It reports p95, p99, maximum and simulation-step p95. Browser results appear in `window.courtyardBenchmark` and the console; native results are written to `artifacts/native-benchmark.json` when running from the project, or `user://benchmarks/native-benchmark.json` from an exported app.

Target: p95 ≤16.7 ms. Final exported macOS debug build (1440×900, M1 Max): **13.409 ms p95**, **14.364 ms p99**, **15.718 ms maximum** over 3,600 measured frames. Simulation p95 was **2.291 ms** across 625 ticks. This meets the local 60 fps frame-time target. Browser debug build at the same load: **9.2 ms p95**, **9.3 ms p99**, **9.7 ms maximum**; simulation p95 **3.6 ms** across 625 ticks. Both local targets passed. These are wall-clock measurements; earlier `_process(delta)` measurements were superseded because engine smoothing concealed some frame variation. A 30–60 second desktop run is not a sustained mobile thermal test. Mod behavior, mesh/material diversity, layout complexity, drivers and browser scheduling can change performance substantially.

## Remaining gates

- [ ] Provision and exercise an iOS device build; resolve simulator graphics startup.
- [ ] Run at least 15 minutes on physical iPhone 13/Pixel 7-class hardware, including low-power/thermal conditions.
- [ ] Check Safari, mobile file pickers, pinch gestures and safe-area behavior on real devices.
- [ ] Measure a low-end integrated-GPU desktop; add quality settings based on observed limits.
- [ ] Extend save migrations and pack fingerprints to arbitrary helper scripts/assets.
- [ ] Add physical utility capacities, stock inventories and richer employment/activity systems.

The current utility model tracks demand, expense and financial reliability. It does not yet simulate pipe networks or resource storage. See [model assumptions](model.md) for the implemented economic boundary.
