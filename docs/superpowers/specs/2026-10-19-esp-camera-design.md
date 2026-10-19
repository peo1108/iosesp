# ESP Camera — Thiết kế

- **Ngày:** 2026-10-19
- **Trạng thái:** Đã chốt thiết kế qua chat, chờ duyệt spec
- **Thiết bị mục tiêu:** iPhone 16 Pro Max (có LiDAR), iOS 26.5.2

## 1. Mục tiêu

App iOS native chạy camera, nhận diện người thật và vẽ "ESP" lên họ giống cheat game bắn súng, để **quay video troll / đăng TikTok cho vui**.

Tiêu chí thành công:
- Nhìn ngầu và "tin được" trên video. Không cần độ chính xác tuyệt đối, nhưng box phải bám người, không rung, không nhảy.
- Giao diện **đậm chất Apple** (Liquid Glass của iOS 26, SF Pro, SF Symbols), nội dung thì đúng kiểu cheat game.
- Có thể ẩn sạch mọi thứ để app trông như camera bình thường, rồi "lộ hack" khi cần.
- Quay được video có toàn bộ overlay, lưu vào Ảnh.

Không phải mục tiêu: nhận diện danh tính người thật (face recognition, gắn tên thật). Mọi xử lý nằm trên máy, app **không có kết nối mạng**.

## 2. Ràng buộc

| Ràng buộc | Hệ quả |
|---|---|
| Dev trên Windows, không có Mac | Không dùng Xcode GUI. Project sinh bằng **XcodeGen** từ `project.yml`, build trên **GitHub Actions (macOS runner)** |
| Cài qua chứng chỉ esign | CI xuất **`.ipa` chưa ký**. Không dùng entitlement đặc biệt (không App Groups, không iCloud, không Push) |
| iOS 26, máy có LiDAR | Deployment target **iOS 26.0**. Dùng `.glassEffect()` và độ sâu LiDAR. Vẫn có fallback khi không có độ sâu |
| Chỉ màn hình ngang | `UISupportedInterfaceOrientations` = LandscapeLeft + LandscapeRight, ẩn status bar, tự ẩn home indicator |
| Không có simulator cho camera | Logic thuần có unit test chạy trên CI. Phần camera và UI test tay trên máy thật theo checklist |

## 3. Kiến trúc

### 3.1 Luồng dữ liệu

```
ARSession (world tracking + smoothedSceneDepth, 60fps)
   │  ARFrame: capturedImage, depthMap, confidenceMap, camera (intrinsics, transform)
   ▼
PerceptionPipeline   (queue nền, 30Hz, giảm theo nhiệt độ máy)
   │  [Detection]: box chuẩn hoá, 19 khớp xương (có confidence), mask người (10Hz)
   ▼
SpatialResolver      (cùng queue)
   │  + khoảng cách (m), vị trí world (simd_float3), trạng thái che khuất
   ▼
Tracker              (ESPCore, logic thuần)
   │  [Track]: ID ổn định, box/khớp đã làm mượt, vận tốc, lastSeen
   ▼
GameEngine           (ESPCore, logic thuần)
   │  máu, rank/tên, bị khóa mục tiêu, bị hạ gục, kill feed
   ▼
ESPStore (@MainActor, @Observable)  ← snapshot mới nhất
   ▼
HUD (SwiftUI): TimelineView(.animation) chiếu lại vị trí world bằng camera của frame hiện tại
```

**Điểm then chốt:** giữa hai lần nhận diện (30Hz), overlay vẫn chạy ở 60/120Hz. Mỗi frame, overlay **chiếu lại vị trí 3D** của từng người bằng `ARCamera.projectPoint` với camera mới nhất. Nhờ vậy box dính vào người khi lia máy, không bị trễ.

### 3.2 Các khối

Code chia làm 2 target:
- **`ESPCore`**: framework Swift thuần, không import ARKit/Vision/UIKit, unit test được.
- **`ESP`**: app chứa ARKit, Vision, SwiftUI.

| Khối | Target | Trách nhiệm | Phụ thuộc |
|---|---|---|---|
| `CaptureEngine` | ESP | Cấu hình và chạy `ARSession`, phát `ARFrame`, báo lỗi quyền/LiDAR | ARKit |
| `PerceptionPipeline` | ESP | Chạy Vision trên `capturedImage`, trả `[Detection]` | Vision |
| `SpatialResolver` | ESP (toán ở ESPCore) | Lấy độ sâu → khoảng cách, unproject → world, kiểm tra che khuất | ARKit, `SpatialMath` |
| `SpatialMath` | ESPCore | Unproject/project pixel ↔ camera ↔ world, median depth, dựng góc box 3D | simd |
| `Tracker` | ESPCore | Ghép detection vào track, vòng đời track, làm mượt | `OneEuroFilter` |
| `OneEuroFilter` | ESPCore | Lọc nhiễu cho box và khớp | — |
| `GameEngine` | ESPCore | Máu, damage, hồi máu, hạ gục/hồi sinh, kill feed, aimbot chọn mục tiêu | `NameGenerator` |
| `NameGenerator` | ESPCore | Sinh tên/level/rank cố định theo track ID | — |
| `Settings` + `Preset` | ESPCore | Struct cài đặt (Codable) và 4 preset | — |
| `SettingsStore` | ESP | Lưu/đọc cài đặt qua UserDefaults (JSON) | `Settings` |
| `Recorder` | ESP | Quay bằng ReplayKit, lưu vào Ảnh | ReplayKit, Photos |
| `GestureLayer` | ESP | Cử chỉ 3 ngón (UIKit recognizer bọc trong SwiftUI) | UIKit |
| `HUD/*` | ESP | Toàn bộ giao diện | SwiftUI |

### 3.3 Chi tiết kỹ thuật

**Capture**
- `ARWorldTrackingConfiguration`, `frameSemantics = [.smoothedSceneDepth]` (nếu `supportsFrameSemantics` trả về true), chọn video format 60fps có độ phân giải cao nhất, không bật plane detection.
- Hiển thị camera bằng RealityKit `ARView` (`automaticallyConfigureSession = false`, không có entity nào). Không dùng SceneKit vì đã bị Apple khai tử mềm.
- Ánh xạ toạ độ ảnh ↔ màn hình qua `ARFrame.displayTransform(for:viewportSize:)` theo hướng xoay hiện tại.

**Perception**
- `VNDetectHumanRectanglesRequest` (`upperBodyOnly = false`) và `VNDetectHumanBodyPoseRequest` chạy cùng một `VNImageRequestHandler` mỗi lượt.
- Ghép pose vào box: lấy bbox của các khớp có confidence > 0.3, chọn box có IoU lớn nhất.
- `VNGeneratePersonInstanceMaskRequest` chạy 10Hz, chỉ khi bật Chams (tối đa 4 người).
- Orientation truyền cho Vision lấy theo hướng giao diện: `.up` khi landscapeRight, `.down` khi landscapeLeft.
- Không xử lý chồng lượt: frame mới đến khi lượt trước chưa xong thì bỏ frame đó.

**Spatial**
- Độ sâu (map 256×192): lấy **median** các mẫu có confidence ≥ medium trong vùng thân (vai, cổ, hông). Không có khớp thì lấy 20% giữa box.
- Unproject: scale intrinsics về độ phân giải depth map, rồi `world = camera.transform × [x·d, y·d, −d, 1]` (theo hệ toạ độ ARKit).
- Box 3D: tâm tại vị trí world, cao từ đầu tới chân (lấy từ khớp, fallback 1.70m), rộng 0.55m, sâu 0.35m. Xoay theo hướng đường vai nếu đủ khớp, không thì quay mặt về camera.
- Che khuất: trong box, nếu > 35% mẫu có độ sâu nhỏ hơn độ sâu người quá 0.5m thì coi là bị che một phần (box vàng).
- Không có độ sâu (fallback): khoảng cách ≈ `fy × 1.70 / chiều_cao_box_px`.

**Tracker**
- Ghép tham lam theo IoU ≥ 0.3. Nếu không có cặp nào thì ghép theo khoảng cách world < 0.6m.
- Vòng đời: *tentative* (cần 3 lần khớp liên tiếp) → *confirmed* → *lost* (không thấy trên màn hình > 0.7s). Track lost được nhớ vị trí world 10s để vẽ mũi tên ngoài màn hình, quay lại trong thời gian đó thì giữ nguyên ID.
- One Euro filter cho 4 góc box, từng khớp và vị trí world. Vận tốc lấy từ vị trí world đã làm mượt.

**Game**
- Máu tối đa 100.
- Chạm vào thân: damage ngẫu nhiên 18–34. Chạm vùng đầu (bán kính quanh khớp đầu, hoặc 18% trên cùng của box): `HEADSHOT`, mất 100.
- Hồi +5/s nếu 3s không bị bắn và tốc độ < 0.3 m/s. Tụt −4/s nếu tốc độ > 1.5 m/s, nhưng tụt tự nhiên không bao giờ dưới 10 (không tự chết).
- Máu về 0: trạng thái *eliminated*, hiệu ứng nổ hạt, banner "ELIMINATED", thêm dòng kill feed (giữ tối đa 4 dòng, mỗi dòng mờ dần sau 6s). Sau 5s hồi sinh đầy máu.
- Aimbot: trong các track confirmed có điểm đầu nằm trong vòng FOV (bán kính 50–400pt quanh tâm màn hình), chọn người gần tâm nhất. Tâm ngắm trượt tới đầu họ bằng spring, độ mượt theo slider Smooth. Khóa được mục tiêu thì rung `.rigid`.
- Tên: chọn từ danh sách tiền tố/hậu tố bằng seed theo track ID (cùng ID luôn ra cùng tên), level 1–99, rank là một SF Symbol (`shield.fill`, `star.fill`, `crown.fill`...).

**Nhiệt và hiệu năng** (theo `ProcessInfo.thermalState`)
| nominal | fair | serious | critical |
|---|---|---|---|
| 30Hz | 20Hz | 10Hz, tắt Chams | 5Hz, tắt Chams, hiện cảnh báo kính |

Mỗi lúc vẽ tối đa 8 người, ưu tiên người gần nhất.

## 4. Giao diện

### 4.1 Nguyên tắc
- Camera tràn viền, chỉ màn hình ngang. **Không có nút cố định nào:** mọi thành phần đều bật tắt được, tắt hết thì là camera trần.
- Các thành phần nổi (thanh máu, name tag, nhãn khoảng cách, HUD, radar, Dynamic Island giả, menu, kill feed) đều dùng **Liquid Glass**: `.glassEffect(.regular.tint(...))` đặt trong `GlassEffectContainer`.
- Nét box, skeleton, snapline và vòng FOV vẽ bằng `Canvas`: nét 1.5pt, đầu tròn.
- Màu theo hệ thống Apple: `systemGreen` khi nhìn rõ, `systemYellow` khi bị che, `systemRed` khi bị khóa. Màu chủ đạo đổi được trong menu.
- Font SF Pro, số dùng SF Mono hoặc `.monospacedDigit()`. Bật tắt gì cũng có haptic nhẹ.

### 4.2 Bố cục ngang
```
┌────────────────────────────────────────────────────────────┐
│ ESP ◉ 60fps · 3 players    ╭─ 🎯 Locked · 12.4 m ─╮  kill feed│
│ ╭───╮                                                        │
│ │·▲ │ radar       ╭Player_0423·Lv67╮                         │
│ ╰───╯          ▕  ┏━━          ━━┓     ╭P_1187╮              │
│                ▕  ┃  (skeleton)  ┃      ┏━  ━┓              │
│        máu  →  ▕  ┃      ⊕       ┃      ┗━  ━┛              │
│                ▕  ┗━━          ━━┛     ╭ 21m ╮       ( ● )   │ ← nút quay (tuỳ chọn)
│ ◀ 8m               ╭ 12.4 m ╮                                │
│                         ╲  snapline                          │
└────────────────────────────────────────────────────────────┘
```
- **Góc trên trái:** HUD (FPS, số người) và radar tròn bằng kính (~110pt, hình nón tầm nhìn, chấm người theo vị trí world so với hướng điện thoại, tầm 5–30m).
- **Dynamic Island giả:** viên kính sát cạnh có Dynamic Island thật (đổi bên theo hướng xoay), nở ra khi khóa mục tiêu.
- **Kill feed:** góc trên phía đối diện radar.
- **Nút quay** (nếu bật): đặt ở cạnh phía ngón cái, đổi bên theo hướng xoay.

### 4.3 ESP từng người
| Thành phần | Kiểu |
|---|---|
| Box | Corner / Full / 3D (box 3D chiếu từ 8 góc world) |
| Name tag | Viên kính trên đầu: `Player_0423 · Lv 67` + icon rank |
| Thanh máu | Viên kính dọc cạnh box, nhuộm xanh → vàng → đỏ, có số, tụt máu có hoạt ảnh spring |
| Khoảng cách | Viên kính dưới chân: `12.4 m` |
| Skeleton | Nét trắng 1.5pt, khớp là chấm tròn |
| Chams | Phủ mask màu (alpha ~0.35) có gradient chạy nhẹ |
| Snapline | Từ giữa cạnh dưới màn hình tới chân người |
| Head dot | Chấm tròn ở khớp đầu |
| Mũi tên ngoài màn hình | Viên kính ở mép màn hình chỉ hướng người đã khuất (≤ 10s), kèm khoảng cách |
| Damage | Số bay lên mờ dần, hitmarker ✕, `HEADSHOT` màu đỏ |

### 4.4 Cử chỉ
| Cử chỉ | Tác dụng |
|---|---|
| Chạm 2 lần bằng 3 ngón | Mở / đóng menu |
| Giữ 3 ngón 0.8s | Bắt đầu / dừng quay (kèm haptic) |
| Chạm 1 ngón vào người | "Bắn" (khi bật Game) |
| Chạm ra ngoài menu | Đóng menu |

Lần mở app đầu tiên: gợi ý kính *"Chạm 2 lần bằng 3 ngón để mở menu"*, mờ sau 3s, không hiện lại. Nếu bật Trợ năng → Thu phóng thì iOS chiếm cử chỉ 3 ngón (ghi chú trong mục "Về app").

### 4.5 Menu
Tấm kính trượt ra từ cạnh phải, rộng ~40%, cuộn dọc, bố cục như app Cài đặt. ESP vẫn chạy phía sau, đổi gì thấy ngay.
- **Preset:** LEGIT · RAGE · STREAMER · OFF. Sửa bất kỳ mục nào thì preset chuyển thành "Custom".
- **ESP:** Box + kiểu, Skeleton, Chams, Snaplines, Name, Health, Distance, Head dot, Off-screen arrows
- **Aim:** Aimbot, vòng FOV + bán kính, Smooth, Target (Head/Chest), Crosshair
- **Game:** Bắn thử, Kill feed, Máu tự nhiên
- **HUD:** FPS/Players, Radar + tầm, Dynamic Island giả, Watermark + chữ (mặc định `ESP v2.6 · Undetected`)
- **Quay video:** Nút quay trên màn hình, Thu mic, Haptics
- **Về app:** `v2.6 · Undetected ✓`, ghi chú về cử chỉ

| Preset | Bật |
|---|---|
| LEGIT | Box góc, Distance |
| RAGE | Tất cả, kể cả Aimbot, Chams, Radar, Game |
| STREAMER | Box, Name, Health, Distance, Skeleton, Watermark. Không có HUD, không có nút |
| OFF | Không gì cả (camera trần) |

Lần cài đầu dùng preset **OFF** (đúng chất troll). Cài đặt tự lưu.

### 4.6 Splash
~2s, chạm để bỏ qua. Nền đen, SF Symbol `scope` phát sáng, các dòng SF Mono hiện lần lượt: `Injecting… ✓`, `Bypassing anti-cheat… ✓`, `Loading offsets… ✓`, bên dưới là thanh tiến trình kính.

## 5. Quay video
- `RPScreenRecorder.shared()`: `startRecording` rồi `stopRecording(withOutput:)` ra file tạm, sau đó lưu vào Ảnh qua `PHPhotoLibrary` (chỉ xin quyền "thêm ảnh").
- Bắt đầu quay thì menu tự đóng. Khi đang quay có chấm đỏ nhỏ bằng kính (tắt được, và preset STREAMER mặc định tắt).
- Mic theo cài đặt. Lần đầu iOS hỏi quyền ghi màn hình.
- Lưu xong thì hiện toast kính "Đã lưu vào Ảnh".

## 6. Xử lý lỗi
| Tình huống | Xử lý |
|---|---|
| Từ chối quyền camera | Màn hình kính giải thích + nút mở Cài đặt |
| Không có LiDAR / sceneDepth | Dùng khoảng cách ước lượng, tắt kiểm tra che khuất, khoảng cách thêm dấu `~` |
| ARKit tracking kém (thiếu sáng, lia nhanh) | Box 3D và radar tạm ẩn, box 2D vẫn chạy. HUD hiện "Low tracking" |
| Session bị gián đoạn (cuộc gọi, ra nền) | Dừng pipeline, xoá track, chạy lại khi quay về |
| Không thấy ai | Nếu HUD đang bật: hiện "Scanning…" với hiệu ứng radar quét |
| Máy nóng | Theo bảng nhiệt ở mục 3.3 |
| Lưu video lỗi / từ chối quyền Ảnh | Toast lỗi, giữ file tạm và cho thử lưu lại |

## 7. Build & phân phối
- **XcodeGen** `project.yml` khai báo 3 target: `ESP` (app), `ESPCore` (framework), `ESPCoreTests` (Swift Testing). File `.xcodeproj` không commit.
- `Info.plist`: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `UIRequiredDeviceCapabilities` = [`arkit`], chỉ màn hình ngang, `UIStatusBarHidden`, `UIRequiresFullScreen`.
- Bundle ID `com.cam.espcamera` (esign sẽ ký lại), tên hiển thị **ESP**.
- **GitHub Actions** `.github/workflows/build.yml`, chạy khi push hoặc bấm tay:
  1. Runner macOS có Xcode 26, chọn Xcode 26 bằng `xcode-select`
  2. `brew install xcodegen` → `xcodegen generate`
  3. `xcodebuild test` cho `ESPCoreTests` trên iOS Simulator
  4. `xcodebuild build -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO`
  5. Đóng gói `Payload/ESP.app` → `ESP.ipa`, upload làm artifact
- Cài: tải `ESP.ipa` từ tab Actions → ký bằng esign → cài.

## 8. Cấu trúc thư mục
```
project.yml
.github/workflows/build.yml
App/
  ESPApp.swift, Info.plist, Assets.xcassets
  Capture/CaptureEngine.swift
  Perception/PerceptionPipeline.swift
  Spatial/SpatialResolver.swift
  Store/ESPStore.swift, SettingsStore.swift
  Recording/Recorder.swift
  Input/GestureLayer.swift
  HUD/RootView.swift, CameraView.swift, ESPCanvas.swift, PlayerGlassViews.swift,
      RadarView.swift, FakeIslandView.swift, KillFeedView.swift, MenuPanel.swift,
      SplashView.swift, HintView.swift, WatermarkView.swift, ToastView.swift
Core/   (ESPCore)
  Models.swift, Tracker.swift, OneEuroFilter.swift, SpatialMath.swift,
  GameEngine.swift, Aimbot.swift, NameGenerator.swift, Settings.swift, Preset.swift
Tests/  (ESPCoreTests)
  TrackerTests, OneEuroFilterTests, SpatialMathTests, GameEngineTests,
  AimbotTests, NameGeneratorTests, PresetTests
```

## 9. Mốc triển khai
Mỗi mốc kết thúc bằng một `.ipa` để cài thử trên máy.

| Mốc | Nội dung | Kiểm tra trên máy |
|---|---|---|
| **M1** | XcodeGen + CI ra `.ipa` + ARView camera ngang + xin quyền | Ký esign cài được, mở ra thấy camera ngang, xoay 2 hướng ok |
| **M2** | Perception + Spatial + Tracker + box / name / distance | Box bám người, khoảng cách lệch dưới ~10% so với đo tay |
| **M3** | Skeleton, Chams, snapline, head dot, box 3D, mũi tên ngoài màn hình | Box 3D đứng yên khi lia máy, mũi tên chỉ đúng hướng |
| **M4** | Menu kính, cử chỉ 3 ngón, SettingsStore, preset, hint lần đầu | OFF ra camera trần, các preset đổi đúng, cài đặt còn sau khi tắt app |
| **M5** | HUD, radar, Dynamic Island giả, watermark, aimbot, crosshair/FOV | Radar xoay theo máy, khóa mục tiêu có rung |
| **M6** | GameEngine: máu, bắn, headshot, hạ gục, kill feed, hồi sinh | Chạm bắn, chết rồi hồi sinh đúng 5s |
| **M7** | Recorder, splash, toast, xử lý nhiệt, chỉnh mượt | Quay 2 phút được, video có overlay kính, máy không giật khi nóng |

## 10. Kiểm thử
- **Unit test (Swift Testing, chạy trên CI):**
  - Tracker: giữ ID, tentative → confirmed, lost rồi nhận lại
  - OneEuroFilter
  - SpatialMath: project/unproject khứ hồi, median bỏ mẫu kém tin cậy, đủ 8 góc box
  - GameEngine: damage, headshot, hồi/tụt máu, sàn 10 máu, hồi sinh
  - Aimbot: chọn đúng mục tiêu trong FOV
  - NameGenerator: cùng seed ra cùng tên
  - Preset: đổi preset và chuyển sang "Custom"
- **Test tay:** checklist theo mốc ở mục 9.

## 11. Để sau (không thuộc bản đầu)
Xuất video dọc 9:16, camera trước, âm thanh, nhiều theme màu.

## 12. Rủi ro
| Rủi ro | Giảm thiểu |
|---|---|
| Không có runner macOS với Xcode 26 | Kiểm tra ngay ở M1, thử lần lượt `macos-26` rồi `macos-15` + Xcode 26 |
| Vision bắt người kém khi tối hoặc ở xa | Chấp nhận cho bản đầu. Nếu cần thì thêm YOLO CoreML sau |
| ReplayKit làm tụt FPS khi quay | Khi đang quay, tự hạ perception xuống 20Hz |
| esign gỡ hoặc đổi entitlement | App không dùng entitlement đặc biệt nào |
| Cử chỉ 3 ngón đụng Thu phóng trợ năng | Ghi chú trong app |
