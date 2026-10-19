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
