"""Video in, ESP video out, as accurate as the GPU can make it (offline, no real-time limit).

    python esp_video.py input.mp4 [-o output.mp4] [--animals] [--fast]

Pass 1 detects and tracks every frame with two models: RF-DETR Large at 1280 px (run on the frame and its mirror)
and YOLO11x-pose at 1280 px with test-time augmentation, their person boxes fused (one model's misses filled by
the other), tracked by BoT-SORT with camera-motion compensation and appearance re-identification, boxes trimmed
to the visible body using YOLO's keypoints. `--fast` uses YOLO11x-pose alone. Then, knowing the whole video, each track is cleaned up: one-off false detections dropped, short
gaps (missed frames) filled in, boxes smoothed both forwards and backwards, distance and speed smoothed.
Pass 2 draws the ESP (same look as the iOS app) and encodes H.264 with the original audio.
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
import time
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np

from ensemble import DETR_ANIMALS, DETR_PERSON, Detections, detr_detect, fuse, load_detr, make_tracker
from esp_live import (ANIMAL_HEIGHT, ANIMALS, EVENT_TTL, EVENTS_SHOWN, GREEN, ORANGE, PERSON_HEIGHT, RIDING_SPEED,
                      Painter, card, clock, corners, estimate_distance, kmh, meters, snapline, torso_px, visible_box)

HERE = Path(__file__).resolve().parent


@dataclass
class Track:
    key: str
    label: str
    color: tuple
    height: float                       # typical height in meters, for distance
    frames: list = field(default_factory=list)
    boxes: list = field(default_factory=list)
    torsos: list = field(default_factory=list)
    # Filled in by `finish`, indexed like `span`.
    span: np.ndarray | None = None
    box: np.ndarray | None = None
    dist: np.ndarray | None = None
    speed: np.ndarray | None = None

    @property
    def is_person(self):
        return self.key.startswith("p")


# ------------------------------------------------------------------------------------------------------- helpers

def gaussian_smooth(values: np.ndarray, sigma: float) -> np.ndarray:
    """Centered Gaussian smoothing along axis 0 (uses past and future frames), edges reflected."""
    if sigma <= 0 or len(values) < 3:
        return values
    radius = max(1, int(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-radius, radius + 1) / sigma) ** 2)
    k /= k.sum()
    pad = min(radius, len(values) - 1)
    padded = np.pad(values, [(pad, pad)] + [(0, 0)] * (values.ndim - 1), mode="reflect")
    if pad < radius:
        padded = np.pad(padded, [(radius - pad, radius - pad)] + [(0, 0)] * (values.ndim - 1), mode="edge")
    out = np.empty_like(values, dtype=np.float64)
    flat = padded.reshape(len(padded), -1)
    res = np.stack([np.convolve(flat[:, j], k, mode="valid") for j in range(flat.shape[1])], axis=1)
    out[:] = res.reshape(values.shape)
    return out


def finish(track: Track, fps: float, W: int, H: int, focal: float, max_gap: int):
    """Fill gaps up to `max_gap` frames by interpolation, split at longer ones, smooth, compute distance and speed."""
    frames = np.array(track.frames)
    boxes = np.array(track.boxes, dtype=np.float64)
    torsos = np.array([t if t else np.nan for t in track.torsos], dtype=np.float64)

    span, box, torso = [], [], []
    for i in range(len(frames)):
        if i and 1 < frames[i] - frames[i - 1] <= max_gap:
            a, b = frames[i - 1], frames[i]
            for f in range(a + 1, b):
                t = (f - a) / (b - a)
                span.append(f)
                box.append(boxes[i - 1] * (1 - t) + boxes[i] * t)
                torso.append(np.nan)
        span.append(frames[i])
        box.append(boxes[i])
        torso.append(torsos[i])
    span, box, torso = np.array(span), np.array(box), np.array(torso)

    # Smooth within each contiguous run separately (a long gap is a real exit and re-entry).
    breaks = np.where(np.diff(span) > 1)[0] + 1
    smoothed = [gaussian_smooth(part, sigma=1.2) for part in np.split(box, breaks)]
    box = np.concatenate(smoothed)

    dist = np.array([estimate_distance(tuple(b), track.height, focal, H, None if np.isnan(t) else t)
                     for b, t in zip(box, torso)])
    log_d = np.concatenate([gaussian_smooth(part, sigma=fps * 0.25) for part in np.split(np.log(dist), breaks)])
    dist = np.exp(log_d)

    cx = (box[:, 0] + box[:, 2]) / 2
    floor = np.stack([(cx - W / 2) / focal * dist, dist], axis=1)
    speed = np.zeros(len(span))
    for part in np.split(np.arange(len(span)), breaks):
        p = gaussian_smooth(floor[part], sigma=fps * 0.3)
        if len(part) > 2:
            v = np.gradient(p, axis=0) * fps
            speed[part] = gaussian_smooth(np.linalg.norm(v, axis=1), sigma=fps * 0.2)

    track.span, track.box, track.dist, track.speed = span, box, dist, speed


def events_for(tracks: list[Track], fps: float):
    """Event log entries (frame, text) from the finished tracks: enter, ride past, leave."""
    raw = []
    for t in tracks:
        first, last = int(t.span[0]), int(t.span[-1])
        entry = [first, f"{t.label} vừa vào khung hình" if t.is_person else f"{t.label} xuất hiện"]
        raw.append(entry)
        if t.is_person:
            fast = np.convolve((t.speed >= RIDING_SPEED).astype(int), np.ones(3, int), mode="valid")
            hits = np.where(fast == 3)[0]
            if len(hits):
                at = int(t.span[hits[0] + 2])
                text = f"{t.label} phóng qua · {kmh(float(t.speed[hits[0] + 2]))}"
                if at - first < 2 * fps:
                    entry[1] = text
                else:
                    raw.append([at, text])
        raw.append([last + int(fps), f"{t.label} rời khung hình"])
    return sorted(raw, key=lambda e: e[0])


def encoder(path: Path, source: Path, W: int, H: int, fps: float):
    """ffmpeg reading raw BGR frames on stdin: H.264 (CRF 17), original audio as AAC when there is any."""
    import imageio_ffmpeg
    cmd = [imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{W}x{H}", "-r", f"{fps:.6f}", "-i", "-",
           "-i", str(source), "-map", "0:v", "-map", "1:a?",
           "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", str(path)]
    return subprocess.Popen(cmd, stdin=subprocess.PIPE)


def progress(label, done, total, started):
    rate = done / max(time.monotonic() - started, 1e-6)
    left = (total - done) / max(rate, 1e-6)
    print(f"\r{label}: {done}/{total} khung · {rate:.1f} khung/s · còn ~{int(left // 60)}:{int(left % 60):02d}   ",
          end="", flush=True)


# ---------------------------------------------------------------------------------------------------------- main

class Cancelled(Exception):
    pass


@dataclass
class Options:
    input: Path
    output: Path | None = None
    model: str = "yolo11x-pose.pt"
    imgsz: int = 1280
    no_tta: bool = False
    animals: bool = False
    fast: bool = False
    detr_res: int = 1280
    fov: float = 70
    min_seconds: float = 0.4
    redetect: bool = False
    # Look
    boxes: bool = True
    cards: bool = True
    snaplines: bool = True
    counter: bool = True
    list: bool = False
    log: bool = False
    watermark: str = ""


def run(o: Options, say=print, report=None, preview=None, stop=lambda: False) -> Path:
    """Processes one video. `report(stage, done, total, fps, eta_seconds)` and `preview(bgr_frame)` are called as it
    goes (stage "detect" or "draw"); `stop()` returning True cancels (raises Cancelled)."""
    last_preview = [0.0]

    def tick(stage, done, total, started, frame):
        rate = done / max(time.monotonic() - started, 1e-6)
        eta = (total - done) / max(rate, 1e-6)
        if report:
            report(stage, done, total, rate, eta)
        else:
            label = "Lượt 1/2 nhận diện" if stage == "detect" else "Lượt 2/2 vẽ ESP"
            print(f"\r{label}: {done}/{total} khung · {rate:.1f} khung/s · còn ~{int(eta // 60)}:{int(eta % 60):02d}   ",
                  end="", flush=True)
        if preview and stage == "draw" and time.monotonic() - last_preview[0] > 0.25:
            last_preview[0] = time.monotonic()
            preview(frame)

    import torch
    from ultralytics import YOLO

    if not o.input.exists():
        raise FileNotFoundError(f"Không thấy file: {o.input}")
    out = o.output or o.input.with_name(o.input.stem + "_esp.mp4")
    gpu = torch.cuda.is_available()
    say(f"GPU: {torch.cuda.get_device_name(0) if gpu else 'không có — sẽ rất chậm'}")
    device, quant = (0, 16) if gpu else ("cpu", None)

    cap = cv2.VideoCapture(str(o.input))
    W, H = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0
    say(f"Video: {W}×{H} · {fps:.2f} fps · {total} khung → {out.name}")
    focal = max(W, H) / 2 / math.tan(math.radians(o.fov) / 2)   # FOV of the long side (portrait too)

    cache = o.input.with_name(o.input.name + f".esp-{'fast' if o.fast else 'max'}-{o.imgsz}-{o.detr_res}"
                                                     f"{'-animals' if o.animals else ''}.pkl")
    cached = None
    if cache.exists() and not o.redetect:
        import pickle
        with open(cache, "rb") as fh:
            cached = pickle.load(fh)
        say(f"Dùng kết quả nhận diện đã lưu ({cache.name}); thêm --redetect để nhận diện lại.")

    # ---- pass 1: detect + track every frame
    people_model = YOLO(o.model)
    tta_people = not o.no_tta and getattr(people_model, "task", "") != "pose"
    tracks: dict[str, Track] = {}

    def add(key, label, color, height, idx, box, torso=None):
        t = tracks.setdefault(key, Track(key, label, color, height))
        t.frames.append(idx); t.boxes.append(tuple(box)); t.torsos.append(torso)

    if cached is not None:
        pass   # detections loaded from the cache: no models needed
    elif o.fast:
        animal_model = YOLO("yolo11x.pt") if o.animals else None
        tracker = str(HERE / "botsort_esp.yaml")
    else:
        # Ensemble: RF-DETR Large (+ mirror) and YOLO11x-pose (+ TTA), fused, tracked by our own BoT-SORT.
        detr, detr_res = load_detr(o.detr_res)
        say(f"Chế độ siêu chính xác: RF-DETR Large {detr_res}px + YOLO11x-pose {o.imgsz}px")
        people_tracker = make_tracker(HERE / "botsort_esp.yaml", fps)
        animal_tracker = make_tracker(HERE / "botsort_esp.yaml", fps) if o.animals else None

    started, idx = time.monotonic(), 0
    while cached is None:
        ok, frame = cap.read()
        if not ok:
            break
        if o.fast:
            res = people_model.track(frame, persist=True, tracker=tracker, imgsz=o.imgsz, augment=tta_people,
                                     quantize=quant, device=device, classes=[0], conf=0.1, iou=0.6, verbose=False)[0]
            if res.boxes is not None and res.boxes.id is not None:
                kp = res.keypoints.xy.cpu().numpy() if res.keypoints is not None else None
                kc = res.keypoints.conf.cpu().numpy() if res.keypoints is not None and res.keypoints.conf is not None else None
                for i, (box, tid) in enumerate(zip(res.boxes.xyxy.cpu().numpy(), res.boxes.id.int().cpu().numpy())):
                    torso, box = None, tuple(box)
                    if kp is not None and kc is not None:
                        box = visible_box(box, kp[i], kc[i])
                        torso = torso_px(kp[i], kc[i])
                    add(f"p{tid}", "Người", GREEN, PERSON_HEIGHT, idx, box, torso)
            if animal_model is not None:
                ares = animal_model.track(frame, persist=True, tracker=tracker, imgsz=o.imgsz, augment=not o.no_tta,
                                          quantize=quant, device=device, classes=list(ANIMALS), conf=0.25, verbose=False)[0]
                if ares.boxes is not None and ares.boxes.id is not None:
                    for box, tid, cls in zip(ares.boxes.xyxy.cpu().numpy(), ares.boxes.id.int().cpu().numpy(),
                                             ares.boxes.cls.int().cpu().numpy()):
                        add(f"a{tid}", ANIMALS[int(cls)], ORANGE, ANIMAL_HEIGHT[int(cls)], idx, box)
        else:
            y = people_model.predict(frame, imgsz=o.imgsz, augment=tta_people, quantize=quant, device=device,
                                     classes=[0], conf=0.1, iou=0.6, verbose=False)[0]
            yb = y.boxes.xyxy.cpu().numpy() if y.boxes is not None else np.zeros((0, 4))
            yc = y.boxes.conf.cpu().numpy() if y.boxes is not None else np.zeros(0)
            kp = y.keypoints.xy.cpu().numpy() if y.keypoints is not None else None
            kc = y.keypoints.conf.cpu().numpy() if y.keypoints is not None and y.keypoints.conf is not None else None
            db, dc, dk = detr_detect(detr, cv2.cvtColor(frame, cv2.COLOR_BGR2RGB), threshold=0.15)
            person = dk == DETR_PERSON
            boxes, scores, yidx = fuse(yb, yc, db[person], dc[person])
            for row in people_tracker.update(Detections(boxes, scores), frame):
                tid, i = int(row[4]), int(row[7])
                box, torso = tuple(boxes[i]), None
                if yidx[i] >= 0 and kp is not None and kc is not None:
                    box = visible_box(box, kp[yidx[i]], kc[yidx[i]])
                    torso = torso_px(kp[yidx[i]], kc[yidx[i]])
                add(f"p{tid}", "Người", GREEN, PERSON_HEIGHT, idx, box, torso)
            if animal_tracker is not None:
                animal = np.isin(dk, list(DETR_ANIMALS))
                classes = np.array([DETR_ANIMALS[k] for k in dk[animal]], dtype=np.float32)
                adets = Detections(db[animal], dc[animal], classes)
                for row in animal_tracker.update(adets, frame):
                    tid, i = int(row[4]), int(row[7])
                    c = int(adets.cls[i])
                    add(f"a{tid}", ANIMALS[c], ORANGE, ANIMAL_HEIGHT[c], idx, adets.xyxy[i])
        idx += 1
        if idx % 10 == 0:
            tick("detect", idx, total or idx, started, frame)
        if stop():
            cap.release()
            raise Cancelled()
    cap.release()
    if cached is None:
        import pickle
        frame_count = idx
        with open(cache, "wb") as fh:
            pickle.dump({"frames": frame_count, "tracks": [(t.key, t.label, t.color, t.height, t.frames, t.boxes, t.torsos)
                                                           for t in tracks.values()]}, fh)
    else:
        frame_count = cached["frames"]
        tracks = {}
        for key, label, color, height, frames, boxes, torsos in cached["tracks"]:
            tracks[key] = Track(key, label, color, height, list(frames), list(boxes), list(torsos))

    # ---- clean up the tracks with the whole video known
    min_len = max(3, int(o.min_seconds * fps))
    kept = [t for t in tracks.values() if len(t.frames) >= min_len]
    for t in kept:
        finish(t, fps, W, H, focal, max_gap=int(fps * 0.5))
    say(f"Track: {len(tracks)} thô → {len(kept)} giữ lại (bỏ track ngắn hơn {o.min_seconds}s)")
    by_frame = defaultdict(list)   # frame → [(track, i)]
    for t in kept:
        for i, f in enumerate(t.span):
            by_frame[int(f)].append((t, i))
    events = events_for(kept, fps)

    # ---- pass 2: draw and encode
    cap = cv2.VideoCapture(str(o.input))
    enc = encoder(out, o.input, W, H, fps)
    painter = Painter(scale=H / 1080 if W >= H else W / 1080)
    u = painter.scale
    started = time.monotonic()
    for idx in range(frame_count):
        ok, frame = cap.read()
        if not ok:
            break
        present = sorted(by_frame.get(idx, []), key=lambda ti: -ti[0].dist[ti[1]])   # far first
        for t, i in present:
            box, d = tuple(t.box[i]), float(t.dist[i])
            if o.snaplines:
                snapline(frame, box, t.color, d)
            if o.boxes:
                corners(frame, box, t.color, d)
        if o.cards:
            taken = []   # nearest people get the room; a card that would overlap is left out
            for t, i in reversed(present):
                card(frame, painter, tuple(t.box[i]), t.color, t.label,
                     [meters(float(t.dist[i])), kmh(float(t.speed[i])), clock((idx - t.span[0]) / fps)],
                     float(t.dist[i]), taken)

        # HUD: counter (top left), in-view list (top right), event log + watermark (bottom left).
        people = sum(1 for t, _ in present if t.is_person)
        animals: dict[str, int] = {}
        for t, _ in present:
            if not t.is_person:
                animals[t.label] = animals.get(t.label, 0) + 1
        summary = " · ".join(([f"{people} người"] if people else []) + [f"{k} {v}" for k, v in animals.items()]) \
            or "Đang quét…"
        if o.counter:
            cw, ch = painter.measure(summary, painter.bold)
            Painter.panel(frame, 16 * u, 16 * u, 16 * u + cw + 50 * u, 52 * u, radius=int(18 * u))
            cv2.circle(frame, (int(36 * u), int(34 * u)), max(int(6 * u), 3), GREEN, max(int(2 * u), 1), cv2.LINE_AA)
            painter.text((52 * u, 22 * u), summary, painter.bold)

        rows = sorted(present, key=lambda ti: ti[0].dist[ti[1]])[:8] if o.list else None
        if rows is not None:
            lw, lh = 230 * u, (34 + 22 * max(len(rows), 1)) * u
            Painter.panel(frame, W - lw - 16 * u, 16 * u, W - 16 * u, 16 * u + lh, radius=int(14 * u))
            painter.text((W - lw - 4 * u, 22 * u), "TRONG KHUNG", painter.small, (200, 200, 200))
            if not rows:
                painter.text((W - lw - 4 * u, 44 * u), "Không có ai", painter.small, (200, 200, 200))
        for r, (t, i) in enumerate(rows or []):
            y = (44 + 22 * r) * u
            cv2.circle(frame, (int(W - lw + 2 * u), int(y + 10 * u)), max(int(4 * u), 2), t.color, -1, cv2.LINE_AA)
            painter.text((W - lw + 14 * u, y), t.label, painter.bold)
            dist = meters(float(t.dist[i]))
            painter.text((W - 28 * u - painter.measure(dist)[0], y), dist)

        live = [e for e in events if 0 <= idx - e[0] < EVENT_TTL * fps][-EVENTS_SHOWN:] if o.log else []
        y = H - 24 * u - 30 * u * (len(live) + 1)
        for _, text in live:
            line = f"› {text}"
            w, _ = painter.measure(line)
            Painter.panel(frame, 16 * u, y, 16 * u + w + 24 * u, y + 26 * u, radius=int(13 * u))
            painter.text((28 * u, y + 3 * u), line)
            y += 30 * u
        if o.watermark:
            w, _ = painter.measure(o.watermark)
            Painter.panel(frame, 16 * u, H - 46 * u, 16 * u + w + 24 * u, H - 20 * u, radius=int(13 * u))
            painter.text((28 * u, H - 43 * u), o.watermark, rgb=(230, 230, 230))

        frame = painter.flush(frame)
        enc.stdin.write(frame.tobytes())
        if (idx + 1) % 5 == 0:
            tick("draw", idx + 1, frame_count, started, frame)
        if stop():
            cap.release(); enc.stdin.close(); enc.wait()
            out.unlink(missing_ok=True)
            raise Cancelled()
    cap.release()
    enc.stdin.close()
    enc.wait()
    say(f"\nXong: {out}")
    return out



def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="Video in, ESP video out (max accuracy, offline).")
    ap.add_argument("input", type=Path)
    ap.add_argument("-o", "--output", type=Path, help="default: <input>_esp.mp4")
    ap.add_argument("--model", default="yolo11x-pose.pt")
    ap.add_argument("--imgsz", type=int, default=1280, help="model input; 1536 for 4K footage with far-away people")
    ap.add_argument("--no-tta", action="store_true", help="skip test-time augmentation")
    ap.add_argument("--animals", action="store_true", help="also track animals")
    ap.add_argument("--fast", action="store_true", help="YOLO11x-pose only (≈3× faster, misses more people)")
    ap.add_argument("--detr-res", type=int, default=1280, help="RF-DETR input size")
    ap.add_argument("--fov", type=float, default=70, help="field of view along the long side of the frame, degrees "
                                                           "(iPhone 1×: ~70, 0.5×: ~105)")
    ap.add_argument("--min-seconds", type=float, default=0.4, help="drop tracks shorter than this (false positives)")
    ap.add_argument("--watermark", default="", help="text in the bottom-left corner (none by default)")
    ap.add_argument("--list", action="store_true", help="show the in-view list (top right)")
    ap.add_argument("--log", action="store_true", help="show the event log (bottom left)")
    ap.add_argument("--no-snaplines", action="store_true")
    ap.add_argument("--no-cards", action="store_true")
    ap.add_argument("--no-counter", action="store_true")
    ap.add_argument("--redetect", action="store_true", help="ignore the saved detections and run pass 1 again")
    a = ap.parse_args()
    run(Options(input=a.input, output=a.output, model=a.model, imgsz=a.imgsz, no_tta=a.no_tta, animals=a.animals,
                fast=a.fast, detr_res=a.detr_res, fov=a.fov, min_seconds=a.min_seconds, redetect=a.redetect,
                cards=not a.no_cards, snaplines=not a.no_snaplines, counter=not a.no_counter, list=a.list, log=a.log,
                watermark=a.watermark))
    print()


if __name__ == "__main__":
    main()
