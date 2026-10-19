# ESP Camera v3 "Street" — Thiết kế

- **Ngày:** 2026-10-19
- **Thay thế:** phần giao diện, menu và nhiệt của `2026-10-19-esp-v2-design.md`. Nhận diện (YOLO), tracking (ByteTrack + Kalman) và đoán hành động giữ như v2.
- **Trạng thái:** người dùng yêu cầu qua chat, làm luôn không chờ duyệt.

## 1. Mục tiêu

Một cam ESP gọn để mang ra đường: ít tính năng, menu ngắn, bắt người và con vật nhanh hơn, thêm cam góc siêu rộng.

## 2. Giữ lại

| Nhóm | Tính năng |
|---|---|
| ESP | Box (góc / viền / kính), thẻ chi tiết, mũi tên ngoài màn hình, tia (lite), hiện con vật |
| HUD | Bộ đếm + fps, danh sách trong khung, nhật ký sự kiện, watermark |
| Quay | Nút quay, thu mic, rung; giữ 3 ngón để quay |

- **Thẻ chi tiết:** tên (`Người 01`, `🐕 Chó 01`), khoảng cách, tốc độ (km/h, dưới 0.3 m/s hiện 0), thời gian trong khung. Có cho cả con vật.
- **Tia lite:** nét 1 pt mờ dần từ mép dưới màn hình, kết thúc bằng chấm nhỏ dưới box.
- Khoảng cách ước lượng (không có depth) có dấu `~`.

## 3. Bỏ

Preset, nhãn và tag khoảng cách riêng, hành động trên nhãn, skeleton, vòng đầu, vệt chân, chams (và mask phân đoạn), box 3D, hiện đồ vật, radar, Dynamic Island giả, chấm đỏ khi quay, bộ lọc tầm xa / số người, chế độ mượt (60 Hz giờ là mặc định).

Đoán hành động vẫn chạy ngầm cho danh sách và nhật ký. File cài đặt cũ đọc được: cờ còn tồn tại giữ nguyên, cờ đã bỏ bị bỏ qua, `threeD` thành `corner`.

## 4. Menu

Một panel Liquid Glass: chọn camera (segmented `1× Thường | 0.5× Siêu rộng`), rồi các lưới ô bấm 3 cột kiểu Control Center (ESP, HUD, Quay video). Ô "Kiểu" bấm để đổi kiểu box. Hàng màu chủ đạo, ghi chú cử chỉ ở cuối.

## 5. Tốc độ phản xạ

| Nhiệt | Pose | Vật thể/con vật | HUD |
|---|---|---|---|
| nominal | 60 | 30 | 60 |
| fair | 30 | 15 | 60 |
| serious | 20 | 8 | 30 |
| critical | 12 | 4 | 30 + cảnh báo |

Đang quay: pose ≤ 30, vật thể ≤ 15.

Tracker:
- Ngưỡng tạo track 0.5 → **0.4** để bắt người nhỏ, ở xa.
- Track mới được lỡ tối đa **0.1 s** (vài khung 60 Hz) mà không phải bắt đầu lại.
- Box biến mất sau **0.5 s** không thấy (trước là 0.7 s).
- Vẫn cần 3 lần khớp, ở 60 Hz là khoảng 33 ms.

Ngoài ra bỏ chams, skeleton và vệt chân cũng bớt tải. Khi con vật tắt thì không tạo track con vật.

### Người đi xe, người di chuyển nhanh

Không cần box xe, nhưng phải bắt được người ngồi trên xe đang phóng qua (người lái xe vẫn là lớp "người" của YOLO).

- **Ghép track mới theo tâm:** người ở xa phóng nhanh có thể dịch quá một bề rộng box giữa hai khung, nhất là khi máy nóng chạy 20 Hz. Lúc đó hai box liên tiếp không chồng nhau, và ở khung thứ 2 Kalman chưa biết vận tốc.
  - Track **mới** (tentative) được ghép thêm theo khoảng cách tâm dưới 1.2 lần chiều cao box, với điều kiện chiều cao hai box chênh nhau không quá 1.5 lần.
  - Track đã xác nhận thì không dùng cách này, để không trao nhầm ID cho người đứng cạnh.
  - Có test kèm test đối chứng: tắt cách ghép này đi thì người lái không bao giờ được xác nhận.
- **Nhãn "🛵 Đi xe":** người đi xe ngồi, nên trước đây nhãn sẽ ra "Ngồi".
  - Gán "Đi xe" khi tốc độ ngang ≥ 6.5 m/s (khoảng 23 km/h), hoặc khi đang ngồi và tốc độ ≥ 3.5 m/s.
  - Nhãn này đứng ngay sau nhãn đồ vật, xếp trên cử chỉ và tư thế.
  - Nhóm chuyển động chỉ giữ 0.2 s (trước 0.4 s), vì người phóng qua chỉ ở trong khung chưa tới 1 s.
- **Sự kiện:** "🛵 Người 05 phóng qua · 32 km/h".
  - Báo một lần cho mỗi track, không bị giới hạn 2 s giữa các sự kiện.
  - Nếu dòng "vừa vào khung hình" còn mới thì sửa luôn dòng đó.
  - Trong lúc đi xe, các sự kiện ngồi xuống, đứng dậy, bắt đầu chạy bị tắt (chân người lái làm tư thế nhảy liên tục).
- **Ít nhoè hơn:** auto-exposure bị giới hạn tối đa 1/120 s trên cả hai camera.
  - Cam 1× chỉnh qua `configurableCaptureDeviceForPrimaryCamera`, đặt ở khung đầu tiên sau khi chạy.
  - Đổi lại, ảnh ban đêm tối và nhiễu hơn.
- **Depth từng khung:** dùng `sceneDepth` thay cho `smoothedSceneDepth`, vì bản làm mượt theo thời gian bị trễ ở người di chuyển nhanh.
- **Kalman world:** giữ nguyên. Mô phỏng người lái 8.3 m/s cho vận tốc đạt khoảng 7 m/s sau 6 khung (0.1 s) ở 60 Hz.

## 6. Cam góc siêu rộng (0.5×)

ARKit world tracking chỉ dùng cam 1× (Apple xác nhận trên forum), nên 0.5× chạy riêng:

- **Hình:** `AVCaptureSession` với `builtInUltraWideCamera`.
  - Chọn format 4:3, 60 fps, rộng tối đa 1920, pixel 420f (giống ARKit).
  - Bật sửa méo hình học, tắt chống rung.
  - Ảnh để nguyên hướng gốc của cảm biến (`videoRotationAngle` 0).
- **Intrinsics:** lấy từ ma trận đi kèm mỗi khung nếu có, không thì tính từ FOV ngang của format.
- **Tư thế:** CoreMotion `xArbitraryZVertical` ở 100 Hz, chỉ có xoay. Ma trận attitude được đổi sang camera → world theo quy ước ARKit (+Y lên).
  - Mỗi ảnh lấy attitude gần thời điểm chụp nhất.
  - Chiều đọc ma trận (device → reference hay ngược lại) được chốt bằng trọng lực ở mẫu đầu tiên đủ rõ.
  - Nhờ vậy re-projection khi lia máy, mũi tên ngoài màn hình và khoảng cách trên sàn vẫn chạy. Đi bộ cầm máy thì không bù được, tốc độ là tương đối.
- **Khoảng cách:** không có LiDAR nên ước lượng theo kích thước.
  - Người bị cắt ở mép khung hoặc đang ngồi (box thấp): đo theo thân, vai → hông khoảng 0.5 m.
  - Còn lại: chiều cao box so với chiều cao điển hình của từng loại (người 1.7 m, chó 0.55 m, mèo 0.3 m…).
  - Công thức này cũng dùng cho cam 1× khi người ở ngoài tầm LiDAR.
- **Preview:** `AVCaptureVideoPreviewLayer`, aspect fill, xoay 180° khi cầm ngang trái. Mapping giống ARView nên `ScreenMapper` dùng chung.
- **Chuyển cam:** dừng hẳn bên này rồi mới mở bên kia, vì ARKit chỉ lấy được camera khi AVFoundation đã nhả. Reset tracker và HUD.
  - Máy không có cam siêu rộng thì quay về 1×, kèm ghi chú trong menu.

## 7. Rủi ro

- **Quy ước attitude của CoreMotion:** đã có test cho cả hai cách đọc, chốt bằng trọng lực lúc chạy. Cần kiểm tra trên máy: lia sang phải thì box phải đứng yên trên người.
- **Khoảng cách ước lượng sai với người thấp, trẻ em, hoặc người cúi:** chấp nhận được, đã có dấu `~`.
- **60 Hz làm máy nóng nhanh hơn:** chính sách nhiệt tự hạ tần số.

## 8. Chỉnh sau khi thử trên máy (2026-10-20)

- **Nhãn:** chỉ ghi "Người" hoặc tên con vật, không đánh số nữa.
- **Bỏ nhận dạng trạng thái:** bỏ luật hành động/tư thế/đồ vật (`Activity`, `ActivityTracker`).
  - Model vật thể chỉ chạy khi bật con vật.
  - Nhật ký giờ lấy từ `PresenceLog`: vào/rời khung, con vật xuất hiện, phóng qua (tốc độ sàn ≥ 6.5 m/s trong 3 lần cập nhật liền).
- **Box bị "lố":** box người được cắt theo các khớp nhìn thấy (`PersonBox.visible`), không bao giờ to hơn box YOLO. Ngưỡng khớp hạ xuống 0.35.
- **Bỏ phóng to/thu nhỏ box theo độ sâu khi khoảng cách chỉ là ước lượng.** Kalman world tin khoảng cách ước lượng ít hơn (nhiễu 0.06 so với 0.005). Tốc độ hiển thị chỉ tính theo mặt sàn.
- **Chiều sâu:** `DepthStyle` theo log khoảng cách từ 1.5 tới 18 m.
  - Nét box 2.6 → 1 pt, độ đậm 1 → 0.45, người gần có thêm viền sáng.
  - Thẻ và mũi tên thu nhỏ còn 0.72 lần khi ở xa.
  - Người xa được vẽ trước, người gần đè lên trên.
- **Tia lite:** kẻ từ giữa mép trên xuống đỉnh box.
- **Người bị che một nửa:**
  - Phát hiện có độ tự tin 0.25–0.4 cũng tạo được track, nhưng phải khớp 8 lần mới hiện. Chỉ cần một lần khớp tự tin (≥ 0.4) là quay về mức 3 lần.
  - YOLO11n thường (bắt người bị che tốt hơn model pose) chạy ở nửa tần số khi tắt con vật. Người nó thấy mà model pose bỏ sót (`PersonFusion.uncovered`, che phủ > 50%) được thêm vào.
- **4 góc mảnh hơn:** nét box 0.8–1.6 pt, viền tối và viền sáng mỏng lại.
