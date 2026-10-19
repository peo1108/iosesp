# ESP Camera v2 — Thiết kế

- **Ngày:** 2026-10-19
- **Thay thế:** các phần aim, game và máu của `2026-10-19-esp-camera-design.md`. Mọi thứ không nhắc tới ở đây giữ nguyên như spec v1: camera ARKit + LiDAR, Liquid Glass, màn hình ngang, menu ẩn, quay video, splash, kiểm soát nhiệt.
- **Trạng thái:** đã chốt qua chat. Người dùng yêu cầu làm luôn, không chờ duyệt.

## 1. Mục tiêu

ESP **thuần thông tin**: nhận biết người và con vật trong khung hình.
- Có bao nhiêu người, bao nhiêu con vật.
- Mỗi người **đang làm gì**.
- Nhận diện **nhiều người, mượt**: ID ổn định, box trượt mượt ở 60–120 Hz.

Không phải mục tiêu: nhận diện danh tính, aimbot, game, máu.

## 2. Thay đổi so với v1

**Bỏ:**
- Aimbot, vòng FOV, tâm ngắm
- GameEngine, HitTest, bắn thử, hiệu ứng damage, ELIMINATED, kill feed
- Thanh máu, máu tự nhiên
- NameGenerator (tên gamer)
- Các trường cài đặt tương ứng

**Đổi:**
- Preset RAGE → **VIP**. File cài đặt cũ ghi `rage` đọc ra thành `vip`.
- Nhãn người: `Người 01`, `Người 02`… Con vật: `Chó 01`, `Mèo 01`… Số đánh riêng theo loại, theo thứ tự xuất hiện.
- Dynamic Island giả: hiện người gần nhất, ví dụ `Người 02 · 1.8 m · 📱`.
- Chạm 1 ngón: chỉ dùng để đóng menu.

## 3. Nhận diện

| Model | Đầu ra | Tần số (máy mát) |
|---|---|---|
| **YOLO11n-pose** (CoreML, input 640×480 đúng tỉ lệ 4:3 của camera) | Box người + 17 khớp COCO | 30 Hz, hoặc 60 Hz khi bật "Chế độ mượt" |
| **YOLO11n** (CoreML, NMS sẵn trong model, input 640×480) | 80 loại COCO: con vật + đồ vật | 15 Hz |

- Model được export và compile (`coremlcompiler`) **trong CI** rồi đóng vào app thành `Models/*.mlmodelc`. Không commit file model vào repo.
  - Giấy phép: Ultralytics dùng AGPL-3.0, chỉ dùng cá nhân.
- Đầu ra pose được giải mã trong ESPCore và có unit test:
  - Ngưỡng box 0.35, NMS IoU 0.5, ngưỡng khớp 0.5.
  - Toạ độ chuẩn hoá theo ảnh.
  - Neck và root suy từ trung điểm vai và hông.
- Cầm ngang chiều trái thì ảnh được xoay 180° trước khi đưa vào model, rồi đổi toạ độ ngược lại về ảnh gốc.
- Không load được model thì quay về bộ nhận diện Vision cũ, kèm cảnh báo trong menu.
- Con vật: chó, mèo, chim, ngựa, cừu, bò, voi, gấu, ngựa vằn, hươu cao cổ.
- Đồ vật dùng để đoán hành động: điện thoại, cốc, chai, ly, laptop, sách, ô, bóng, ghế, sofa, ghế băng, giường, balo, túi xách, xe đạp, xe máy.

## 4. Tracking

- **Ảnh (ByteTrack):**
  - Mỗi track có Kalman tốc độ không đổi trên (cx, cy, w, h), dự đoán mỗi lần chạy.
  - Ghép hai lượt: detection tin cậy cao (≥ 0.5) với mọi track, theo IoU ≥ 0.2. Sau đó detection tin cậy thấp (0.15–0.5) với các track còn lại, theo IoU ≥ 0.5.
  - Còn sót thì ghép theo khoảng cách world < 0.6 m, giống v1.
  - Chỉ ghép cùng loại: người với người, chó với chó.
  - Vòng đời như v1: cần 3 lần khớp, mất sau 0.7 s, quên sau 10 s.
- **World:**
  - Kalman tốc độ không đổi trên vị trí chân (x, y, z), cho ra vận tốc và tốc độ thật.
  - Lúc vẽ, vị trí được dự đoán tới thời điểm hiện tại, tối đa 0.3 s, rồi chiếu qua camera hiện tại. Kết quả là box trượt theo người ở tốc độ màn hình.

## 5. Đoán hành động

- Luật thuần trong ESPCore, có unit test bằng khung xương giả.
- Chạy trên toạ độ "đứng thẳng": nếu ảnh đã bị xoay 180° thì lật lại trước khi áp luật.
- Đơn vị đo là độ dài thân L, tính từ trung điểm vai tới trung điểm hông.

| Nhóm | Nhãn | Luật |
|---|---|---|
| Chuyển động | Đứng yên / Đi bộ / Chạy | tốc độ ngang < 0.25 / 0.25–1.8 / > 1.8 m/s |
| Tư thế | Nằm | thân nghiêng > 60° so với phương thẳng đứng |
| | Cúi người | thân nghiêng 30–60°, đùi gần thẳng đứng (< 30°) |
| | Ngồi | thân thẳng, và có đùi nằm ngang (> 50°) hoặc đùi bị ngắn lại < 0.5L khi gối thấp hơn hông |
| | Ngồi xổm | như Ngồi, nhưng hông cách cổ chân theo chiều dọc < 0.8L và không có ghế |
| | Đứng | mặc định khi thân thẳng |
| Tay | Giơ tay / Giơ 2 tay | cổ tay cao hơn mũi (không có mũi thì cao hơn vai 0.3L) |
| | Vẫy tay | cổ tay cao hơn vai, đổi chiều ngang ≥ 2 lần với biên độ ≥ 0.25L trong 1.2 s |
| | Khoanh tay | hai cổ tay nằm giữa hai vai theo chiều ngang, giữa vai và hông theo chiều dọc, và bắt chéo nhau |
| | Chống nạnh | mỗi cổ tay cách hông cùng bên < 0.3L, khuỷu tay chìa ra ngoài vai > 0.15L |
| Hướng | Đang nhìn bạn | thấy mũi và hai mắt, mũi nằm giữa hai mắt, vai trái nằm bên phải ảnh |
| | Quay lưng | không thấy mũi và mắt nhưng thấy hai vai, hoặc vai trái nằm bên trái ảnh |
| | Nghiêng | các trường hợp còn lại |
| Đồ vật | 📞 Gọi điện | điện thoại cách tai < 0.5L |
| | 📱 Dùng điện thoại | điện thoại cách cổ tay < 0.6L |
| | ☕ Uống | cốc, chai hoặc ly cách mũi < 0.6L |
| | 💻 Dùng laptop | laptop chồng lên nửa dưới box, kèm đang ngồi hoặc cổ tay chạm laptop |
| | 📖 Đọc sách | sách cách cổ tay < 0.6L |
| | ☂️ Cầm ô | ô nằm trên đầu |
| | ⚽ Chơi bóng | bóng cách cổ tay hoặc cổ chân < 0.8L |
| | 🪑 Ngồi ghế / 🛋 Ngồi sofa | đang ngồi và ghế hoặc sofa chứa trung điểm hông |
| | 🛏 Nằm giường | đang nằm và giường chồng lên thân |
| | 🚲 Đi xe đạp / 🏍 Đi xe máy | xe chứa hông hoặc gối |
| Mang theo | 🎒 Balo / 👜 Túi | balo hoặc túi chồng lên phần thân |

- **Nhãn chính** ưu tiên theo thứ tự: đồ vật > tay > tư thế (trừ Đứng) > chuyển động.
- **Chống nhấp nháy:** mỗi nhóm tách riêng, giá trị mới phải đứng đầu liên tục 0.4 s mới được đổi.
- **Sự kiện:**
  - Các loại: vào khung hình, rời khung hình (mất > 1 s), ngồi xuống, đứng dậy, nằm xuống, bắt đầu chạy, bắt đầu nhìn bạn, cầm điện thoại lên, con vật xuất hiện.
  - Mỗi track tối đa 1 sự kiện mỗi 2 s.
  - Hiện 5 dòng gần nhất, mỗi dòng sống 8 s.

## 6. Giao diện

Giữ nguyên tắc v1: Liquid Glass, không có nút cố định, tắt hết thì là camera trần.

- **Từng người:**
  - Box: góc, đầy đủ, 3D, hoặc **kính** (phủ lớp kính mờ). Màu xanh khi nhìn rõ, vàng nét đứt khi bị che.
  - Nhãn `Người 01 · 🚶 Đi bộ`.
  - **Thẻ chi tiết:** khoảng cách, tốc độ, tư thế, hướng, đồ vật, mang theo, thời gian trong khung hình `⏱ 00:42`.
  - Skeleton 17 khớp. **Vòng đầu**, bán kính tỉ lệ nghịch với khoảng cách.
  - **Vệt chân:** 5 s gần nhất, mỗi điểm cách nhau ≥ 0.12 m, mờ dần.
  - Chams và snapline: giữ như v1.
- **Con vật:** box màu cam, nhãn `🐕 Chó 01 · 2.0 m`.
- **Đồ vật** (khi bật): box trắng mảnh, nhãn nhỏ.
- **HUD:**
  - **Bộ đếm** `◉ 3 người · 🐕 1 · 🐈 1`, kèm fps.
  - **Danh sách "TRONG KHUNG"** ở góc phải trên, tối đa 8 dòng, xếp gần → xa.
  - **Nhật ký sự kiện** ở góc trái dưới, phía trên watermark.
  - Radar: người chấm xanh, con vật chấm cam.
  - Mũi tên ngoài màn hình, island, watermark.
- **Lọc:**
  - Tầm xa tối đa 5–30 m, mặc định 30.
  - Số người tối đa 5–20, mặc định 20. Tracker giữ tối đa 30 track.
- **Preset:**

| Preset | Bật |
|---|---|
| LEGIT | box góc, nhãn, khoảng cách |
| VIP | tất cả, box kính |
| STREAMER | box, nhãn, hành động, skeleton, watermark, bộ đếm |
| OFF | không gì |

## 7. Nhiệt

| Trạng thái | Pose | Vật thể | Chams | Cảnh báo |
|---|---|---|---|---|
| nominal | 30 (60 khi bật Chế độ mượt) | 15 | có | không |
| fair | 24 | 10 | có | không |
| serious | 15 | 5 | không | không |
| critical | 10 | 3 | không | có |

- Đang quay video thì pose giới hạn ở 24 Hz.
- Khi máy ở serious hoặc critical, HUD chỉ vẽ lại 30 lần/giây.

## 8. Mốc

| Mốc | Nội dung |
|---|---|
| M8 | Bỏ aim, game, máu; settings v2; VIP; nhãn "Người 01" |
| M9 | YOLO trong CI; bộ giải mã và NMS (Core); pipeline CoreML; con vật và đồ vật |
| M10 | Kalman, ByteTrack, Kalman world; vẽ theo vị trí dự đoán |
| M11 | Đoán hành động, chống nhấp nháy, sự kiện; nhãn và thẻ chi tiết |
| M12 | HUD v2: bộ đếm, danh sách, nhật ký, island, vệt chân, box kính, lọc, hiện đồ vật |
| M13 | Nhiệt v2, sửa các lỗi nhỏ còn lại từ review v1, chỉnh mượt |

## 9. Rủi ro

- **Export model trong CI lỗi:** ghim phiên bản `ultralytics`; nếu vẫn hỏng thì chuyển sang Git LFS.
- **Định dạng đầu ra của model khác dự kiến:** bộ giải mã đọc kích thước tensor lúc chạy, hỗ trợ cả `[1, 56, N]` lẫn `[1, N, 56]`, cả Float16 lẫn Float32.
- **Luật hành động có lúc sai:** chỉnh ngưỡng sau khi test trên máy.
