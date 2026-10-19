"""ESP Studio: drop videos in, pick the look, watch the ESP being drawn, open the result.

    pythonw studio.py
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

import cv2
from PySide6.QtCore import QObject, QSettings, QSize, Qt, QThread, QUrl, Signal
from PySide6.QtGui import QDesktopServices, QDragEnterEvent, QDropEvent, QFont, QImage, QPixmap
from PySide6.QtWidgets import (QApplication, QButtonGroup, QCheckBox, QComboBox, QFileDialog, QFrame, QHBoxLayout,
                               QLabel, QLineEdit, QListWidget, QListWidgetItem, QMainWindow, QProgressBar,
                               QPushButton, QSizePolicy, QVBoxLayout, QWidget)

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}
FOV_PRESETS = [("iPhone 1× (≈70°)", 70), ("iPhone 0.5× siêu rộng (≈105°)", 105), ("iPhone 2× (≈40°)", 40),
               ("iPhone 3×/5× (≈25°)", 25), ("Camera hành trình / GoPro (≈120°)", 120)]

STYLE = """
* { font-family: 'Segoe UI'; color: #f2f2f7; }
QMainWindow, QWidget#root { background: #0b0b0d; }
QFrame#card { background: #1c1c1e; border-radius: 16px; }
QLabel#title { font-size: 20px; font-weight: 600; }
QLabel#section { color: #8e8e93; font-size: 11px; font-weight: 600; letter-spacing: 1px; }
QLabel#muted { color: #8e8e93; }
QLabel#preview { background: #000; border-radius: 14px; color: #636366; font-size: 15px; }
QListWidget { background: transparent; border: none; font-size: 13px; }
QListWidget::item { padding: 8px 10px; border-radius: 10px; margin: 2px 0; }
QListWidget::item:selected { background: #2c2c2e; }
QPushButton { background: #2c2c2e; border: none; border-radius: 10px; padding: 9px 16px; font-size: 13px; }
QPushButton:hover { background: #3a3a3c; }
QPushButton:disabled { color: #636366; background: #1c1c1e; }
QPushButton#primary { background: #30d158; color: #000; font-weight: 600; }
QPushButton#primary:hover { background: #4cd964; }
QPushButton#primary:disabled { background: #1f5f31; color: #0b0b0d; }
QPushButton#danger { background: #3a1d1d; color: #ff6961; }
QPushButton#seg { border-radius: 9px; padding: 7px 10px; }
QPushButton#seg:checked { background: #30d158; color: #000; font-weight: 600; }
QCheckBox { spacing: 10px; font-size: 13px; padding: 4px 0; }
QCheckBox::indicator { width: 38px; height: 22px; border-radius: 11px; background: #3a3a3c; }
QCheckBox::indicator:checked { background: #30d158; }
QLineEdit, QComboBox { background: #2c2c2e; border: none; border-radius: 9px; padding: 7px 10px; font-size: 13px; }
QComboBox QAbstractItemView { background: #2c2c2e; selection-background-color: #3a3a3c; border-radius: 8px; }
QProgressBar { background: #2c2c2e; border: none; border-radius: 7px; height: 14px; text-align: center;
               font-size: 11px; color: #f2f2f7; }
QProgressBar::chunk { background: #30d158; border-radius: 7px; }
"""


def bgr_to_pixmap(frame, size: QSize) -> QPixmap:
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    h, w = rgb.shape[:2]
    image = QImage(rgb.data, w, h, 3 * w, QImage.Format_RGB888).copy()
    return QPixmap.fromImage(image).scaled(size, Qt.KeepAspectRatio, Qt.SmoothTransformation)


def first_frame(path: Path):
    cap = cv2.VideoCapture(str(path))
    ok, frame = cap.read()
    info = (int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)),
            cap.get(cv2.CAP_PROP_FPS) or 0, int(cap.get(cv2.CAP_PROP_FRAME_COUNT)))
    cap.release()
    return (frame if ok else None), info


# ------------------------------------------------------------------------------------------------------- worker

class Worker(QObject):
    """Runs esp_video.run on each queued video off the UI thread."""
    progress = Signal(int, str)          # percent, status line
    preview = Signal(object)             # BGR frame
    started_item = Signal(int)
    finished_item = Signal(int, str)     # index, output path
    failed_item = Signal(int, str)
    message = Signal(str)
    done = Signal()

    def __init__(self, jobs):
        super().__init__()
        self.jobs = jobs                 # [(index, Options)]
        self.cancel = False

    def run(self):
        import esp_video
        for index, options in self.jobs:
            if self.cancel:
                break
            self.started_item.emit(index)
            stage_start = {"t": time.monotonic()}

            def report(stage, done, total, rate, eta):
                share = (0, 85) if stage == "detect" else (85, 100)
                if getattr(options, "_cached", False) and stage == "draw":
                    share = (0, 100)
                pct = share[0] + (share[1] - share[0]) * done / max(total, 1)
                name = "Nhận diện" if stage == "detect" else "Vẽ ESP"
                step = "1/2" if stage == "detect" else "2/2"
                self.progress.emit(int(pct), f"Lượt {step} · {name} · {done}/{total} khung · {rate:.1f} khung/s · "
                                             f"còn {int(eta // 60)}:{int(eta % 60):02d}")

            def say(*parts, **_):
                text = " ".join(str(p) for p in parts).strip()
                if text.startswith("Dùng kết quả nhận diện"):
                    options._cached = True
                if text:
                    self.message.emit(text)

            try:
                out = esp_video.run(options, say=say, report=report, preview=self.preview.emit,
                                    stop=lambda: self.cancel)
                self.finished_item.emit(index, str(out))
            except esp_video.Cancelled:
                self.failed_item.emit(index, "Đã huỷ")
                break
            except Exception as e:   # surface anything (missing file, CUDA OOM…) instead of dying silently
                self.failed_item.emit(index, f"Lỗi: {e}")
        self.done.emit()


# --------------------------------------------------------------------------------------------------------- window

class Studio(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ESP Studio")
        self.resize(1280, 800)
        self.setAcceptDrops(True)
        self.settings = QSettings("esp", "studio")
        self.outputs: dict[int, str] = {}
        self.thread: QThread | None = None
        self.worker: Worker | None = None
        self.last_frame = None

        root = QWidget(objectName="root")
        self.setCentralWidget(root)
        layout = QHBoxLayout(root)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(14)
        layout.addWidget(self._queue_panel(), 0)
        layout.addWidget(self._center_panel(), 1)
        layout.addWidget(self._options_panel(), 0)
        self._load_settings()
        self._refresh_buttons()

    # ---- panels

    def _card(self, width=None):
        frame = QFrame(objectName="card")
        if width:
            frame.setFixedWidth(width)
        box = QVBoxLayout(frame)
        box.setContentsMargins(16, 16, 16, 16)
        box.setSpacing(10)
        return frame, box

    def _queue_panel(self):
        frame, box = self._card(260)
        title = QLabel("ESP Studio", objectName="title")
        box.addWidget(title)
        box.addWidget(QLabel("Kéo thả video vào cửa sổ", objectName="muted"))
        box.addWidget(QLabel("HÀNG ĐỢI", objectName="section"))
        self.queue = QListWidget()
        self.queue.currentRowChanged.connect(self._show_selected)
        box.addWidget(self.queue, 1)
        row = QHBoxLayout()
        add = QPushButton("＋ Thêm video")
        add.clicked.connect(self._pick_files)
        self.remove = QPushButton("Bỏ")
        self.remove.clicked.connect(self._remove_selected)
        row.addWidget(add, 1)
        row.addWidget(self.remove)
        box.addLayout(row)
        return frame

    def _center_panel(self):
        frame, box = self._card()
        self.preview = QLabel("Kéo video vào đây", objectName="preview", alignment=Qt.AlignCenter)
        self.preview.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.preview.setMinimumSize(420, 420)
        box.addWidget(self.preview, 1)
        self.info = QLabel("", objectName="muted")
        box.addWidget(self.info)
        self.bar = QProgressBar()
        self.bar.setRange(0, 100)
        self.bar.setValue(0)
        self.bar.setFormat("%p%")
        box.addWidget(self.bar)
        self.status = QLabel("Sẵn sàng", objectName="muted")
        box.addWidget(self.status)
        row = QHBoxLayout()
        self.start = QPushButton("Bắt đầu", objectName="primary")
        self.start.clicked.connect(self._start)
        self.cancel = QPushButton("Huỷ", objectName="danger")
        self.cancel.clicked.connect(self._cancel)
        self.open_video = QPushButton("Mở video ESP")
        self.open_video.clicked.connect(self._open_output)
        self.open_folder = QPushButton("Mở thư mục")
        self.open_folder.clicked.connect(self._open_folder)
        for b in (self.start, self.cancel, self.open_video, self.open_folder):
            row.addWidget(b)
        box.addLayout(row)
        return frame

    def _options_panel(self):
        frame, box = self._card(300)
        box.addWidget(QLabel("CHẾ ĐỘ", objectName="section"))
        seg = QHBoxLayout()
        self.mode_group = QButtonGroup(self)
        self.mode_max = QPushButton("Siêu chính xác", objectName="seg", checkable=True)
        self.mode_fast = QPushButton("Nhanh", objectName="seg", checkable=True)
        for i, b in enumerate((self.mode_max, self.mode_fast)):
            self.mode_group.addButton(b, i)
            seg.addWidget(b)
        box.addLayout(seg)
        self.mode_hint = QLabel("", objectName="muted", wordWrap=True)
        box.addWidget(self.mode_hint)
        self.mode_group.idToggled.connect(lambda *_: self._update_hint())

        box.addWidget(QLabel("HIỂN THỊ", objectName="section"))
        self.checks = {}
        for key, text in (("boxes", "Box 4 góc"), ("cards", "Thẻ chi tiết"), ("snaplines", "Tia (lite)"),
                          ("counter", "Bộ đếm"), ("list", "Danh sách trong khung"), ("log", "Nhật ký sự kiện"),
                          ("animals", "Nhận diện con vật")):
            c = QCheckBox(text)
            self.checks[key] = c
            box.addWidget(c)
        box.addWidget(QLabel("WATERMARK", objectName="section"))
        self.watermark = QLineEdit(placeholderText="Để trống = không có")
        box.addWidget(self.watermark)

        box.addWidget(QLabel("CAMERA (để tính khoảng cách)", objectName="section"))
        self.fov = QComboBox()
        for text, value in FOV_PRESETS:
            self.fov.addItem(text, value)
        box.addWidget(self.fov)

        box.addWidget(QLabel("NÂNG CAO", objectName="section"))
        self.res = QComboBox()
        for text, value in (("Ảnh vào model 1280 (mặc định)", 1280), ("1536 · video 4K, người rất xa", 1536),
                            ("960 · nhanh hơn", 960)):
            self.res.addItem(text, value)
        box.addWidget(self.res)
        self.redetect = QCheckBox("Nhận diện lại (bỏ kết quả đã lưu)")
        box.addWidget(self.redetect)
        box.addStretch(1)
        return frame

    # ---- state

    def _update_hint(self):
        if self.mode_max.isChecked():
            self.mode_hint.setText("RF-DETR Large + YOLO11x-pose, 1280 px. Bắt được người bị che và ở xa tốt nhất. "
                                   "≈ 4–5 khung/s với video 1080p.")
        else:
            self.mode_hint.setText("Chỉ YOLO11x-pose. Nhanh gấp ~2–3 lần, sót người bị che nhiều hơn.")

    def _load_settings(self):
        s = self.settings
        (self.mode_fast if s.value("fast", False, bool) else self.mode_max).setChecked(True)
        defaults = {"boxes": True, "cards": True, "snaplines": True, "counter": True, "list": False, "log": False,
                    "animals": False}
        for key, c in self.checks.items():
            c.setChecked(s.value(key, defaults[key], bool))
        self.watermark.setText(s.value("watermark", "", str))
        self.fov.setCurrentIndex(int(s.value("fov_index", 0)))
        self.res.setCurrentIndex(int(s.value("res_index", 0)))
        self._update_hint()

    def _save_settings(self):
        s = self.settings
        s.setValue("fast", self.mode_fast.isChecked())
        for key, c in self.checks.items():
            s.setValue(key, c.isChecked())
        s.setValue("watermark", self.watermark.text())
        s.setValue("fov_index", self.fov.currentIndex())
        s.setValue("res_index", self.res.currentIndex())

    def _options_for(self, path: Path):
        import esp_video
        c = self.checks
        return esp_video.Options(
            input=path, fast=self.mode_fast.isChecked(), animals=c["animals"].isChecked(),
            imgsz=self.res.currentData(), detr_res=self.res.currentData(), fov=float(self.fov.currentData()),
            redetect=self.redetect.isChecked(), boxes=c["boxes"].isChecked(), cards=c["cards"].isChecked(),
            snaplines=c["snaplines"].isChecked(), counter=c["counter"].isChecked(), list=c["list"].isChecked(),
            log=c["log"].isChecked(), watermark=self.watermark.text().strip())

    def _busy(self):
        return self.thread is not None

    def _refresh_buttons(self):
        busy = self._busy()
        has = self.queue.count() > 0
        self.start.setEnabled(has and not busy)
        self.cancel.setEnabled(busy)
        self.remove.setEnabled(has and not busy)
        row = self.queue.currentRow()
        self.open_video.setEnabled(row in self.outputs)
        self.open_folder.setEnabled(row in self.outputs or has)

    # ---- queue

    def add_files(self, paths):
        for p in paths:
            p = Path(p)
            if p.suffix.lower() not in VIDEO_EXT or p.stem.endswith("_esp"):
                continue
            item = QListWidgetItem(f"⏳  {p.name}")
            item.setData(Qt.UserRole, str(p))
            self.queue.addItem(item)
        if self.queue.currentRow() < 0 and self.queue.count():
            self.queue.setCurrentRow(0)
        self._refresh_buttons()

    def _pick_files(self):
        files, _ = QFileDialog.getOpenFileNames(self, "Chọn video", "", "Video (*.mp4 *.mov *.m4v *.avi *.mkv *.webm)")
        self.add_files(files)

    def _remove_selected(self):
        row = self.queue.currentRow()
        if row >= 0 and not self._busy():
            self.queue.takeItem(row)
            self.outputs = {(i if i < row else i - 1): o for i, o in self.outputs.items() if i != row}
        self._refresh_buttons()

    def _show_selected(self, row):
        self._refresh_buttons()
        if row < 0 or self._busy():
            return
        path = Path(self.queue.item(row).data(Qt.UserRole))
        source = Path(self.outputs[row]) if row in self.outputs else path
        frame, (w, h, fps, n) = first_frame(source)
        if frame is not None:
            self.last_frame = frame
            self.preview.setPixmap(bgr_to_pixmap(frame, self.preview.size()))
        secs = n / fps if fps else 0
        self.info.setText(f"{path.name} · {w}×{h} · {fps:.0f} fps · {int(secs // 60)}:{int(secs % 60):02d}"
                          + ("  ·  ✓ đã có bản ESP" if row in self.outputs else ""))

    # ---- run

    def _start(self):
        if self._busy() or not self.queue.count():
            return
        self._save_settings()
        jobs = []
        for i in range(self.queue.count()):
            path = Path(self.queue.item(i).data(Qt.UserRole))
            jobs.append((i, self._options_for(path)))
        self.thread = QThread()
        self.worker = Worker(jobs)
        self.worker.moveToThread(self.thread)
        self.thread.started.connect(self.worker.run)
        self.worker.progress.connect(self._on_progress)
        self.worker.preview.connect(self._on_preview)
        self.worker.message.connect(lambda m: self.status.setText(m))
        self.worker.started_item.connect(self._on_started)
        self.worker.finished_item.connect(self._on_finished)
        self.worker.failed_item.connect(self._on_failed)
        self.worker.done.connect(self._on_done)
        self.thread.start()
        self.bar.setValue(0)
        self.status.setText("Đang tải model… (lần đầu mất ~10–20 giây)")
        self._refresh_buttons()

    def _cancel(self):
        if self.worker:
            self.worker.cancel = True
            self.status.setText("Đang huỷ…")

    def _set_icon(self, index, icon):
        item = self.queue.item(index)
        if item:
            item.setText(f"{icon}  {Path(item.data(Qt.UserRole)).name}")

    def _on_started(self, index):
        self.queue.setCurrentRow(index)
        self._set_icon(index, "▶")
        self.bar.setValue(0)

    def _on_progress(self, pct, line):
        self.bar.setValue(pct)
        self.status.setText(line)

    def _on_preview(self, frame):
        self.last_frame = frame
        self.preview.setPixmap(bgr_to_pixmap(frame, self.preview.size()))

    def _on_finished(self, index, out):
        self.outputs[index] = out
        self._set_icon(index, "✓")
        self.bar.setValue(100)
        self.status.setText(f"Xong: {Path(out).name}")
        self._refresh_buttons()

    def _on_failed(self, index, why):
        self._set_icon(index, "✕")
        self.status.setText(why)

    def _on_done(self):
        self.thread.quit()
        self.thread.wait()
        self.thread, self.worker = None, None
        self.redetect.setChecked(False)
        self._refresh_buttons()

    def _open_output(self):
        row = self.queue.currentRow()
        if row in self.outputs:
            os.startfile(self.outputs[row])

    def _open_folder(self):
        row = self.queue.currentRow()
        target = self.outputs.get(row) or (self.queue.item(row).data(Qt.UserRole) if row >= 0 else None)
        if target:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(Path(target).parent)))

    # ---- window events

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event: QDropEvent):
        self.add_files(u.toLocalFile() for u in event.mimeData().urls())

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self.last_frame is not None:
            self.preview.setPixmap(bgr_to_pixmap(self.last_frame, self.preview.size()))

    def closeEvent(self, event):
        self._save_settings()
        if self.worker:
            self.worker.cancel = True
        if self.thread:
            self.thread.quit()
            self.thread.wait(3000)
        super().closeEvent(event)


def main():
    app = QApplication(sys.argv)
    app.setStyleSheet(STYLE)
    app.setFont(QFont("Segoe UI", 10))
    window = Studio()
    window.add_files(sys.argv[1:])
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
