# ESP Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native iOS 26 landscape camera app that detects real people and draws Liquid-Glass "cheat game" ESP on them, with hidden menu, fake game layer and screen recording, built on GitHub Actions into an unsigned `.ipa` for esign.

**Architecture:** Pure-Swift `ESPCore` package (tracking, spatial math, game rules, settings — stdlib SIMD + Foundation only, tested with `swift test` on Linux/WSL and macOS CI) plus an `ESP` app target (ARKit capture, Vision perception, SwiftUI HUD, ReplayKit). Perception runs at ≤30 Hz off-main; the HUD re-projects world positions with the latest `ARCamera` every display frame.

**Tech Stack:** Swift 6.2, SwiftUI + Liquid Glass (`glassEffect`), ARKit (world tracking + `smoothedSceneDepth`), RealityKit `ARView` (camera feed only), Vision, ReplayKit, Photos, XcodeGen, GitHub Actions (`macos-26`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-19-esp-camera-design.md`

## Global Constraints

- Deployment target **iOS 26.0**, iPhone only, landscape only (LandscapeLeft + LandscapeRight), status bar hidden, home indicator auto-hidden.
- `ESPCore` must not import ARKit, Vision, UIKit, SwiftUI, simd, or CoreGraphics. Vectors are `SIMD2<Float>`/`SIMD3<Float>`/`SIMD4<Float>`; matrices are ESPCore `Mat4`.
- No network code, no face recognition, no special entitlements.
- Bundle ID `com.cam.espcamera`, display name `ESP`, `MARKETING_VERSION` 1.0, build number = `github.run_number`.
- Watermark default text: `ESP v2.6 · Undetected`. About row: `v2.6 · Undetected ✓`.
- First install uses preset **OFF** (bare camera).
- Glass elements use `.glassEffect(.regular.tint(...))` inside a `GlassEffectContainer`; lines (box, skeleton, snapline, FOV) are drawn in `Canvas`, 1.5 pt, round caps.
- State colors: `systemGreen` visible, `systemYellow` partially occluded, `systemRed` locked target.
- Max 8 players rendered, nearest first.
- Image-space coordinates in ESPCore are **normalized, top-left origin, in ARKit captured-image orientation** (= interface `landscapeRight`).
- ARKit camera space: +X right, +Y up, looking down −Z. Pixel (u, v) at depth d → camera point `((u−cx)/fx·d, −(v−cy)/fy·d, −d)`.
- Every `public struct` in ESPCore declares an explicit `public init` with all stored properties in declaration order (the app target cannot use internal memberwise inits).
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Verification Environments

- **Core tests:** `wsl -d Ubuntu -- bash -lc "cd '/mnt/c/Users/cam/Desktop/esp nghịch/Core' && swift test"`. If Task 1 could not install Swift in WSL, run Core tests only through CI (push, then `gh run watch`).
- **App build:** push to `main` on `https://github.com/peo1108/iosesp`, then `gh run watch --exit-status`. Expected: workflow `build` succeeds and uploads artifact `ESP-ipa`.
- **Device gate:** at the end of each milestone, the user downloads the artifact (`gh run download -n ESP-ipa`), signs it with esign, installs it on the iPhone 16 Pro Max, and runs that milestone's checklist. Do not start the next milestone's app task until the user reports the checklist.

## Review Focus

1. **Saved settings from an older build or corrupted JSON** → app launches normally. Missing keys take their defaults, garbage falls back to `Settings.default`. Test: Task 9 `decodesMissingKeysWithDefaults`, `garbageFallsBackToDefault`.
2. **Invalid depth (0, NaN, ∞, person closer than the LiDAR minimum)** → distance falls back to the estimate, never NaN on screen. Test: Task 4 `medianIgnoresInvalidSamples`, `medianNilWhenNoValidSamples`.
3. **Two people crossing or overlapping** → one detection never feeds two tracks, and two detections never merge into one track. Test: Task 5 `oneToOneMatching`.
4. **Shooting a player who is already eliminated, or whose track disappears mid-death** → no extra kill-feed entry. The kill feed entry survives the track's removal. Test: Task 12 `shootingEliminatedIsIgnored`, `killFeedSurvivesTrackRemoval`.
5. **Rotating between landscapeLeft and landscapeRight while tracking** → overlays stay on people (no 180° mirror) and island-side UI moves to the new island side. Device checklist item in Tasks 6 and 11.

---

## File Map

```
.gitignore  .gitattributes  project.yml
.github/workflows/build.yml
tools/make-icon.ps1
App/
  ESPApp.swift  Info.plist  Assets.xcassets/{AppIcon.appiconset, AccentColor.colorset}
  Capture/CaptureEngine.swift          ARSession owner, frame fan-out, LiDAR flag, interruptions
  Perception/PerceptionPipeline.swift  Vision requests → [RawDetection]
  Perception/RawDetection.swift        Vision-side detection (box + joints, normalized top-left)
  Spatial/SpatialResolver.swift        depth sampling, world position, occlusion → ESPCore.Detection
  Spatial/ARConversions.swift          simd_float4x4 ↔ Mat4, ARCamera → CameraIntrinsics
  Store/ESPStore.swift                 @MainActor @Observable: tracks, game, fps, tracking quality
  Store/ESPPipeline.swift              wires Capture → Perception → Spatial → Tracker → Store
  Store/SettingsStore.swift            UserDefaults persistence
  Recording/Recorder.swift             ReplayKit + Photos
  Input/GestureLayer.swift             3-finger double tap, 3-finger hold, 1-finger tap
  HUD/ScreenMapper.swift               image-normalized → view points, world → view points
  HUD/RootView.swift  CameraView.swift  ESPCanvas.swift  PlayerGlassViews.swift  ChamsView.swift
  HUD/OffscreenArrowsView.swift  RadarView.swift  StatsView.swift  FakeIslandView.swift
  HUD/WatermarkView.swift  CrosshairView.swift  KillFeedView.swift  DamageFXView.swift
  HUD/MenuPanel.swift  HintView.swift  SplashView.swift  ToastView.swift  PermissionView.swift
  HUD/Palette.swift                    system colors, accent mapping
Core/
  Package.swift
  Sources/ESPCore/  Vector.swift  Mat4.swift  Rect.swift  Joint.swift  Detection.swift  Track.swift
                    SplitMix64.swift  NameGenerator.swift  SpatialMath.swift  OneEuroFilter.swift
                    Tracker.swift  OffscreenArrow.swift  Radar.swift  Aimbot.swift
                    Settings.swift  ThermalPolicy.swift  HitTest.swift  GameEngine.swift
  Tests/ESPCoreTests/  one *Tests.swift per source file above that has logic
```

---

## Milestone M1 — Pipeline proves esign install

### Task 1: Repo scaffold, Core package, local Swift

**Files:**
- Create: `.gitignore`, `.gitattributes`, `Core/Package.swift`, `Core/Sources/ESPCore/Vector.swift`, `Core/Tests/ESPCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: package `ESPCore` (library product `ESPCore`, static), `public typealias Vec2 = SIMD2<Float>`, `Vec3 = SIMD3<Float>`, `Vec4 = SIMD4<Float>`, `func length(_ v: Vec3) -> Float`, `func normalize(_ v: Vec3) -> Vec3`, `func dot(_ a: Vec3, _ b: Vec3) -> Float` (all `public`, in `Vector.swift`).

- [ ] **Step 1: Write `.gitignore`** with `*.xcodeproj/`, `build/`, `.build/`, `DerivedData/`, `*.ipa`, `Payload/`, `.DS_Store`, `.swiftpm/`.
- [ ] **Step 2: Write `.gitattributes`** with `* text=auto eol=lf` and `*.png binary`.
- [ ] **Step 3: Write `Core/Package.swift`**: `// swift-tools-version: 6.2`, `platforms: [.iOS(.v26), .macOS(.v15)]`, library `ESPCore` (`type: .static`), target `ESPCore`, test target `ESPCoreTests`.
- [ ] **Step 4: Write the failing smoke test**

```swift
import Testing
@testable import ESPCore

@Test func vectorHelpers() {
    #expect(length(Vec3(3, 4, 0)) == 5)
    #expect(normalize(Vec3(0, 0, 2)) == Vec3(0, 0, 1))
    #expect(dot(Vec3(1, 2, 3), Vec3(4, 5, 6)) == 32)
}
```

- [ ] **Step 5: Install Swift in WSL (best effort).** In `wsl -d Ubuntu`, install swiftly (`curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz`, extract, `./swiftly init --assume-yes`). If platform detection rejects Ubuntu 26.04, retry with `--platform ubuntu24.04`. Install the apt dependencies swiftly lists. Expected: `swift --version` prints 6.2 or newer. If this still fails after one retry, record "Core tests via CI only" in the task report and continue.
- [ ] **Step 6: Run the test, verify it fails** (`swift test`, see Verification Environments). Expected: compile error, `length` undefined.
- [ ] **Step 7: Implement `Vector.swift`.**
- [ ] **Step 8: Run the test, verify it passes.** Expected: `1 test passed`.
- [ ] **Step 9: Commit:** `chore: scaffold repo and ESPCore package`.

### Task 2: App shell, camera, CI → first installable IPA

**Files:**
- Create: `project.yml`, `App/ESPApp.swift`, `App/Info.plist`, `App/Assets.xcassets/...`, `App/Capture/CaptureEngine.swift`, `App/HUD/CameraView.swift`, `App/HUD/RootView.swift`, `App/HUD/PermissionView.swift`, `tools/make-icon.ps1`, `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `ESPCore` package.
- Produces:
  - `@MainActor @Observable final class CaptureEngine: NSObject, ARSessionDelegate` with `let session: ARSession`, `private(set) var hasDepth: Bool`, `private(set) var authorization: CameraAuth` (`enum CameraAuth { case unknown, granted, denied }`), `private(set) var isInterrupted: Bool`, `func start()`, `func pause()`, and `var frameHandler: (@Sendable (ARFrame) -> Void)?`, called on `CaptureEngine.frameQueue` (a serial `DispatchQueue(label: "esp.frames", qos: .userInitiated)`, set as `session.delegateQueue`).
  - `struct CameraView: UIViewRepresentable` taking `session: ARSession`. Uses RealityKit `ARView(frame:cameraMode: .ar, automaticallyConfigureSession: false)`, assigns `arView.session = session`, `renderOptions` disable motion blur, DoF, grain and camera exposure effects.
  - `struct RootView: View`, the screen-level ZStack later tasks add layers to.

- [ ] **Step 1: Write `project.yml`.** Project `ESP`, `options.deploymentTarget.iOS: "26.0"`, `packages: { ESPCore: { path: Core } }`. Target `ESP`: type `application`, platform iOS, sources `App`, dependency `package: ESPCore`. Settings: `PRODUCT_BUNDLE_IDENTIFIER: com.cam.espcamera`, `INFOPLIST_FILE: App/Info.plist`, `TARGETED_DEVICE_FAMILY: "1"`, `SWIFT_VERSION: "6.0"`, `MARKETING_VERSION: "1.0"`, `CURRENT_PROJECT_VERSION: "$(BUILD_NUMBER)"` with default `1`, `CODE_SIGNING_ALLOWED: NO`. Scheme `ESP`.
- [ ] **Step 2: Write `App/Info.plist`** with `CFBundleDisplayName` `ESP`, `UISupportedInterfaceOrientations` = `[UIInterfaceOrientationLandscapeRight, UIInterfaceOrientationLandscapeLeft]`, `UIRequiresFullScreen` true, `UIStatusBarHidden` true, `UIRequiredDeviceCapabilities` `[arkit]`, `UILaunchScreen` (empty dict, black background color), and these usage strings:
  - `NSCameraUsageDescription`: "ESP dùng camera để nhận diện người và vẽ ESP."
  - `NSMicrophoneUsageDescription`: "Thu tiếng khi quay video."
  - `NSPhotoLibraryAddUsageDescription`: "Lưu video đã quay vào Ảnh."
- [ ] **Step 3: Write `tools/make-icon.ps1`** (System.Drawing, 1024×1024 PNG: black background, two concentric `systemBlue` rings plus a crosshair, approximating SF Symbol `scope`). Run it to produce `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png`, then write the single-size `Contents.json`.
- [ ] **Step 4: Implement `CaptureEngine`.**
  - `start()` requests `AVCaptureDevice.requestAccess(for: .video)` when undetermined.
  - Config: `ARWorldTrackingConfiguration`, `videoFormat` = highest-resolution format with `framesPerSecond == 60`, `frameSemantics = [.smoothedSceneDepth]` only if `supportsFrameSemantics(.smoothedSceneDepth)` (sets `hasDepth`), `planeDetection = []`.
  - `sessionWasInterrupted` / `sessionInterruptionEnded` toggle `isInterrupted`. On interruption end, re-run with `.resetTracking`.
  - The delegate's `session(_:didUpdate:)` forwards the frame to `frameHandler`. The handler must not keep the frame beyond processing.
- [ ] **Step 5: Implement `RootView`, `CameraView`, `PermissionView`, `ESPApp`.**
  - `RootView`: ZStack of `CameraView` (ignoresSafeArea), plus `PermissionView` when `authorization == .denied`. Black background, `.statusBarHidden()`, `.persistentSystemOverlays(.hidden)`.
  - `PermissionView`: glass card with SF Symbol `camera.fill`, title "Cần quyền camera", body "Vào Cài đặt → ESP → bật Camera.", and a glass button "Mở Cài đặt" opening `UIApplication.openSettingsURLString`.
  - `ESPApp`: start capture on `scenePhase == .active`, pause on `.background`.
- [ ] **Step 6: Write `.github/workflows/build.yml`.** Name `build`, triggers on `push` to `main` and `workflow_dispatch`, `runs-on: macos-26`. Steps:
  1. checkout
  2. `sudo xcode-select -s` the newest `/Applications/Xcode_26*.app`
  3. `brew install xcodegen`
  4. `cd Core && swift test`
  5. `xcodegen generate`
  6. `xcodebuild -project ESP.xcodeproj -scheme ESP -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build BUILD_NUMBER=${{ github.run_number }} CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build`
  7. `mkdir Payload && cp -R build/Build/Products/Release-iphoneos/ESP.app Payload/ && zip -qry ESP.ipa Payload`
  8. `actions/upload-artifact@v4`, name `ESP-ipa`, path `ESP.ipa`
- [ ] **Step 7: Get `workflow` scope.** Ask the user to run `gh auth refresh -h github.com -s workflow` in their own terminal (browser login). Verify with `gh auth status`: scopes include `workflow`.
- [ ] **Step 8: Commit and push:** `feat: app shell with ARKit camera and CI build`, then `git push -u origin main`.
- [ ] **Step 9: Verify CI** with `gh run watch --exit-status`. Expected: success, artifact `ESP-ipa`. If `macos-26` is unavailable, switch to `macos-15` and select Xcode 26 the same way. Fix compile errors from the log and push again until green.
- [ ] **Step 10: Device gate M1.** Give the user the artifact command. Checklist:
  - Signs and installs via esign
  - Camera full-screen landscape, both rotations fill the screen
  - Denying camera shows the glass permission card
  - Status bar and home indicator hidden

---

## Milestone M2 — Core ESP (box, name, distance)

### Task 3: Core models, RNG, identities

**Files:**
- Create: `Core/Sources/ESPCore/{Mat4,Rect,Joint,Detection,Track,SplitMix64,NameGenerator}.swift`
- Test: `Core/Tests/ESPCoreTests/{Mat4Tests,RectTests,NameGeneratorTests}.swift`

**Interfaces:**
- Produces:
  - `public struct Mat4: Equatable, Sendable` — column-major `var columns: (Vec4, Vec4, Vec4, Vec4)`, `init(columns:)`, `static let identity`, `static func * (Mat4, Vec4) -> Vec4`, `static func * (Mat4, Mat4) -> Mat4`, `var rigidInverse: Mat4` (transpose rotation, negate rotated translation), `var translation: Vec3`, `static func translation(_ t: Vec3) -> Mat4`, `static func rotationY(_ radians: Float) -> Mat4`.
  - `public struct Rect: Equatable, Sendable` — `x, y, width, height: Float`, `var center: Vec2`, `var minY`, `var maxY`, `func iou(_ other: Rect) -> Float`, `func contains(_ p: Vec2) -> Bool`, `static func bounding(_ points: [Vec2]) -> Rect?`.
  - `public enum Joint: String, CaseIterable, Sendable, Codable` — 19 cases: `nose, leftEye, rightEye, leftEar, rightEar, neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle`. `static let bones: [(Joint, Joint)]` = the 18 skeleton edges: nose–neck, neck–shoulders, shoulders–elbows, elbows–wrists, neck–root, root–hips, hips–knees, knees–ankles, nose–eyes, eyes–ears.
  - `public enum Occlusion: Sendable { case visible, partial }`
  - `public struct Detection: Sendable` — `box: Rect`, `joints: [Joint: Vec2]`, `worldPosition: Vec3?` (feet-center point), `distance: Float`, `distanceIsEstimated: Bool`, `heightMeters: Float`, `yaw: Float`, `occlusion: Occlusion`.
  - `public enum TrackState: Sendable { case tentative, confirmed, lost }`
  - `public struct Track: Identifiable, Sendable` — `id: Int`, `state`, `box`, `joints`, `worldPosition: Vec3?`, `velocity: Vec3`, `distance`, `distanceIsEstimated`, `heightMeters`, `yaw`, `occlusion`, `hits: Int`, `lastSeen: TimeInterval`, `var speed: Float { length(velocity) }`.
  - `public struct SplitMix64: RandomNumberGenerator` with `init(seed: UInt64)`.
  - `public struct PlayerIdentity: Equatable, Sendable { name: String; level: Int; rankSymbol: String }`
  - `public enum NameGenerator { static func identity(for id: Int) -> PlayerIdentity }`. Lists:
    - names: `xX_Sniper_Xx`, `NoobMaster69`, `Player_####` (4 random digits), `ProGamer_vn`, `HeadshotKing`, `CampingPro`, `LagSwitch`, `AFK_Bot`, `NotACheater`, `Sweaty_Tryhard`
    - level 1–99
    - rank one of `shield.fill`, `star.fill`, `crown.fill`, `bolt.fill`, `flame.fill`

- [ ] **Step 1: Write failing tests**

```swift
@Test func rigidInverseUndoesTransform() {
    let m = Mat4.translation(Vec3(1, 2, 3)) * Mat4.rotationY(.pi / 3)
    let p = Vec4(0.5, -1, 2, 1)
    let back = m.rigidInverse * (m * p)
    #expect(abs(back.x - p.x) < 1e-5 && abs(back.y - p.y) < 1e-5 && abs(back.z - p.z) < 1e-5)
}
@Test func iouOfIdenticalIsOneAndDisjointIsZero() {
    let a = Rect(x: 0.1, y: 0.1, width: 0.2, height: 0.4)
    #expect(a.iou(a) == 1)
    #expect(a.iou(Rect(x: 0.6, y: 0.6, width: 0.1, height: 0.1)) == 0)
    #expect(abs(a.iou(Rect(x: 0.2, y: 0.1, width: 0.2, height: 0.4)) - 1.0 / 3.0) < 1e-5)
}
@Test func boundingOfPoints() {
    #expect(Rect.bounding([Vec2(0.2, 0.3), Vec2(0.5, 0.9)]) == Rect(x: 0.2, y: 0.3, width: 0.3, height: 0.6))
    #expect(Rect.bounding([]) == nil)
}
@Test func identityIsDeterministicAndInRange() {
    #expect(NameGenerator.identity(for: 7) == NameGenerator.identity(for: 7))
    let ids = (0..<50).map(NameGenerator.identity(for:))
    #expect(ids.allSatisfy { (1...99).contains($0.level) })
    #expect(Set(ids.map(\.name)).count > 5)
}
@Test func skeletonHas18Bones() { #expect(Joint.bones.count == 18) }
```

- [ ] **Step 2: Run, verify fail** (undefined symbols).
- [ ] **Step 3: Implement the files listed.** `NameGenerator` seeds `SplitMix64(seed: UInt64(id) &* 0x9E3779B97F4A7C15)`.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit:** `feat(core): models, Mat4, Rect, name generator`.

### Task 4: SpatialMath

**Files:**
- Create: `Core/Sources/ESPCore/SpatialMath.swift`
- Test: `Core/Tests/ESPCoreTests/SpatialMathTests.swift`

**Interfaces:**
- Consumes: `Mat4`, `Vec2/3`.
- Produces:
  - `public struct CameraIntrinsics: Sendable` — `fx, fy, cx, cy: Float`, `imageSize: Vec2` (pixels), `func scaled(to size: Vec2) -> CameraIntrinsics`.
  - `public enum SpatialMath`:
    - `static func unproject(pixel: Vec2, depth: Float, intrinsics: CameraIntrinsics, cameraToWorld: Mat4) -> Vec3`
    - `static func project(world: Vec3, intrinsics: CameraIntrinsics, cameraToWorld: Mat4) -> Vec2?` (pixel; nil when the point is behind the camera, i.e. camera-space z ≥ −0.01)
    - `static func cameraSpace(world: Vec3, cameraToWorld: Mat4) -> Vec3`
    - `static func medianDepth(_ samples: [Float], confidences: [UInt8], minConfidence: UInt8 = 1) -> Float?` (ignores non-finite, ≤ 0.05, > 20 m)
    - `static func estimatedDistance(boxHeightPixels: Float, fy: Float, personHeight: Float = 1.70) -> Float`
    - `static func boxCorners(base: Vec3, height: Float, width: Float = 0.55, depth: Float = 0.35, yaw: Float) -> [Vec3]` (8 corners: 0–3 bottom ring at local half-extents (−w,−d), (+w,−d), (+w,+d), (−w,+d) rotated by yaw around +Y; 4–7 the same ring raised by height)
    - `static func isPartiallyOccluded(sampleDepths: [Float], personDepth: Float, margin: Float = 0.5, fraction: Float = 0.35) -> Bool` (only finite samples > 0.05 count)
    - `static func yaw(leftShoulder: Vec3, rightShoulder: Vec3) -> Float` (rotation around +Y of the shoulder line's normal, `atan2`)

- [ ] **Step 1: Write failing tests**

```swift
let K = CameraIntrinsics(fx: 1000, fy: 1000, cx: 960, cy: 720, imageSize: Vec2(1920, 1440))
@Test func centerPixelUnprojectsStraightAhead() {
    let p = SpatialMath.unproject(pixel: Vec2(960, 720), depth: 3, intrinsics: K, cameraToWorld: .identity)
    #expect(p == Vec3(0, 0, -3))
}
@Test func pixelBelowCenterIsBelowInWorld() {
    let p = SpatialMath.unproject(pixel: Vec2(960, 1220), depth: 2, intrinsics: K, cameraToWorld: .identity)
    #expect(abs(p.y - (-1)) < 1e-5)
}
@Test func projectRoundTrips() {
    let cam = Mat4.translation(Vec3(0.3, 1.4, 2)) * Mat4.rotationY(0.4)
    let w = SpatialMath.unproject(pixel: Vec2(400, 300), depth: 5, intrinsics: K, cameraToWorld: cam)
    let px = SpatialMath.project(world: w, intrinsics: K, cameraToWorld: cam)!
    #expect(abs(px.x - 400) < 0.01 && abs(px.y - 300) < 0.01)
}
@Test func behindCameraProjectsNil() {
    #expect(SpatialMath.project(world: Vec3(0, 0, 1), intrinsics: K, cameraToWorld: .identity) == nil)
}
@Test func scaledIntrinsics() {
    let s = K.scaled(to: Vec2(256, 192))
    #expect(abs(s.fx - 1000 * 256 / 1920) < 1e-3 && abs(s.cy - 720 * 192 / 1440) < 1e-3)
}
@Test func medianIgnoresInvalidSamples() {
    let d = SpatialMath.medianDepth([2, .nan, 0, .infinity, 2.2, 1.8, 50, 2.1], confidences: [2, 2, 2, 2, 2, 2, 2, 0])
    #expect(d == 2)  // valid: 2, 2.2, 1.8 → median 2 (2.1 dropped for low confidence)
}
@Test func medianNilWhenNoValidSamples() {
    #expect(SpatialMath.medianDepth([0, .nan], confidences: [2, 2]) == nil)
}
@Test func estimatedDistance() {
    #expect(abs(SpatialMath.estimatedDistance(boxHeightPixels: 425, fy: 1000) - 4) < 1e-4)
}
@Test func boxCornersHeightAndFootprint() {
    let c = SpatialMath.boxCorners(base: Vec3(0, 0, -3), height: 1.8, yaw: 0)
    #expect(c.count == 8)
    #expect(c[0...3].allSatisfy { $0.y == 0 } && c[4...7].allSatisfy { abs($0.y - 1.8) < 1e-5 })
    #expect(abs(length(c[0] - c[2]) - (0.55 * 0.55 + 0.35 * 0.35).squareRoot()) < 1e-4)
}
@Test func occlusionThreshold() {
    let near = [Float](repeating: 1.0, count: 4), far = [Float](repeating: 3.0, count: 6)
    #expect(SpatialMath.isPartiallyOccluded(sampleDepths: near + far, personDepth: 3))   // 40% > 35%
    #expect(!SpatialMath.isPartiallyOccluded(sampleDepths: [1, 1, 1] + far + [3], personDepth: 3)) // 30%
}
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement `SpatialMath.swift`** following the camera-space convention in Global Constraints.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit:** `feat(core): spatial math`.

### Task 5: OneEuroFilter and Tracker

**Files:**
- Create: `Core/Sources/ESPCore/OneEuroFilter.swift`, `Core/Sources/ESPCore/Tracker.swift`
- Test: `Core/Tests/ESPCoreTests/OneEuroFilterTests.swift`, `TrackerTests.swift`

**Interfaces:**
- Consumes: `Detection`, `Track`, `Rect`, `Vec3`.
- Produces:
  - `public struct OneEuroFilter<V: SIMD>: Sendable where V.Scalar == Float` — `init(minCutoff: Float = 1.0, beta: Float = 0.02, dCutoff: Float = 1.0)`, `mutating func filter(_ x: V, at t: TimeInterval) -> V` (first call returns x; a non-increasing t returns the last output), `mutating func reset()`.
  - `public struct TrackerConfig: Sendable` — `iouThreshold: Float = 0.3`, `worldMatchDistance: Float = 0.6`, `confirmHits = 3`, `lostAfter: TimeInterval = 0.7`, `forgetAfter: TimeInterval = 10`, `maxTracks = 8`.
  - `public final class Tracker` — `init(config: TrackerConfig = .init())`, `@discardableResult func update(_ detections: [Detection], at time: TimeInterval) -> [Track]` (returns confirmed and lost tracks, sorted by distance ascending, confirmed first; tentative tracks are internal), `func reset()`.

Matching algorithm (not determined by the signature):
1. Build all (track, detection) pairs with IoU ≥ `iouThreshold`, sorted by IoU descending, and assign greedily, each track and each detection at most once.
2. For the leftovers, pair by world distance < `worldMatchDistance` (both have positions), greedily by smallest distance. Lost tracks can be revived only this way.
3. Matched: filter box (`Vec4` of x, y, w, h), joints (`Vec2` each, joints absent in the detection are dropped), and world position (`Vec3`). Velocity = Δ filtered world position / Δt. Then `hits += 1`, `lastSeen = time`, and tentative → confirmed at `confirmHits`, lost → confirmed.
4. Unmatched tentative track is deleted. Confirmed track unseen for > `lostAfter` → lost. Lost track unseen for > `forgetAfter` → deleted.
5. Each unmatched detection creates a tentative track with the next id (monotonic from 1).
6. Return at most `maxTracks`.

- [ ] **Step 1: Write failing tests**

```swift
func det(_ x: Float, _ y: Float = 0.3, world: Vec3? = nil) -> Detection {
    Detection(box: Rect(x: x, y: y, width: 0.1, height: 0.4), joints: [:], worldPosition: world,
              distance: 3, distanceIsEstimated: false, heightMeters: 1.7, yaw: 0, occlusion: .visible)
}
@Test func filterPassesConstantSignal() {
    var f = OneEuroFilter<Vec2>()
    for i in 0..<10 { _ = f.filter(Vec2(1, 2), at: Double(i) / 30) }
    #expect(f.filter(Vec2(1, 2), at: 0.4) == Vec2(1, 2))
}
@Test func filterSmoothsJitter() {
    var f = OneEuroFilter<Vec2>()
    _ = f.filter(Vec2(0, 0), at: 0)
    #expect(f.filter(Vec2(1, 0), at: 1.0 / 30).x < 1)
}
@Test func confirmsAfterThreeHits() {
    let t = Tracker()
    #expect(t.update([det(0.2)], at: 0).isEmpty)
    #expect(t.update([det(0.2)], at: 0.033).isEmpty)
    let r = t.update([det(0.2)], at: 0.066)
    #expect(r.count == 1 && r[0].state == .confirmed && r[0].id == 1)
}
@Test func keepsIdWhileMoving() {
    let t = Tracker()
    for i in 0..<10 { t.update([det(0.2 + Float(i) * 0.01)], at: Double(i) / 30) }
    #expect(t.update([det(0.3)], at: 0.34).first?.id == 1)
}
@Test func oneToOneMatching() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2), det(0.26)], at: Double(i) / 30) }
    let r = t.update([det(0.21), det(0.25)], at: 0.1)
    #expect(Set(r.map(\.id)) == [1, 2])
}
@Test func losesThenForgets() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2)], at: Double(i) / 30) }
    #expect(t.update([], at: 0.9).first?.state == .lost)
    #expect(t.update([], at: 11).isEmpty)
}
@Test func revivesLostByWorldPosition() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2, world: Vec3(0, 0, -3))], at: Double(i) / 30) }
    t.update([], at: 1.5)
    let r = t.update([det(0.7, world: Vec3(0.3, 0, -3))], at: 2)
    #expect(r.first?.id == 1 && r.first?.state == .confirmed)
}
@Test func capsAtEightTracks() {
    let t = Tracker()
    let many = (0..<10).map { det(Float($0) * 0.1, y: 0) }
    for i in 0..<3 { t.update(many, at: Double(i) / 30) }
    #expect(t.update(many, at: 0.1).count == 8)
}
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement both files.**
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit:** `feat(core): one euro filter and tracker`.

### Task 6: Perception → Spatial → Tracker → box/name/distance on screen

**Files:**
- Create: `App/Perception/RawDetection.swift`, `App/Perception/PerceptionPipeline.swift`, `App/Spatial/ARConversions.swift`, `App/Spatial/SpatialResolver.swift`, `App/Store/ESPStore.swift`, `App/Store/ESPPipeline.swift`, `App/HUD/ScreenMapper.swift`, `App/HUD/Palette.swift`, `App/HUD/ESPCanvas.swift`, `App/HUD/PlayerGlassViews.swift`
- Modify: `App/HUD/RootView.swift`, `App/ESPApp.swift`

**Interfaces:**
- Consumes: `CaptureEngine.frameHandler`/`frameQueue`, `Tracker`, `SpatialMath`, `NameGenerator`, `Detection`, `Track`.
- Produces:
  - `struct RawDetection: Sendable { box: Rect; joints: [Joint: Vec2] }` — normalized, top-left origin, captured-image orientation.
  - `final class PerceptionPipeline` — `func detect(in pixelBuffer: CVPixelBuffer, wantMask: Bool) -> (people: [RawDetection], mask: CVPixelBuffer?)`. Uses `VNDetectHumanRectanglesRequest(upperBodyOnly = false)` and `VNDetectHumanBodyPoseRequest` on one handler with orientation `.up`. Joints with confidence < 0.3 are dropped. Each pose goes to the box with the highest IoU against `Rect.bounding(pose joints)`, minimum 0.1. Vision's bottom-left y is converted by `y' = 1 − y − h`. The `mask` slot stays nil until Task 8.
  - `extension Mat4 { init(_ m: simd_float4x4) }`, `extension CameraIntrinsics { init(_ camera: ARCamera) }`.
  - `struct SpatialResolver` — `func resolve(_ raw: [RawDetection], frame: ARFrame) -> [Detection]`. Samples `smoothedSceneDepth.depthMap` + `confidenceMap` at a 5×5 grid over the torso region (Rect.bounding of shoulders, neck and hips; fallback: the central 20% of the box) → `medianDepth`. Unprojects the box bottom-center at that depth for `worldPosition`. Height: unproject the top and bottom of the box at the same depth, |Δy|, clamped 1.0–2.2, fallback 1.70. Yaw from the shoulders when both exist, else facing the camera (`atan2` of the camera→person vector). Occlusion from a 6×6 grid over the box. Without depth: `estimatedDistance`, `distanceIsEstimated = true`, worldPosition still computed at the estimated depth.
  - `@MainActor @Observable final class ESPStore` — `var tracks: [Track]`, `var fps: Double` (perception results per second, EMA), `var trackingNormal: Bool`, `var hasDepth: Bool`, `func identity(for id: Int) -> PlayerIdentity` (cached `NameGenerator`).
  - `final class ESPPipeline` — owns `PerceptionPipeline`, `SpatialResolver`, `Tracker`. `init(capture: CaptureEngine, store: ESPStore)`. On each frame on `frameQueue`: skip if busy or < `1/targetHz` since the last run (`targetHz` default 30), else detect → resolve → `tracker.update(at: frame.timestamp)` → `Task { @MainActor in store.tracks = ... }`. Resets the tracker when tracking state is `.notAvailable` or on interruption. `var targetHz: Double`.
  - `struct ScreenMapper` — `init(frame: ARFrame, viewSize: CGSize, orientation: UIInterfaceOrientation)`, `func point(normalized: Vec2) -> CGPoint` (via `frame.displayTransform(for:viewportSize:)`), `func rect(_ r: Rect) -> CGRect`, `func point(world: Vec3) -> CGPoint?` (`ARCamera.projectPoint`, nil when behind the camera via `SpatialMath.cameraSpace(...).z ≥ 0`).
  - `enum Palette` — `visible = Color(.systemGreen)`, `partial = Color(.systemYellow)`, `locked = Color(.systemRed)`, `static func color(for: Track, locked: Bool) -> Color`.
  - `ESPCanvas` — `TimelineView(.animation)` + `Canvas`. Reads `session.currentFrame` for the mapper. Draws boxes for confirmed tracks: style `.corner` (corner length 22% of the shorter side) or `.full`, 1.5 pt, round caps.
  - `PlayerGlassViews` — per confirmed track: name tag capsule above the box (`Text("\(name) · Lv \(level)")` plus `Image(systemName: rankSymbol)`, `.font(.caption.weight(.semibold))`), and distance capsule below (`String(format: "%@%.1f m", estimated ? "~" : "", distance)`, `.monospacedDigit()`). All `.glassEffect(.regular.tint(stateColor.opacity(0.25)), in: .capsule)` inside one `GlassEffectContainer`, `.allowsHitTesting(false)`.
  - Until Task 10 adds settings, M2 shows box (corner), name and distance unconditionally.
- **Projection rule:** when the track has `worldPosition` and tracking is normal, the HUD positions the box from the projected world base point (bottom center) and keeps the detection's screen width/height scaled by `oldDistance/currentCameraDistance`. Otherwise it uses `mapper.rect(track.box)`. Glass views use the same anchor.

- [ ] **Step 1: Implement `RawDetection`, `PerceptionPipeline`, `ARConversions`, `SpatialResolver`.**
- [ ] **Step 2: Implement `ESPStore`, `ESPPipeline`, and wire them in `ESPApp`** (owned as `@State` and passed down).
- [ ] **Step 3: Implement `ScreenMapper`, `Palette`, `ESPCanvas`, `PlayerGlassViews`.** Add them to `RootView` above `CameraView`. Orientation comes from the window scene's `interfaceOrientation`, read in a small `UIViewRepresentable` probe or via `UIWindowScene` on geometry change.
- [ ] **Step 4: Commit, push, `gh run watch --exit-status`.** Expected: green. Fix and re-push until green. Commit message `feat: person detection with box, name and LiDAR distance`.
- [ ] **Step 5: Device gate M2.** Checklist:
  - Box follows a walking person without visible jitter
  - Distance within ~10% of a tape measure at 2 m and 5 m
  - Name stays the same while the person stays in view
  - Rotate the phone 180° while tracking: boxes stay on people (Review Focus 5)
  - A person walking out and back within 10 s keeps their name

---

## Milestone M3 — Full ESP visuals

### Task 7: Core HUD geometry (off-screen arrows, radar, aimbot)

**Files:**
- Create: `Core/Sources/ESPCore/{OffscreenArrow,Radar,Aimbot}.swift`
- Test: `Core/Tests/ESPCoreTests/{OffscreenArrowTests,RadarTests,AimbotTests}.swift`

**Interfaces:**
- Produces:
  - `public enum OffscreenArrow { static func place(target: Vec2, isBehind: Bool, viewSize: Vec2, inset: Float = 36) -> (point: Vec2, angle: Float)? }` — screen points, origin top-left. Returns nil when the target is inside the inset rect and not behind. When behind, mirror the target through the screen center first and always return an arrow, even if the mirrored point is on screen. The point is where the ray from the center toward the target crosses the inset rect. `angle = atan2(dy, dx)`.
  - `public struct RadarBlip: Equatable, Sendable { id: Int; position: Vec2 }` (−1…1, +y up = forward).
  - `public enum Radar { static func blips(_ players: [(id: Int, world: Vec3)], cameraToWorld: Mat4, range: Float) -> [RadarBlip] }`. Uses only the camera's heading (forward = −Z of the camera projected on the XZ plane), drops players beyond `range`, scales by `range`.
  - `public enum Aimbot { static func selectTarget(_ candidates: [(id: Int, aimPoint: Vec2)], center: Vec2, fovRadius: Float) -> Int? }` — nearest to the center within the radius.

- [ ] **Step 1: Write failing tests**

```swift
let view = Vec2(1000, 500)
@Test func onScreenHasNoArrow() { #expect(OffscreenArrow.place(target: Vec2(500, 250), isBehind: false, viewSize: view) == nil) }
@Test func rightSideArrowClampsToEdge() {
    let a = OffscreenArrow.place(target: Vec2(3000, 250), isBehind: false, viewSize: view)!
    #expect(a.point == Vec2(964, 250) && abs(a.angle) < 1e-5)
}
@Test func behindIsMirrored() {
    let a = OffscreenArrow.place(target: Vec2(700, 250), isBehind: true, viewSize: view)!
    #expect(a.point.x == 36)
}
@Test func radarForwardIsUp() {
    let b = Radar.blips([(1, Vec3(0, 0, -5))], cameraToWorld: .identity, range: 10)
    #expect(b == [RadarBlip(id: 1, position: Vec2(0, 0.5))])
}
@Test func radarRotatesWithHeading() {
    // camera turned 90° left (yaw +π/2): a player at world −Z now appears on the right
    let b = Radar.blips([(1, Vec3(0, 0, -5))], cameraToWorld: .rotationY(.pi / 2), range: 10)[0]
    #expect(abs(b.position.x - 0.5) < 1e-4 && abs(b.position.y) < 1e-4)
}
@Test func radarDropsOutOfRange() { #expect(Radar.blips([(1, Vec3(0, 0, -50))], cameraToWorld: .identity, range: 10).isEmpty) }
@Test func aimbotPicksNearestInFov() {
    let c: [(id: Int, aimPoint: Vec2)] = [(1, Vec2(600, 250)), (2, Vec2(530, 260)), (3, Vec2(900, 250))]
    #expect(Aimbot.selectTarget(c, center: Vec2(500, 250), fovRadius: 150) == 2)
    #expect(Aimbot.selectTarget([(id: 3, aimPoint: Vec2(900, 250))], center: Vec2(500, 250), fovRadius: 150) == nil)
}
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit:** `feat(core): offscreen arrows, radar, aimbot selection`.

### Task 8: Skeleton, Chams, snaplines, head dot, 3D box, off-screen arrows

**Files:**
- Create: `App/HUD/ChamsView.swift`, `App/HUD/OffscreenArrowsView.swift`
- Modify: `App/Perception/PerceptionPipeline.swift`, `App/Store/ESPPipeline.swift`, `App/Store/ESPStore.swift`, `App/HUD/ESPCanvas.swift`, `App/HUD/PlayerGlassViews.swift` (health bar), `App/HUD/RootView.swift`

**Interfaces:**
- Consumes: `Joint.bones`, `SpatialMath.boxCorners`, `OffscreenArrow.place`, `ScreenMapper`.
- Produces:
  - `PerceptionPipeline.detect(..., wantMask: true)` adds `VNGeneratePersonSegmentationRequest` (`qualityLevel = .balanced`, `outputPixelFormat = kCVPixelFormatType_OneComponent8`), run only when `wantMask` and ≥ 0.1 s since the last mask.
  - `ESPStore.chamsMask: CGImage?`, built off-main from the mask with Core Image: transform to the display via `displayTransform`, then false-color to accent at alpha 0.35.
  - `ESPStore.health(for id: Int) -> Float`, returning 100 until Task 13 wires `GameEngine`.
  - `ChamsView` — the mask image full-screen, overlaid with a slowly moving `LinearGradient` (accent → accent.opacity(0.4), 4 s period) using `.mask`, `.allowsHitTesting(false)`.
  - `ESPCanvas` gains:
    - skeleton: white 1.5 pt bones, joint dots r = 2.5 pt
    - head dot: r = 4 pt at `.nose`, fallback top-center + 8% of the box
    - snapline: from the bottom-center of the view to the box bottom-center
    - `.threeD` box: project the 8 `boxCorners`, draw 12 edges, fall back to `.full` when any corner is behind
  - `PlayerGlassViews` gains the vertical health capsule: 6 pt wide, 100% box height, 6 pt left of the box. Fill color interpolates `systemGreen` (100) → `systemYellow` (50) → `systemRed` (0), with a caption-2 number above it, `.animation(.spring(duration: 0.4, bounce: 0.3))`.
  - `OffscreenArrowsView` — for lost tracks with `worldPosition`, and confirmed tracks that are off-screen: glass circle 30 pt with `Image(systemName: "arrowtriangle.right.fill")` rotated by `angle`, plus a distance caption.

- [ ] **Step 1: Implement the mask path** (Perception → Store → `ChamsView`).
- [ ] **Step 2: Implement the canvas additions and the health capsule.**
- [ ] **Step 3: Implement `OffscreenArrowsView` and add both views to `RootView`** in this layer order: camera, chams, canvas, glass, arrows.
- [ ] **Step 4: Commit, push, CI green.** Message `feat: skeleton, chams, snaplines, 3D box, offscreen arrows`.
- [ ] **Step 5: Device gate M3.** Checklist:
  - Skeleton matches limbs
  - Chams covers bodies with a moving gradient
  - 3D box stays put on a standing person while you pan
  - Walk out of frame: an arrow appears at the correct edge, also when you turn 180°

---

## Milestone M4 — Hidden menu and settings

### Task 9: Settings, presets, thermal policy

**Files:**
- Create: `Core/Sources/ESPCore/Settings.swift`, `Core/Sources/ESPCore/ThermalPolicy.swift`
- Test: `Core/Tests/ESPCoreTests/SettingsTests.swift`, `ThermalPolicyTests.swift`

**Interfaces:**
- Produces:
  - `public enum BoxStyle: String, Codable, CaseIterable, Sendable { case corner, full, threeD }`
  - `public enum AimTarget: String, Codable, CaseIterable, Sendable { case head, chest }`
  - `public enum AccentName: String, Codable, CaseIterable, Sendable { case blue, purple, pink, red, orange, green, mint, cyan }`
  - `public enum Preset: String, Codable, CaseIterable, Sendable { case legit, rage, streamer, off, custom }`
  - `public struct Settings: Codable, Equatable, Sendable`. Fields and defaults:
    - `preset = .off`
    - ESP: `box = false`, `boxStyle = .corner`, `skeleton = false`, `chams = false`, `snaplines = false`, `name = false`, `health = false`, `distance = false`, `headDot = false`, `offscreenArrows = false`
    - Aim: `aimbot = false`, `fovCircle = false`, `fovRadius: Double = 150` (50…400), `smooth: Double = 0.5` (0…1), `aimTarget = .head`, `crosshair = false`
    - Game: `shooting = false`, `killFeed = false`, `naturalHealth = false`
    - HUD: `stats = false`, `radar = false`, `radarRange: Double = 15` (5…30), `fakeIsland = false`, `watermark = false`, `watermarkText = "ESP v2.6 · Undetected"`
    - Recording: `recordButton = false`, `recordIndicator = false`, `microphone = false`, `haptics = true`
    - `accent = .blue`
    - `hasSeenHint = false`
    - Custom `init(from:)` uses `decodeIfPresent` for every key, defaulting per field.
    - `static let default: Settings`
    - `mutating func apply(_ preset: Preset)` sets only the visibility toggles plus `boxStyle`, and keeps watermarkText, ranges, smooth, aimTarget, accent, microphone, haptics and hasSeenHint
    - `mutating func set<V>(_ keyPath: WritableKeyPath<Settings, V>, _ value: V)` assigns and sets `preset = .custom` (unless the keyPath is `\.preset` or `\.hasSeenHint`)
    - `static func decodeOrDefault(_ data: Data?) -> Settings`
  - Preset table (everything not listed is false):

| Preset | true | boxStyle |
|---|---|---|
| legit | box, distance | corner |
| rage | all visibility toggles: every ESP flag, aimbot, fovCircle, crosshair, shooting, killFeed, naturalHealth, stats, radar, fakeIsland, watermark, recordButton, recordIndicator | threeD |
| streamer | box, name, health, distance, skeleton, watermark | corner |
| off | none | corner |

  - `public enum ThermalLevel: Sendable { case nominal, fair, serious, critical }`
  - `public struct PerceptionBudget: Equatable, Sendable { hz: Double; chamsAllowed: Bool; showHeatWarning: Bool }`
  - `public enum ThermalPolicy { static func budget(_ level: ThermalLevel, isRecording: Bool) -> PerceptionBudget }` — nominal 30/true/false, fair 20/true/false, serious 10/false/false, critical 5/false/true. Recording caps hz at 20.

- [ ] **Step 1: Write failing tests**

```swift
@Test func defaultIsOff() { #expect(Settings.default.preset == .off && !Settings.default.box) }
@Test func legitPreset() {
    var s = Settings.default; s.apply(.legit)
    #expect(s.box && s.distance && !s.name && !s.skeleton && s.boxStyle == .corner && s.preset == .legit)
}
@Test func ragePresetEnablesEverything() {
    var s = Settings.default; s.apply(.rage)
    #expect(s.aimbot && s.chams && s.radar && s.shooting && s.recordButton && s.boxStyle == .threeD)
}
@Test func streamerHidesHud() {
    var s = Settings.default; s.apply(.streamer)
    #expect(s.skeleton && s.watermark && !s.stats && !s.recordButton && !s.recordIndicator)
}
@Test func presetKeepsPersonalization() {
    var s = Settings.default; s.watermarkText = "hi"; s.fovRadius = 300; s.accent = .pink
    s.apply(.rage); s.apply(.off)
    #expect(s.watermarkText == "hi" && s.fovRadius == 300 && s.accent == .pink && !s.box)
}
@Test func editingMakesCustom() {
    var s = Settings.default; s.apply(.legit); s.set(\.skeleton, true)
    #expect(s.preset == .custom && s.skeleton)
}
@Test func decodesMissingKeysWithDefaults() {
    let s = Settings.decodeOrDefault(#"{"radar":true}"#.data(using: .utf8))
    #expect(s.radar && s.watermarkText == "ESP v2.6 · Undetected" && s.haptics && s.preset == .off)
}
@Test func garbageFallsBackToDefault() {
    #expect(Settings.decodeOrDefault(Data("nope".utf8)) == .default)
    #expect(Settings.decodeOrDefault(nil) == .default)
}
@Test func thermalBudgets() {
    #expect(ThermalPolicy.budget(.nominal, isRecording: false) == PerceptionBudget(hz: 30, chamsAllowed: true, showHeatWarning: false))
    #expect(ThermalPolicy.budget(.serious, isRecording: false).chamsAllowed == false)
    #expect(ThermalPolicy.budget(.nominal, isRecording: true).hz == 20)
    #expect(ThermalPolicy.budget(.critical, isRecording: true) == PerceptionBudget(hz: 5, chamsAllowed: false, showHeatWarning: true))
}
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit:** `feat(core): settings, presets, thermal policy`.

### Task 10: SettingsStore, gestures, menu, first-run hint

**Files:**
- Create: `App/Store/SettingsStore.swift`, `App/Input/GestureLayer.swift`, `App/HUD/MenuPanel.swift`, `App/HUD/HintView.swift`
- Modify: `App/HUD/RootView.swift`, `App/HUD/ESPCanvas.swift`, `App/HUD/PlayerGlassViews.swift`, `App/HUD/ChamsView.swift`, `App/HUD/OffscreenArrowsView.swift`, `App/HUD/Palette.swift`, `App/Store/ESPPipeline.swift`

**Interfaces:**
- Consumes: `Settings`, `Preset`, `ThermalPolicy`.
- Produces:
  - `@MainActor @Observable final class SettingsStore` — `var settings: Settings` (`didSet` saves JSON to `UserDefaults.standard` key `esp.settings.v1`), `init()` loads via `Settings.decodeOrDefault`, `func binding<V>(_ kp: WritableKeyPath<Settings, V>) -> Binding<V>` (writes through `settings.set`), `func apply(_ preset: Preset)` (plus haptic).
  - `Palette.accent(_ name: AccentName) -> Color`, mapping to the matching `UIColor.system*`.
  - `struct GestureLayer: UIViewRepresentable` — a transparent view with:
    - `UITapGestureRecognizer` (`numberOfTouchesRequired = 3`, `numberOfTapsRequired = 2`) → `onToggleMenu()`
    - `UILongPressGestureRecognizer` (`numberOfTouchesRequired = 3`, `minimumPressDuration = 0.8`) → `onToggleRecording()` on `.began`
    - `UITapGestureRecognizer` (1 touch, 1 tap) → `onTap(CGPoint)`
    - all recognizers recognize simultaneously
  - `MenuPanel` — trailing-edge panel, width `0.4 × screen width`, full height inside the safe area, `.glassEffect(.regular, in: .rect(cornerRadius: 28))`. Slides in with `.move(edge: .trailing)` and `.spring(duration: 0.35, bounce: 0.15)`. Scrollable sections in this order:
    - Preset: segmented LEGIT · RAGE · STREAMER · OFF, with "Custom" caption when `.custom`
    - ESP, Aim, Game, HUD, Quay video: one row per Settings field, `Toggle` / `Picker` / `Slider` with the value in `.monospacedDigit()`, `TextField` for the watermark
    - Màu chủ đạo: accent circles
    - Về app: `v2.6 · Undetected ✓` plus the note "Nếu bật Trợ năng → Thu phóng, iOS sẽ chiếm cử chỉ chạm 3 ngón."
    - Header: SF Symbol `scope` + "ESP Menu"
    - Every toggle change plays `.sensoryFeedback(.selection)` when `haptics` is on
  - `HintView` — centered glass capsule "Chạm 2 lần bằng 3 ngón để mở menu" with SF Symbol `hand.tap`. Shown when `!hasSeenHint`, fades out after 3 s, then sets `hasSeenHint = true`.
  - Root layer order (bottom → top): camera, chams, canvas, glass, arrows, `GestureLayer`, menu, hint. While the menu is open, `onTap` closes it.
  - All HUD views gate on their Settings flag. Chams also requires `budget.chamsAllowed`. `ESPPipeline.targetHz` and `wantMask` come from `ThermalPolicy.budget(ProcessInfo.processInfo.thermalState → ThermalLevel, isRecording:)`, re-read on `ProcessInfo.thermalStateDidChangeNotification`.

- [ ] **Step 1: Implement `SettingsStore` and `Palette.accent`.**
- [ ] **Step 2: Implement `GestureLayer`.**
- [ ] **Step 3: Implement `MenuPanel` and `HintView`, wire them in `RootView`.**
- [ ] **Step 4: Gate every existing HUD element on its setting and connect the thermal budget.**
- [ ] **Step 5: Commit, push, CI green.** Message `feat: hidden glass menu, presets, 3-finger gestures`.
- [ ] **Step 6: Device gate M4.** Checklist:
  - Fresh install: bare camera plus the hint, hint never shown again
  - 3-finger double tap opens and closes the menu, tapping outside closes it
  - Every toggle changes the view live
  - Each preset looks as in the table, OFF gives a bare camera
  - Settings survive a force-quit

---

## Milestone M5 — HUD and aimbot

### Task 11: Stats, radar, fake island, watermark, crosshair, FOV, aimbot

**Files:**
- Create: `App/HUD/StatsView.swift`, `App/HUD/RadarView.swift`, `App/HUD/FakeIslandView.swift`, `App/HUD/WatermarkView.swift`, `App/HUD/CrosshairView.swift`
- Modify: `App/HUD/RootView.swift`, `App/Store/ESPStore.swift`, `App/HUD/Palette.swift`

**Interfaces:**
- Consumes: `Radar.blips`, `Aimbot.selectTarget`, `Settings`, `ScreenMapper`.
- Produces:
  - `ESPStore.lockedID: Int?`, updated each display tick by `Aimbot.selectTarget`. Aim point: projected `.nose`, or the box top + 10% (head), or the neck/shoulder midpoint (chest) per `aimTarget`. Center = view center, radius = `fovRadius`. Locked tracks use `Palette.locked`.
  - `ESPStore.aimPoint: CGPoint` — spring-smoothed toward the locked aim point or back to center. `Animation.spring(response: 0.08 + smooth × 0.5, dampingFraction: 0.85)`. A `.rigid` haptic fires when `lockedID` changes from nil to a value.
  - `StatsView` — top-leading glass capsule: `Image(systemName: "scope")`, `ESP`, `\(Int(fps))fps`, `\(count) players`. Shows "Scanning…" with a pulsing `dot.radiowaves.left.and.right` when there are 0 players. Shows "Low tracking" (SF `exclamationmark.triangle.fill`, yellow) when `!trackingNormal`. Shows "Máy đang nóng" when `budget.showHeatWarning`.
  - `RadarView` — 110 pt glass circle below the stats, rings at 1/3 and 2/3, a 60° FOV cone (accent at 0.15), a center triangle, blips as 6 pt dots (red if locked), and a rotating sweep line (3 s period).
  - `FakeIslandView` — a capsule on the island side, vertically centered. Island side = the horizontal safe-area edge with the larger inset. Collapsed it's 36×36 glass with a `scope` glyph. With `lockedID` set it expands (spring) to `🎯 Locked · 12.4 m`, using SF `target` and the locked distance.
  - `WatermarkView` — bottom-leading `watermarkText`, `.caption.monospaced()`, glass capsule, opacity 0.8.
  - `CrosshairView` — 18 pt plus-sign crosshair at `aimPoint` when `crosshair` is on. FOV circle (1.5 pt, accent at 0.6) of radius `fovRadius` at the view center when `fovCircle` is on.
  - `RadarView` and 3D boxes hide while `!trackingNormal` (2D boxes keep running).
  - Kill feed goes top-trailing in Task 13. When the island is on the trailing side, the kill feed sits below the island's vertical zone.

- [ ] **Step 1: Implement the aimbot state in `ESPStore`, plus `CrosshairView`.**
- [ ] **Step 2: Implement `StatsView`, `RadarView`, `FakeIslandView`, `WatermarkView`, gated by settings.**
- [ ] **Step 3: Commit, push, CI green.** Message `feat: HUD, radar, fake island, aimbot`.
- [ ] **Step 4: Device gate M5.** Checklist:
  - Radar dots rotate correctly as you turn
  - Aimbot snaps to the person nearest the center within FOV, with a haptic on lock
  - Island expands on lock and sits on the real island's side in both rotations (Review Focus 5)
  - Watermark text edits live

---

## Milestone M6 — Game layer

### Task 12: Core hit test and game engine

**Files:**
- Create: `Core/Sources/ESPCore/HitTest.swift`, `Core/Sources/ESPCore/GameEngine.swift`
- Test: `Core/Tests/ESPCoreTests/HitTestTests.swift`, `GameEngineTests.swift`

**Interfaces:**
- Consumes: `Track`, `Rect`, `Joint`, `PlayerIdentity`, `NameGenerator`, `SplitMix64`.
- Produces:
  - `public struct HitTarget: Equatable, Sendable { id: Int; isHead: Bool }`
  - `public enum HitTest { static func target(at p: Vec2, boxes: [(id: Int, box: Rect, head: Vec2?)]) -> HitTarget? }` — screen-space rects. Head = within `0.25 × box.width` of `head`, or (no head) inside the top 18% of the box. When boxes overlap, the smallest box wins.
  - `public struct GameConfig: Sendable` — `maxHP: Float = 100`, `bodyDamage: ClosedRange<Int> = 18...34`, `headshotDamage: Float = 100`, `regenPerSecond: Float = 5`, `regenDelay: TimeInterval = 3`, `regenMaxSpeed: Float = 0.3`, `drainPerSecond: Float = 4`, `drainMinSpeed: Float = 1.5`, `drainFloor: Float = 10`, `respawnDelay: TimeInterval = 5`, `killFeedMax = 4`, `killFeedTTL: TimeInterval = 6`.
  - `public struct PlayerStatus: Equatable, Sendable { id: Int; hp: Float; lastDamageAt: TimeInterval?; eliminatedAt: TimeInterval?; var isEliminated: Bool }`
  - `public struct DamageEvent: Equatable, Sendable { trackID: Int; amount: Int; isHeadshot: Bool; killed: Bool; time: TimeInterval }`
  - `public struct KillFeedEntry: Equatable, Sendable, Identifiable { id: Int; victim: String; distance: Float; isHeadshot: Bool; time: TimeInterval }`
  - `public final class GameEngine`:
    - `init(config: GameConfig = .init(), seed: UInt64 = UInt64.random(in: 0...UInt64.max))`
    - `func sync(_ tracks: [Track], at time: TimeInterval, naturalHealth: Bool)`: create statuses for new confirmed ids, delete statuses whose id is absent from `tracks`, respawn eliminated at `respawnDelay`. If `naturalHealth`: regen when `time − lastDamage ≥ regenDelay` and speed < `regenMaxSpeed`, drain when speed > `drainMinSpeed`, never below `drainFloor`, never above maxHP. Prune kill feed by TTL.
    - `func shoot(_ target: HitTarget, distance: Float, at time: TimeInterval) -> DamageEvent?` — nil if unknown or eliminated. On a kill, appends a kill-feed entry (keep the newest `killFeedMax`).
    - `func status(_ id: Int) -> PlayerStatus?`
    - `private(set) var killFeed: [KillFeedEntry]`

- [ ] **Step 1: Write failing tests**

```swift
func track(_ id: Int, speed: Float = 0) -> Track { /* confirmed, box 0.2,0.2,0.1,0.4, velocity Vec3(speed,0,0) */ }
@Test func headHitByJointRadius() {
    let b: [(id: Int, box: Rect, head: Vec2?)] = [(1, Rect(x: 100, y: 100, width: 80, height: 240), Vec2(140, 120))]
    #expect(HitTest.target(at: Vec2(150, 125), boxes: b) == HitTarget(id: 1, isHead: true))
    #expect(HitTest.target(at: Vec2(140, 250), boxes: b) == HitTarget(id: 1, isHead: false))
    #expect(HitTest.target(at: Vec2(10, 10), boxes: b) == nil)
}
@Test func headHitFallsBackToTopOfBox() {
    let b: [(id: Int, box: Rect, head: Vec2?)] = [(1, Rect(x: 0, y: 0, width: 100, height: 100), nil)]
    #expect(HitTest.target(at: Vec2(50, 10), boxes: b)?.isHead == true)
}
@Test func bodyDamageInRange() {
    let g = GameEngine(seed: 1); g.sync([track(1)], at: 0, naturalHealth: false)
    let e = g.shoot(HitTarget(id: 1, isHead: false), distance: 3, at: 0.1)!
    #expect((18...34).contains(e.amount) && g.status(1)!.hp == 100 - Float(e.amount))
}
@Test func headshotKillsAndFeeds() {
    let g = GameEngine(seed: 1); g.sync([track(1)], at: 0, naturalHealth: false)
    let e = g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 0.1)!
    #expect(e.killed && e.isHeadshot && g.killFeed.count == 1 && g.status(1)!.isEliminated)
}
@Test func shootingEliminatedIsIgnored() {
    let g = GameEngine(seed: 1); g.sync([track(1)], at: 0, naturalHealth: false)
    _ = g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 0.1)
    #expect(g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 0.2) == nil && g.killFeed.count == 1)
}
@Test func respawnsAfterFiveSeconds() {
    let g = GameEngine(seed: 1); g.sync([track(1)], at: 0, naturalHealth: false)
    _ = g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 1)
    g.sync([track(1)], at: 5.9, naturalHealth: false); #expect(g.status(1)!.isEliminated)
    g.sync([track(1)], at: 6.1, naturalHealth: false); #expect(g.status(1)!.hp == 100 && !g.status(1)!.isEliminated)
}
@Test func drainStopsAtFloor() {
    let g = GameEngine(seed: 1); g.sync([track(1, speed: 2)], at: 0, naturalHealth: true)
    for i in 1...300 { g.sync([track(1, speed: 2)], at: Double(i) * 0.1, naturalHealth: true) }
    #expect(g.status(1)!.hp == 10)
}
@Test func regenWaitsThreeSecondsAfterDamage() {
    let g = GameEngine(seed: 1); g.sync([track(1)], at: 0, naturalHealth: true)
    _ = g.shoot(HitTarget(id: 1, isHead: false), distance: 3, at: 1)
    let hp = g.status(1)!.hp
    g.sync([track(1)], at: 3.5, naturalHealth: true); #expect(g.status(1)!.hp == hp)   // 2.5 s after hit: no regen
    g.sync([track(1)], at: 4.5, naturalHealth: true); #expect(g.status(1)!.hp > hp)
}
@Test func noNaturalHealthWhenDisabled() {
    let g = GameEngine(seed: 1); g.sync([track(1, speed: 2)], at: 0, naturalHealth: false)
    g.sync([track(1, speed: 2)], at: 10, naturalHealth: false); #expect(g.status(1)!.hp == 100)
}
@Test func killFeedSurvivesTrackRemoval() {
    let g = GameEngine(seed: 1); g.sync([track(1)], at: 0, naturalHealth: false)
    _ = g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 0.1)
    g.sync([], at: 1, naturalHealth: false)
    #expect(g.status(1) == nil && g.killFeed.count == 1)
    g.sync([], at: 7, naturalHealth: false); #expect(g.killFeed.isEmpty)
}
@Test func killFeedKeepsNewestFour() {
    let g = GameEngine(seed: 1); let ts = (1...6).map { track($0) }; g.sync(ts, at: 0, naturalHealth: false)
    for id in 1...6 { _ = g.shoot(HitTarget(id: id, isHead: true), distance: 2, at: 0.1) }
    #expect(g.killFeed.map(\.id).count == 4)
}
```

  (The kill-feed victim name comes from `NameGenerator.identity(for:)`. `KillFeedEntry.id` is a monotonic counter.)

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit:** `feat(core): hit test and game engine`.

### Task 13: Shooting, damage FX, elimination, kill feed

**Files:**
- Create: `App/HUD/DamageFXView.swift`, `App/HUD/KillFeedView.swift`
- Modify: `App/Store/ESPStore.swift`, `App/HUD/RootView.swift`, `App/HUD/PlayerGlassViews.swift`, `App/HUD/ESPCanvas.swift`

**Interfaces:**
- Consumes: `GameEngine`, `HitTest`, `GestureLayer.onTap`.
- Produces:
  - `ESPStore.game: GameEngine`. `sync` runs on every tracks update with `settings.naturalHealth`. `health(for:)` now reads the engine (eliminated → 0).
  - `ESPStore.fx: [DamageFX]` (`struct DamageFX: Identifiable { id: UUID; point: CGPoint; text: String; isHeadshot: Bool; born: Date }`), pruned after 1.2 s. `ESPStore.lastElimination: (name: String, time: Date)?`.
  - `onTap` (menu closed, `shooting` on): build screen boxes with `ScreenMapper` (the same anchors as the HUD), `HitTest.target`, then `game.shoot`. On an event: append FX (`-\(amount)` or `HEADSHOT -100`, red), hitmarker at the tap, `.impact(.medium)` haptic (`.heavy` on a kill).
  - `DamageFXView`:
    - floating numbers rise 40 pt and fade over 1.2 s
    - hitmarker: four 10 pt diagonal strokes, fade in 0.25 s
    - elimination: 24 accent particles burst from the box center over 0.6 s, plus a centered glass banner "ELIMINATED" (`.title2.weight(.heavy)`, red tint) for 1.5 s
  - Eliminated players hide box, glass and skeleton until respawn.
  - `KillFeedView` — top-trailing stack (newest on top, max 4) of glass capsules: `You` + `Image(systemName: "scope")` + victim + `· 12.4m` (+ SF `scope` in red if headshot). Each fades with `killFeedTTL`, gated by `killFeed`.

- [ ] **Step 1: Wire `GameEngine` and the tap → shoot path in `ESPStore`.**
- [ ] **Step 2: Implement `DamageFXView` and `KillFeedView`, and hide eliminated players.**
- [ ] **Step 3: Commit, push, CI green.** Message `feat: shooting, damage, eliminations, kill feed`.
- [ ] **Step 4: Device gate M6.** Checklist:
  - Tap body: number and health drop
  - Tap head: HEADSHOT, burst, banner, kill-feed line
  - Respawn after 5 s with full health
  - Walking fast drains health but never below 10

---

## Milestone M7 — Recording and polish

### Task 14: Recorder, splash, toast, final polish

**Files:**
- Create: `App/Recording/Recorder.swift`, `App/HUD/SplashView.swift`, `App/HUD/ToastView.swift`
- Modify: `App/HUD/RootView.swift`, `App/ESPApp.swift`, `App/Store/ESPPipeline.swift`

**Interfaces:**
- Consumes: `GestureLayer.onToggleRecording`, `Settings.recordButton/recordIndicator/microphone/haptics`, `ThermalPolicy`.
- Produces:
  - `@MainActor @Observable final class Recorder`:
    - `private(set) var isRecording: Bool`
    - `func toggle(microphone: Bool) async`: start via `RPScreenRecorder.shared().startRecording`. Stop via `stopRecording(withOutput: tmpURL)` with `tmpURL = FileManager.default.temporaryDirectory/ESP-<yyyyMMdd-HHmmss>.mp4`, then `PHPhotoLibrary.requestAuthorization(for: .addOnly)` and `PHAssetCreationRequest` (video from file), then delete the temp file on success.
    - `var onResult: ((ToastMessage) -> Void)?` — `.saved` → "Đã lưu vào Ảnh", `.failed(String)` → "Lưu thất bại" + a "Thử lại" action that re-runs the save of the kept temp file.
    - Stops and saves when the app goes to background while recording.
  - Starting a recording closes the menu. `ESPPipeline` reads `isRecording` for the thermal budget.
  - Record button: 64 pt circle on the side opposite the island, vertically centered. Glass ring with a red inner circle that morphs to a rounded square while recording (`.spring`). Shown when `recordButton` is on. The red 10 pt glass dot top-center while recording shows when `recordIndicator` is on. Toggling plays `.impact(.rigid)` when `haptics` is on.
  - `ToastView` — bottom-center glass capsule, auto-hides after 2.5 s.
  - `SplashView`:
    - ~2 s total, tap to skip
    - black background, SF `scope` 64 pt with an accent glow (`.shadow(color: accent, radius: 20)` pulsing)
    - SF Mono lines appear every 0.45 s: `Injecting… ✓`, `Bypassing anti-cheat… ✓`, `Loading offsets… ✓`
    - glass progress capsule fills over the 2 s
    - shown once per cold launch, before `RootView` content (the camera starts behind it)

- [ ] **Step 1: Implement `Recorder` and `ToastView`, and wire the gesture, button and indicator.**
- [ ] **Step 2: Implement `SplashView`.**
- [ ] **Step 3: Commit, push, CI green.** Message `feat: screen recording, splash, toasts`.
- [ ] **Step 4: Device gate M7 (final).** Checklist:
  - 3-finger hold starts and stops recording with a haptic
  - The saved video in Ảnh shows the glass HUD and ESP
  - A 2-minute recording with RAGE has no heavy stutter
  - Leaving the app while recording saves the video
  - Denying Photos shows the failure toast, and "Thử lại" works after granting
  - Splash plays once and can be skipped
  - After 10 minutes of use the phone gets warm but the app stays usable (heat warning shows only at critical)
