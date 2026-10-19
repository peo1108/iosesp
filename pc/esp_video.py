"""Video in, ESP video out, as accurate as the GPU can make it (offline, no real-time limit).

    python esp_video.py input.mp4 [-o output.mp4] [--no-animals] [--no-vehicles] [--fast]

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

from ensemble import (DETR_ANIMALS, DETR_PERSON, DETR_VEHICLES, Detections, detr_detect, detr_tiles, fuse, load_detr,
                      make_tracker, merge_detections)
from reid import Embedder, should_sample, stitch
from esp_live import (ANIMAL_HEIGHT, ANIMALS, BLUE, VEHICLE_HEIGHT, VEHICLES, EVENT_TTL, EVENTS_SHOWN, GREEN, ORANGE, PERSON_HEIGHT, RIDING_SPEED,
                      Painter, card, clock, corners, estimate_distance, kmh, meters, snapline, torso_px, visible_box)

from scene import CameraMotion, DepthModel, dedupe_vehicles, depth_scale, riders

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
    depths: list = field(default_factory=list)   # raw depth-model meters per observation (nan when not sampled)
    embeds: list = field(default_factory=list)   # appearance embeddings of a few crops (re-identification)
    embed_frames: list = field(default_factory=list)
    returns: list = field(default_factory=list)  # frames where a re-identified track came back
    ghost: np.ndarray | None = None              # per `span` frame: position inferred (hidden or just gone)
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


def finish(track: Track, fps: float, W: int, H: int, focal: float, max_gap: int, pan: np.ndarray | None = None,
           scale: float = 1.0, frame_count: int | None = None):
    """Fill gaps up to `max_gap` frames by interpolation (when the jump across is plausible), split at longer ones,
    coast a little past a disappearance in mid-frame, smooth, compute distance (depth model × `scale` when sampled,
    else body size) and speed (positions with the camera's `pan` taken out). Frames not actually seen for more than a
    blink are marked `ghost`."""
    frames = np.array(track.frames)
    boxes = np.array(track.boxes, dtype=np.float64)
    torsos = np.array([t if t else np.nan for t in track.torsos], dtype=np.float64)
    raw_depth = np.array(track.depths if len(track.depths) == len(track.frames) else [np.nan] * len(frames),
                         dtype=np.float64) * scale

    size = max(W, H)
    blink = max(2, int(0.4 * fps))   # shorter misses are detector blinks (blur, night): drawn normally
    span, box, torso, depth, ghost = [], [], [], [], []
    for i in range(len(frames)):
        if i and 1 < frames[i] - frames[i - 1] <= max_gap:
            a, b = frames[i - 1], frames[i]
            ca, cb = (boxes[i - 1, :2] + boxes[i - 1, 2:]) / 2, (boxes[i, :2] + boxes[i, 2:]) / 2
            width = max(boxes[i - 1, 2] - boxes[i - 1, 0], boxes[i, 2] - boxes[i, 0])
            if np.hypot(*(cb - ca)) <= max(3 * width, 0.35 * size):   # hidden behind something, not teleported
                for f in range(a + 1, b):
                    t = (f - a) / (b - a)
                    span.append(f)
                    box.append(boxes[i - 1] * (1 - t) + boxes[i] * t)
                    torso.append(np.nan)
                    depth.append(np.nan)
                    ghost.append(b - a > blink)
        span.append(frames[i])
        box.append(boxes[i])
        torso.append(torsos[i])
        depth.append(raw_depth[i])
        ghost.append(False)

    # Vanished in mid-frame (behind a bus…) rather than off an edge: carry on along the last motion for 0.3 s.
    last = boxes[-1]
    edge = 0.03 * W
    if len(frames) >= 3 and last[0] > edge and last[2] < W - edge and last[3] < H - 0.03 * H:
        recent = frames >= frames[-1] - 0.5 * fps
        c = (boxes[recent, :2] + boxes[recent, 2:]) / 2
        dt = (frames[recent][-1] - frames[recent][0]) or 1
        step = (c[-1] - c[0]) / dt
        for k in range(1, int(0.3 * fps) + 1):
            f = frames[-1] + k
            moved = last + np.tile(step * k, 2)
            if (frame_count is not None and f >= frame_count) or moved[2] < 0 or moved[0] > W:
                break
            span.append(f); box.append(moved); torso.append(np.nan); depth.append(np.nan); ghost.append(True)
    span, box, torso, depth = np.array(span), np.array(box), np.array(torso), np.array(depth)
    track.ghost = np.array(ghost, dtype=bool)

    # Smooth within each contiguous run separately (a long gap is a real exit and re-entry).
    breaks = np.where(np.diff(span) > 1)[0] + 1
    smoothed = [gaussian_smooth(part, sigma=1.2) for part in np.split(box, breaks)]
    box = np.concatenate(smoothed)

    dist = np.array([estimate_distance(tuple(b), track.height, focal, H, None if np.isnan(t) else t)
                     for b, t in zip(box, torso)])
    measured = np.isfinite(depth)
    track.measured = bool(measured.mean() > 0.3)
    if measured.sum() >= 2:
        # Depth is sampled every few frames: fill the rest by interpolation, then prefer it over the size guess.
        idx = np.arange(len(span))
        dist = np.interp(idx, idx[measured], depth[measured])
    log_d = np.concatenate([gaussian_smooth(part, sigma=fps * 0.25) for part in np.split(np.log(dist), breaks)])
    dist = np.exp(log_d)

    cx = (box[:, 0] + box[:, 2]) / 2
    if pan is not None and len(pan):
        cx = cx - pan[np.clip(span, 0, len(pan) - 1)]   # where it is in the scene, not on the turning screen
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
        for gap in np.where(np.diff(t.span) > 1)[0]:
            raw.append([int(t.span[gap]) + int(fps), f"{t.label} rời khung hình"])
            raw.append([int(t.span[gap + 1]), f"{t.label} quay lại khung hình"])
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
    animals: bool = True
    vehicles: bool = True
    fast: bool = False
    detr_res: int = 1280
    fov: float = 70
    min_seconds: float = 0.4
    depth: bool = True          # metric distances from Depth Anything V2
    depth_every: int = 2        # run the depth model on every Nth frame
    tiles: bool = True          # also detect on a 2×2 grid of zoomed tiles (far, small people and vehicles)
    reid: bool = True           # join tracks of the same person/vehicle seen again later
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
                                                     f"{'-animals' if o.animals else ''}{'-vehicles' if o.vehicles else ''}{'-depth' if o.depth else ''}{'-tiles' if o.tiles else ''}-v3.pkl")
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

    new_this_frame: list[tuple[Track, int]] = []

    def add(key, label, color, height, idx, box, torso=None):
        t = tracks.setdefault(key, Track(key, label, color, height))
        t.frames.append(idx); t.boxes.append(tuple(box)); t.torsos.append(torso); t.depths.append(float("nan"))
        new_this_frame.append((t, len(t.frames) - 1))

    motion = CameraMotion(W)
    embedder = Embedder() if cached is None else None
    depth_model = None
    if cached is None and o.depth:
        say("Đang tải model độ sâu (Depth Anything V2)…")
        depth_model = DepthModel()

    if cached is not None:
        pass   # detections loaded from the cache: no models needed
    elif o.fast:
        thing_classes = (list(ANIMALS) if o.animals else []) + (list(VEHICLES) if o.vehicles else [])
        animal_model = YOLO("yolo11x.pt") if thing_classes else None
        tracker = str(HERE / "botsort_esp.yaml")
    else:
        # Ensemble: RF-DETR Large (+ mirror) and YOLO11x-pose (+ TTA), fused, tracked by our own BoT-SORT.
        detr, detr_res = load_detr(o.detr_res)
        say(f"Chế độ siêu chính xác: RF-DETR Large {detr_res}px + YOLO11x-pose {o.imgsz}px")
        people_tracker = make_tracker(HERE / "botsort_esp.yaml", fps)
        animal_tracker = make_tracker(HERE / "botsort_esp.yaml", fps) if o.animals else None
        vehicle_tracker = make_tracker(HERE / "botsort_esp.yaml", fps) if o.vehicles else None

    started, idx = time.monotonic(), 0
    while cached is None:
        ok, frame = cap.read()
        if not ok:
            break
        new_this_frame.clear()
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
                                          quantize=quant, device=device, classes=thing_classes, conf=0.25, verbose=False)[0]
                if ares.boxes is not None and ares.boxes.id is not None:
                    for box, tid, cls in zip(ares.boxes.xyxy.cpu().numpy(), ares.boxes.id.int().cpu().numpy(),
                                             ares.boxes.cls.int().cpu().numpy()):
                        c = int(cls)
                        if c in VEHICLES:
                            add(f"v{tid}", VEHICLES[c], BLUE, VEHICLE_HEIGHT[c], idx, box)
                        else:
                            add(f"a{tid}", ANIMALS[c], ORANGE, ANIMAL_HEIGHT[c], idx, box)
        else:
            y = people_model.predict(frame, imgsz=o.imgsz, augment=tta_people, quantize=quant, device=device,
                                     classes=[0], conf=0.1, iou=0.6, verbose=False)[0]
            yb = y.boxes.xyxy.cpu().numpy() if y.boxes is not None else np.zeros((0, 4))
            yc = y.boxes.conf.cpu().numpy() if y.boxes is not None else np.zeros(0)
            kp = y.keypoints.xy.cpu().numpy() if y.keypoints is not None else None
            kc = y.keypoints.conf.cpu().numpy() if y.keypoints is not None and y.keypoints.conf is not None else None
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            db, dc, dk = detr_detect(detr, rgb, threshold=0.15)
            if o.tiles:
                db, dc, dk = merge_detections((db, dc, dk), detr_tiles(detr, rgb, threshold=0.2))
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
            if vehicle_tracker is not None:
                vehicle = np.isin(dk, list(DETR_VEHICLES))
                vclasses = np.array([DETR_VEHICLES[k] for k in dk[vehicle]], dtype=np.float32)
                vdets = Detections(db[vehicle], dc[vehicle], vclasses)
                for row in vehicle_tracker.update(vdets, frame):
                    tid, i = int(row[4]), int(row[7])
                    c = int(vdets.cls[i])
                    add(f"v{tid}", VEHICLES[c], BLUE, VEHICLE_HEIGHT[c], idx, vdets.xyxy[i])
        motion.update(frame, [t.boxes[j] for t, j in new_this_frame])
        due = [(t, j) for t, j in new_this_frame if should_sample(t, idx, fps, t.boxes[j])]
        if due and embedder is not None:
            for (t, j), e in zip(due, embedder.embed(frame, [t.boxes[j] for t, j in due])):
                t.embeds.append(e.astype(np.float16)); t.embed_frames.append(idx)
        if depth_model is not None and new_this_frame and idx % max(o.depth_every, 1) == 0:
            dmap = depth_model.infer(frame)
            for t, j in new_this_frame:
                t.depths[j] = DepthModel.sample(dmap, t.boxes[j], (H, W))
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
            pickle.dump({"frames": frame_count, "pan": motion.pan,
                         "tracks": [(t.key, t.label, t.color, t.height, t.frames, t.boxes, t.torsos, t.depths,
                                     t.embeds, t.embed_frames) for t in tracks.values()]}, fh)
        pan = np.array(motion.pan)
    else:
        frame_count = cached["frames"]
        pan = np.array(cached.get("pan", []))
        tracks = {}
        for key, label, color, height, frames, boxes, torsos, depths, embeds, embed_frames in cached["tracks"]:
            tracks[key] = Track(key, label, color, height, list(frames), list(boxes), list(torsos), list(depths),
                                list(embeds), list(embed_frames))

    # ---- clean up the tracks with the whole video known
    if o.reid:
        tracks, joins = stitch(tracks, fps, W, H)
        say(f"Nhận lại: nối {joins} đoạn của cùng một người/xe")
    min_len = max(3, int(o.min_seconds * fps))
    kept = [t for t in tracks.values() if len(t.frames) >= min_len]
    # Calibrate the depth model's scale on standing, uncut people (their height is the ruler).
    samples = []
    for t in kept:
        if not t.is_person:
            continue
        for box, d in zip(t.boxes, t.depths):
            x0, y0, x1, y1 = box
            if np.isfinite(d) and y0 > 0.02 * H and y1 < 0.98 * H and (y1 - y0) > 1.8 * (x1 - x0):
                samples.append((estimate_distance(box, PERSON_HEIGHT, focal, H), d))
    scale = depth_scale(samples)
    if o.depth:
        say(f"Hiệu chỉnh độ sâu: ×{scale:.2f} ({len(samples)} mẫu)")
    for t in kept:
        finish(t, fps, W, H, focal, max_gap=int(fps * 2.5), pan=pan, scale=scale, frame_count=frame_count)
    kept = dedupe_vehicles(kept)
    riding, hidden = riders(kept, frame_count, fps)
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
        everyone = by_frame.get(idx, [])
        on_bikes = riding.get(idx, {})
        present = sorted([(t, i) for t, i in everyone if (t.key, idx) not in hidden],
                         key=lambda ti: -ti[0].dist[ti[1]])   # far first

        def shown_box(t, i):
            """A bike's box grows over its riders."""
            box = t.box[i]
            for p in on_bikes.get(t.key, []):
                j = int(np.searchsorted(p.span, idx))
                pb = p.box[j]
                box = np.array([min(box[0], pb[0]), min(box[1], pb[1]), max(box[2], pb[2]), max(box[3], pb[3])])
            return tuple(box)

        def title(t, i):
            n = len(on_bikes.get(t.key, []))
            name = f"{t.label} · {n} người" if n else t.label
            return name + " · bị che" if t.ghost[i] else name
        for t, i in present:
            box, d = shown_box(t, i), float(t.dist[i])
            if o.snaplines:
                snapline(frame, box, t.color, d, ghost=bool(t.ghost[i]))
            if o.boxes:
                corners(frame, box, t.color, d, ghost=bool(t.ghost[i]))
        if o.cards:
            taken = []   # nearest people get the room; a card that would overlap is left out
            for t, i in reversed(present):
                card(frame, painter, shown_box(t, i), t.color, title(t, i),
                     [meters(float(t.dist[i]), approx=not getattr(t, "measured", False)), kmh(float(t.speed[i])),
                      clock(i / fps)],   # time actually in view: keeps counting where it left off
                     float(t.dist[i]), taken)

        # HUD: counter (top left), in-view list (top right), event log + watermark (bottom left).
        people = sum(1 for t, _ in everyone if t.is_person)   # riders still count as people
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
            dist = meters(float(t.dist[i]), approx=not getattr(t, "measured", False))
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
    ap.add_argument("--no-animals", action="store_true", help="don't track animals")
    ap.add_argument("--no-vehicles", action="store_true", help="don't track vehicles")
    ap.add_argument("--no-depth", action="store_true", help="guess distances from body size instead of the depth model")
    ap.add_argument("--no-tiles", action="store_true", help="skip the zoomed-tile pass for far, small objects")
    ap.add_argument("--no-reid", action="store_true", help="don't join tracks of someone who comes back")
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
    run(Options(input=a.input, output=a.output, model=a.model, imgsz=a.imgsz, no_tta=a.no_tta, animals=not a.no_animals, vehicles=not a.no_vehicles, depth=not a.no_depth, tiles=not a.no_tiles, reid=not a.no_reid,
                fast=a.fast, detr_res=a.detr_res, fov=a.fov, min_seconds=a.min_seconds, redetect=a.redetect,
                cards=not a.no_cards, snaplines=not a.no_snaplines, counter=not a.no_counter, list=a.list, log=a.log,
                watermark=a.watermark))
    print()


if __name__ == "__main__":
    main()
