"""ESP on a live stream (or a video file / webcam), on the PC's GPU.

Same look as the iOS app: thin corner boxes that get bolder when near and fade when far, a detail card
(Người / animal, ~distance, speed, time in view), lite snaplines from the top, a counter, an in-view list,
an event log and a watermark. People come from YOLO11x-pose (boxes trimmed to the visible body), animals
from YOLO11x; both tracked with ByteTrack.

    python esp_live.py <url | file | webcam index> [--animals] [--record out.mp4]

A URL can be RTSP/HTTP(S)/.m3u8 (IP cameras, OBS/phone streamers) or a YouTube/Twitch/... page (via yt-dlp).
There is no depth here: distances are guessed from body size and the camera's field of view (--fov), so
they carry a "~" and speeds are rough.
"""
from __future__ import annotations

import argparse
import math
import sys
import threading
import time
from collections import deque
from dataclasses import dataclass, field

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

GREEN = (88, 199, 52)       # BGR of iOS systemGreen
ORANGE = (10, 159, 255)     # BGR of iOS systemOrange
BLUE = (255, 160, 10)       # BGR of iOS systemBlue-ish, for vehicles
ANIMALS = {14: "Chim", 15: "Mèo", 16: "Chó", 17: "Ngựa", 18: "Cừu", 19: "Bò", 20: "Voi", 21: "Gấu", 22: "Ngựa vằn",
           23: "Hươu cao cổ"}
ANIMAL_HEIGHT = {14: 0.25, 15: 0.3, 16: 0.55, 17: 1.7, 18: 0.9, 19: 1.5, 20: 3.0, 21: 1.2, 22: 1.4, 23: 4.5}
# Ultralytics COCO index → name / typical box height in meters (for guessing distance).
VEHICLES = {1: "Xe đạp", 2: "Ô tô", 3: "Xe máy", 5: "Xe buýt", 7: "Xe tải"}
VEHICLE_HEIGHT = {1: 1.05, 2: 1.5, 3: 1.15, 5: 3.1, 7: 3.0}
PERSON_HEIGHT, TORSO = 1.7, 0.5
NEAR, FAR = 1.5, 18.0
RIDING_SPEED = 6.5          # m/s, ~23 km/h: on a vehicle, not on foot
EVENT_TTL, EVENTS_SHOWN, LEAVE_AFTER = 8.0, 5, 1.0

# COCO keypoint indices
NOSE, L_EYE, R_EYE, L_EAR, R_EAR, L_SH, R_SH = 0, 1, 2, 3, 4, 5, 6
L_HIP, R_HIP, L_ANK, R_ANK = 11, 12, 15, 16


# ---------------------------------------------------------------------------------------------------------- source

def resolve(source: str):
    """Webcam index, file path or stream URL as OpenCV can open it; web pages go through yt-dlp."""
    if source.isdigit():
        return int(source)
    if source.startswith(("http://", "https://")) and not any(s in source for s in (".m3u8", ".mp4", ".mjpg", "mjpeg")):
        import yt_dlp
        with yt_dlp.YoutubeDL({"quiet": True, "format": "best[height<=1080]/best"}) as ydl:
            info = ydl.extract_info(source, download=False)
            print(f"stream: {info.get('title', source)}")
            return info["url"]
    return source


class LatestFrame:
    """Reads a live source on its own thread and keeps only the newest frame, so the ESP never lags behind the
    stream. Files are read in order instead (no dropping)."""

    def __init__(self, source, live: bool):
        self.cap = cv2.VideoCapture(source, cv2.CAP_FFMPEG) if isinstance(source, str) else cv2.VideoCapture(source)
        if not self.cap.isOpened():
            raise SystemExit(f"Không mở được nguồn: {source}")
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        self.live = live
        self.frame, self.stamp, self.ended = None, 0.0, False
        self.cond = threading.Condition()
        if live:
            threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        while True:
            ok, frame = self.cap.read()
            with self.cond:
                if not ok:
                    self.ended = True
                    self.cond.notify_all()
                    return
                self.frame, self.stamp = frame, time.monotonic()
                self.cond.notify_all()

    def read(self):
        if not self.live:
            ok, frame = self.cap.read()
            return (frame, time.monotonic()) if ok else (None, 0.0)
        with self.cond:
            while self.frame is None and not self.ended:
                self.cond.wait(1)
            frame, stamp, self.frame = self.frame, self.stamp, None
            return frame, stamp

    @property
    def fps(self):
        return self.cap.get(cv2.CAP_PROP_FPS) or 30


# --------------------------------------------------------------------------------------------------------- geometry

def nearness(d: float) -> float:
    """1 at arm's length, 0 far down the street; logarithmic like perspective."""
    if not math.isfinite(d) or d <= NEAR:
        return 1.0
    return 1 - min(max(math.log(d / NEAR) / math.log(FAR / NEAR), 0), 1)


def visible_box(box, kpts, conf, threshold=0.35):
    """Trims the detector's full-body guess to the keypoints that are actually seen (never grows it)."""
    x0, y0, x1, y1 = box
    seen = conf >= threshold
    if seen.sum() < 5 or not (seen[L_SH] or seen[R_SH]):
        return box
    pts = kpts[seen]
    bx0, by0 = pts.min(axis=0)
    bx1, by1 = pts.max(axis=0)
    sh = kpts[[i for i in (L_SH, R_SH) if seen[i]]].mean(axis=0)
    hips = [i for i in (L_HIP, R_HIP) if seen[i]]
    if hips:
        unit = float(np.linalg.norm(sh - kpts[hips].mean(axis=0)))
    elif seen[L_SH] and seen[R_SH]:
        unit = float(np.linalg.norm(kpts[L_SH] - kpts[R_SH])) * 1.6
    else:
        unit = float(by1 - by0)
    if unit < 4:
        return box
    head = [kpts[i][1] for i in (NOSE, L_EYE, R_EYE, L_EAR, R_EAR) if seen[i]]
    top = (min(head) - 0.35 * unit) if head else by0 - 0.6 * unit
    bottom = by1 + (0.15 if (seen[L_ANK] or seen[R_ANK]) else 0.3) * unit
    nx0, nx1 = max(x0, bx0 - 0.35 * unit), min(x1, bx1 + 0.35 * unit)
    ny0, ny1 = max(y0, top), min(y1, bottom)
    if nx1 - nx0 < 0.2 * (x1 - x0) or ny1 - ny0 < 0.2 * (y1 - y0):
        return box
    return (nx0, ny0, nx1, ny1)


def torso_px(kpts, conf, threshold=0.35):
    idx = (L_SH, R_SH, L_HIP, R_HIP)
    if any(conf[i] < threshold for i in idx):
        return None
    return float(np.linalg.norm((kpts[L_SH] + kpts[R_SH]) / 2 - (kpts[L_HIP] + kpts[R_HIP]) / 2))


def estimate_distance(box, height_m, focal, frame_h, torso=None):
    """No depth: torso length for people cut off by the frame or squatting/sitting, else box height."""
    x0, y0, x1, y1 = box
    h, w = y1 - y0, x1 - x0
    clipped = y0 < 0.02 * frame_h or y1 > 0.98 * frame_h
    if torso and torso > 8 and (clipped or h < 1.8 * w):
        return focal * TORSO / torso
    return focal * height_m / max(h, 1)


# ------------------------------------------------------------------------------------------------------- tracking

@dataclass
class Tracked:
    label: str
    is_person: bool
    first: float
    last: float
    pos: np.ndarray | None = None          # (x, z) on the floor, meters
    vel: np.ndarray = field(default_factory=lambda: np.zeros(2))
    fast: int = 0
    announced: bool = False
    entry_event: int | None = None


class World:
    """Per-track floor position, smoothed velocity and the event log."""

    def __init__(self):
        self.tracks: dict[str, Tracked] = {}
        self.events: deque = deque()
        self.next_event = 1

    def log(self, text, now):
        eid = self.next_event
        self.next_event += 1
        self.events.append([eid, text, now])
        while len(self.events) > EVENTS_SHOWN:
            self.events.popleft()
        return eid

    def update(self, key, label, is_person, floor, now):
        t = self.tracks.get(key)
        if t is None:
            t = self.tracks[key] = Tracked(label, is_person, now, now)
            t.entry_event = self.log(f"{label} vừa vào khung hình" if is_person else f"{label} xuất hiện", now)
        dt = max(now - t.last, 1e-3)
        if t.pos is not None:
            # Guessed distances jitter: heavy smoothing on the velocity, lighter on the position.
            t.vel = 0.85 * t.vel + 0.15 * ((floor - t.pos) / dt)
            t.pos = 0.6 * t.pos + 0.4 * floor
        else:
            t.pos = floor
        t.last = now
        speed = float(np.linalg.norm(t.vel))
        t.fast = t.fast + 1 if is_person and speed >= RIDING_SPEED else 0
        if t.fast >= 3 and not t.announced:
            t.announced = True
            text = f"{label} phóng qua · {kmh(speed)}"
            fresh = next((e for e in self.events if e[0] == t.entry_event and now - e[2] < 2), None)
            if fresh:
                fresh[1], fresh[2] = text, now
            else:
                self.log(text, now)
        return t

    def sweep(self, now):
        for key, t in list(self.tracks.items()):
            if now - t.last > LEAVE_AFTER:
                self.log(f"{t.label} rời khung hình", now)
                del self.tracks[key]
        while self.events and now - self.events[0][2] > EVENT_TTL:
            self.events.popleft()


def kmh(mps: float) -> str:
    if mps < 0.3:
        return "0 km/h"
    v = mps * 3.6
    return f"{v:.1f} km/h" if v < 10 else f"{v:.0f} km/h"


def meters(d: float, approx: bool = True) -> str:
    """"~" marks a distance guessed from body size; measured (depth model) ones go without."""
    mark = "~" if approx else ""
    return f"{mark}{d:.1f} m" if d < 10 else f"{mark}{d:.0f} m"


def clock(s: float) -> str:
    s = max(int(s), 0)
    return f"{s // 60:02d}:{s % 60:02d}"


# -------------------------------------------------------------------------------------------------------- drawing

class Painter:
    def __init__(self, scale: float = 1.0):
        """`scale` grows text and panels with the video (1 at 1080p)."""
        self.scale = scale
        fonts = "C:/Windows/Fonts/"
        try:
            self.bold = ImageFont.truetype(fonts + "seguisb.ttf", round(18 * scale))
            self.small = ImageFont.truetype(fonts + "segoeui.ttf", round(15 * scale))
        except OSError:
            self.bold = self.small = ImageFont.load_default()
        self.texts: list = []   # (xy, text, font, rgb)
        self._fonts: dict = {}

    def font(self, bold: bool, factor: float):
        """The bold/small font at `factor` × its size (cached in 10% steps), for cards that shrink with distance."""
        key = (bold, round(factor * 10))
        if key not in self._fonts:
            base = (18 if bold else 15) * self.scale * key[1] / 10
            try:
                self._fonts[key] = ImageFont.truetype("C:/Windows/Fonts/" + ("seguisb.ttf" if bold else "segoeui.ttf"),
                                                      max(round(base), 8))
            except OSError:
                self._fonts[key] = self.bold if bold else self.small
        return self._fonts[key]

    def text(self, xy, text, font=None, rgb=(255, 255, 255)):
        self.texts.append((xy, text, font or self.small, rgb))

    def measure(self, text, font=None):
        l, t, r, b = (font or self.small).getbbox(text)
        return r - l, b - t

    @staticmethod
    def panel(img, x0, y0, x1, y1, tint=(30, 30, 30), alpha=0.55, radius=12):
        """Rounded translucent glass-ish panel."""
        h, w = img.shape[:2]
        x0, y0, x1, y1 = max(int(x0), 0), max(int(y0), 0), min(int(x1), w), min(int(y1), h)
        if x1 <= x0 or y1 <= y0:
            return
        roi = img[y0:y1, x0:x1]
        mask = np.zeros(roi.shape[:2], np.uint8)
        r = min(radius, (x1 - x0) // 2, (y1 - y0) // 2)
        cv2.rectangle(mask, (r, 0), (x1 - x0 - r, y1 - y0), 255, -1)
        cv2.rectangle(mask, (0, r), (x1 - x0, y1 - y0 - r), 255, -1)
        for cx, cy in ((r, r), (x1 - x0 - r, r), (r, y1 - y0 - r), (x1 - x0 - r, y1 - y0 - r)):
            cv2.circle(mask, (cx, cy), r, 255, -1, cv2.LINE_AA)
        blurred = cv2.GaussianBlur(roi, (0, 0), 6)
        glass = cv2.addWeighted(blurred, 1 - alpha, np.full_like(roi, tint), alpha, 0)
        m = (mask.astype(np.float32) / 255)[..., None]
        roi[:] = (glass * m + roi * (1 - m)).astype(np.uint8)

    def flush(self, img):
        if not self.texts:
            return img
        pil = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(pil)
        for (x, y), text, font, rgb in self.texts:
            draw.text((x + 1, y + 1), text, font=font, fill=(0, 0, 0))
            draw.text((x, y), text, font=font, fill=rgb)
        self.texts.clear()
        return cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)


def _blend_roi(img, x0, y0, x1, y1, draw, alpha):
    """Runs `draw(layer, ox, oy)` on a copy of just this region and blends it back with `alpha`."""
    h, w = img.shape[:2]
    x0, y0, x1, y1 = max(int(x0), 0), max(int(y0), 0), min(int(x1), w), min(int(y1), h)
    if x1 <= x0 or y1 <= y0:
        return
    roi = img[y0:y1, x0:x1]
    layer = roi.copy()
    draw(layer, x0, y0)
    cv2.addWeighted(layer, alpha, roi, 1 - alpha, 0, roi)


def corners(img, box, color, d, ghost=False):
    """Thin corner box: 0.8-1.6 px wide (scaled to the frame), bold and glowing near, faded far. `ghost` (hidden
    behind something, position inferred) draws it thin and faint with no glow."""
    x0, y0, x1, y1 = (int(v) for v in box)
    n = nearness(d)
    scale = max(img.shape[0] / 720, 1)
    width = max(1, round((0.8 + 0.8 * n) * scale * (0.7 if ghost else 1)))
    glow = round(3 * n * scale)
    l = int(min(x1 - x0, y1 - y0) * 0.22)
    segs = [((x0, y0), (x0 + l, y0)), ((x0, y0), (x0, y0 + l)), ((x1, y0), (x1 - l, y0)), ((x1, y0), (x1, y0 + l)),
            ((x0, y1), (x0 + l, y1)), ((x0, y1), (x0, y1 - l)), ((x1, y1), (x1 - l, y1)), ((x1, y1), (x1, y1 - l))]
    pad = width + glow + 4

    def lines(thickness, colour):
        def draw(layer, ox, oy):
            for a, b in segs:
                cv2.line(layer, (a[0] - ox, a[1] - oy), (b[0] - ox, b[1] - oy), colour, thickness, cv2.LINE_AA)
        return draw

    if n > 0.05 and not ghost:
        _blend_roi(img, x0 - pad, y0 - pad, x1 + pad, y1 + pad, lines(width + glow, color), 0.18 * n)

    def body(layer, ox, oy):
        lines(width + 1, (0, 0, 0))(layer, ox, oy)
        lines(width, color)(layer, ox, oy)
    _blend_roi(img, x0 - pad, y0 - pad, x1 + pad, y1 + pad, body, (0.45 + 0.55 * n) * (0.45 if ghost else 1))


def snapline(img, box, color, d, ghost=False):
    """Lite line from the top centre to the box's top edge, fading in toward the box (fainter when `ghost`)."""
    x0, y0, x1, _ = box
    top = np.array([img.shape[1] / 2, 0.0])
    end = np.array([(x0 + x1) / 2, y0])
    opacity = 0.7 * (0.45 + 0.55 * nearness(d)) * (0.45 if ghost else 1)
    steps = 10
    for i in range(steps):
        a, b = top + (end - top) * i / steps, top + (end - top) * (i + 1) / steps
        def draw(layer, ox, oy, a=a, b=b):
            cv2.line(layer, (int(a[0] - ox), int(a[1] - oy)), (int(b[0] - ox), int(b[1] - oy)), color, 1, cv2.LINE_AA)
        _blend_roi(img, min(a[0], b[0]) - 2, min(a[1], b[1]) - 2, max(a[0], b[0]) + 3, max(a[1], b[1]) + 3, draw,
                   opacity * (i + 1) / steps)
    ex, ey = int(end[0]), int(end[1])
    _blend_roi(img, ex - 4, ey - 4, ex + 5, ey + 5,
               lambda layer, ox, oy: cv2.circle(layer, (ex - ox, ey - oy), 3, color, -1, cv2.LINE_AA), 0.9)


def card(img, painter, box, color, title, rows, d, taken=None):
    """Detail card beside the box, smaller and fainter when far. With `taken` (rects of cards already drawn, nearest
    people first) it tries right, left, then above the box and skips the card when all three would overlap, so a
    crowd doesn't turn into a pile of cards. Returns whether it was drawn."""
    x0, y0, x1, _ = box
    f = 0.72 + 0.28 * nearness(d)
    s = f * painter.scale
    bold, small = painter.font(True, f), painter.font(False, f)
    pad, line = int(10 * s), int(21 * s)
    widths = [painter.measure(title, bold)[0]] + [painter.measure(r, small)[0] for r in rows]
    w, h = int(max(widths) + 2 * pad + 4), int(line * (len(rows) + 1) + 2 * pad)
    gap = int(8 * painter.scale)
    H, W = img.shape[:2]
    candidates = [(x1 + gap, max(int(y0), 4)), (x0 - gap - w, max(int(y0), 4)),
                  (int((x0 + x1) / 2 - w / 2), int(y0) - gap - h)]
    spot = None
    for cx, cy in candidates:
        if cx < 0 or cy < 0 or cx + w > W or cy + h > H:
            continue
        if taken is not None and any(cx < tx1 and tx0 < cx + w and cy < ty1 and ty0 < cy + h
                                     for tx0, ty0, tx1, ty1 in taken):
            continue
        spot = (cx, cy)
        break
    if spot is None:
        if taken is not None:
            return False
        spot = (x1 + gap if x1 + gap + w < W else x0 - gap - w, max(int(y0), 4))
    cx, cy = spot
    if taken is not None:
        taken.append((cx - 4, cy - 4, cx + w + 4, cy + h + 4))
    tint = tuple(int(c * 0.35) for c in color)
    Painter.panel(img, cx, cy, cx + w, cy + h, tint=tint, alpha=0.5 + 0.2 * nearness(d), radius=int(12 * painter.scale))
    painter.text((cx + pad, cy + pad - int(3 * s)), title, bold)
    for i, r in enumerate(rows):
        painter.text((cx + pad, cy + pad + line * (i + 1) - int(3 * s)), r, small)
    return True


# ----------------------------------------------------------------------------------------------------------- main

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="ESP on a live stream, file or webcam (GPU).")
    ap.add_argument("source", help="URL (RTSP / HTTP / m3u8 / YouTube…), video file or webcam index")
    ap.add_argument("--model", default="yolo11x-pose.pt", help="people (pose) model")
    ap.add_argument("--animals", action="store_true", help="also track animals (YOLO11x)")
    ap.add_argument("--imgsz", type=int, default=1280, help="model input size (bigger sees farther people)")
    ap.add_argument("--fov", type=float, default=70, help="camera horizontal field of view, degrees")
    ap.add_argument("--record", help="also save the ESP video to this .mp4")
    ap.add_argument("--watermark", default="ESP v3 · Undetected")
    ap.add_argument("--no-snaplines", action="store_true")
    ap.add_argument("--headless", action="store_true", help="no window (record only)")
    args = ap.parse_args()

    import torch
    from ultralytics import YOLO

    device = 0 if torch.cuda.is_available() else "cpu"
    half = device == 0
    print(f"device: {torch.cuda.get_device_name(0) if half else 'CPU (chậm!)'}")
    people_model = YOLO(args.model)
    animal_model = YOLO("yolo11x.pt") if args.animals else None

    source = resolve(args.source)
    # Streams and webcams are live (drop stale frames); files play every frame.
    live = isinstance(source, int) or source.startswith(("rtsp", "rtmp", "http", "udp", "srt"))
    reader = LatestFrame(source, live)
    writer = None
    world, painter = World(), Painter()
    fps, last, frames = 0.0, time.monotonic(), 0
    if not args.headless:
        cv2.namedWindow("ESP", cv2.WINDOW_NORMAL)

    while True:
        frame, now = reader.read()
        if frame is None:
            break
        H, W = frame.shape[:2]
        focal = max(W, H) / 2 / math.tan(math.radians(args.fov) / 2)   # FOV of the long side
        seen = []   # (key, label, box, color, distance, is_person)

        res = people_model.track(frame, persist=True, tracker="bytetrack.yaml", imgsz=args.imgsz, quantize=16 if half else None,
                                 device=device, classes=[0], conf=0.2, verbose=False)[0]
        if res.boxes is not None and res.boxes.id is not None:
            boxes = res.boxes.xyxy.cpu().numpy()
            ids = res.boxes.id.int().cpu().numpy()
            kp = res.keypoints.xy.cpu().numpy() if res.keypoints is not None else None
            kc = res.keypoints.conf.cpu().numpy() if res.keypoints is not None and res.keypoints.conf is not None else None
            for i, (box, tid) in enumerate(zip(boxes, ids)):
                torso = None
                if kp is not None and kc is not None:
                    box = visible_box(tuple(box), kp[i], kc[i])
                    torso = torso_px(kp[i], kc[i])
                d = estimate_distance(box, PERSON_HEIGHT, focal, H, torso)
                seen.append((f"p{tid}", "Người", box, GREEN, d, True))

        if animal_model is not None:
            ares = animal_model.track(frame, persist=True, tracker="bytetrack.yaml", imgsz=min(args.imgsz, 960),
                                      quantize=16 if half else None, device=device, classes=list(ANIMALS), conf=0.3, verbose=False)[0]
            if ares.boxes is not None and ares.boxes.id is not None:
                for box, tid, cls in zip(ares.boxes.xyxy.cpu().numpy(), ares.boxes.id.int().cpu().numpy(),
                                         ares.boxes.cls.int().cpu().numpy()):
                    d = estimate_distance(tuple(box), ANIMAL_HEIGHT[int(cls)], focal, H)
                    seen.append((f"a{tid}", ANIMALS[int(cls)], tuple(box), ORANGE, d, False))

        # World positions (floor x, z) for speed; then draw far first so near sits on top.
        state = {}
        for key, label, box, color, d, is_person in seen:
            cx = (box[0] + box[2]) / 2
            floor = np.array([(cx - W / 2) / focal * d, d])
            state[key] = world.update(key, label, is_person, floor, now)
        world.sweep(now)

        for key, label, box, color, d, is_person in sorted(seen, key=lambda s: -s[4]):
            if not args.no_snaplines:
                snapline(frame, box, color, d)
            corners(frame, box, color, d)
        taken = []
        for key, label, box, color, d, is_person in sorted(seen, key=lambda s: s[4]):   # nearest gets the room
            t = state[key]
            card(frame, painter, box, color, label,
                 [meters(d), kmh(float(np.linalg.norm(t.vel))), clock(now - t.first)], d, taken)

        # HUD: counter + fps (top left), in-view list (top right), event log + watermark (bottom left).
        dt = time.monotonic() - last
        last = time.monotonic()
        fps = 1 / dt if fps == 0 else fps * 0.9 + 0.1 / max(dt, 1e-3)
        people = sum(1 for s in seen if s[5])
        animals = {}
        for s in seen:
            if not s[5]:
                animals[s[1]] = animals.get(s[1], 0) + 1
        summary = " · ".join(([f"{people} người"] if people else []) + [f"{k} {v}" for k, v in animals.items()]) or "Đang quét…"
        counter = f"{summary}   {fps:.0f} fps"
        cw, _ = painter.measure(counter, painter.bold)
        Painter.panel(frame, 16, 16, 16 + cw + 50, 52, radius=18)
        cv2.circle(frame, (36, 34), 6, GREEN, 2, cv2.LINE_AA)
        painter.text((52, 22), counter, painter.bold)

        rows = sorted(seen, key=lambda s: s[4])[:8]
        lw, lh = 230, 34 + 22 * max(len(rows), 1)
        Painter.panel(frame, W - lw - 16, 16, W - 16, 16 + lh, radius=14)
        painter.text((W - lw - 4, 22), "TRONG KHUNG", painter.small, (200, 200, 200))
        if not rows:
            painter.text((W - lw - 4, 44), "Không có ai", painter.small, (200, 200, 200))
        for i, (_, label, _, color, d, _) in enumerate(rows):
            y = 44 + 22 * i
            cv2.circle(frame, (W - lw + 2, y + 10), 4, color, -1, cv2.LINE_AA)
            painter.text((W - lw + 14, y), label, painter.bold)
            dist = meters(d)
            painter.text((W - 28 - painter.measure(dist)[0], y), dist)

        y = H - 24 - 30 * (len(world.events) + 1)
        for _, text, at in world.events:
            line = f"› {text}"
            w, _ = painter.measure(line)
            Painter.panel(frame, 16, y, 16 + w + 24, y + 26, radius=13)
            painter.text((28, y + 3), line)
            y += 30
        mark = args.watermark
        w, _ = painter.measure(mark)
        Painter.panel(frame, 16, H - 46, 16 + w + 24, H - 20, radius=13)
        painter.text((28, H - 43), mark, rgb=(230, 230, 230))

        frame = painter.flush(frame)
        frames += 1
        if args.record:
            if writer is None:
                writer = cv2.VideoWriter(args.record, cv2.VideoWriter_fourcc(*"mp4v"), min(reader.fps, 60), (W, H))
            writer.write(frame)
        if not args.headless:
            cv2.imshow("ESP", frame)
            if cv2.waitKey(1) & 0xFF in (ord("q"), 27):
                break

    if frames:
        print(f"{frames} khung · trung bình {fps:.1f} fps")
    if writer is not None:
        writer.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
