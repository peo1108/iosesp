"""Scene understanding on top of the detections: metric depth, the camera's own motion, and riders on two-wheelers."""
from __future__ import annotations

import cv2
import numpy as np

DEPTH_MODEL = "depth-anything/Depth-Anything-V2-Metric-Outdoor-Large-hf"


class DepthModel:
    """Depth Anything V2 (metric, outdoor) on the GPU. Monocular metric depth is only roughly scaled for an
    arbitrary phone lens, so callers calibrate it against people's known size (`depth_scale`)."""

    def __init__(self, model_id: str = DEPTH_MODEL):
        import torch
        from transformers import AutoImageProcessor, AutoModelForDepthEstimation

        self.torch = torch
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.dtype = torch.float16 if self.device == "cuda" else torch.float32
        self.processor = AutoImageProcessor.from_pretrained(model_id)
        self.model = AutoModelForDepthEstimation.from_pretrained(model_id, torch_dtype=self.dtype).to(self.device).eval()

    def infer(self, bgr: np.ndarray) -> np.ndarray:
        """Depth in meters at the model's resolution (same aspect as the frame)."""
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        inputs = self.processor(images=rgb, return_tensors="pt").to(self.device)
        with self.torch.inference_mode():
            out = self.model(pixel_values=inputs["pixel_values"].to(self.dtype))
        return out.predicted_depth[0].float().cpu().numpy()

    @staticmethod
    def sample(depth: np.ndarray, box, frame_size) -> float:
        """Median depth over the middle of a box (centre 40% wide, 30–80% tall: the body, not the background
        around it or the ground at the feet)."""
        H, W = frame_size
        dh, dw = depth.shape
        x0, y0, x1, y1 = box
        bw, bh = x1 - x0, y1 - y0
        sx, sy = dw / W, dh / H
        a, b = int((x0 + 0.3 * bw) * sx), int((x0 + 0.7 * bw) * sx) + 1
        c, d = int((y0 + 0.3 * bh) * sy), int((y0 + 0.8 * bh) * sy) + 1
        patch = depth[max(c, 0):min(d, dh), max(a, 0):min(b, dw)]
        vals = patch[np.isfinite(patch) & (patch > 0.1)]
        return float(np.median(vals)) if vals.size else float("nan")


class CameraMotion:
    """Horizontal pan of the camera, frame to frame, from sparse optical flow on the background (people and
    vehicles masked out). `pan[i]` is the cumulative shift in pixels at frame i; subtracting it from an object's
    x keeps someone standing still at the same place while the phone turns."""

    def __init__(self, width: int):
        self.scale = 640 / max(width, 1)
        self.prev = None
        self.pan = [0.0]

    def update(self, bgr: np.ndarray, boxes) -> None:
        small = cv2.resize(bgr, None, fx=self.scale, fy=self.scale, interpolation=cv2.INTER_AREA)
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        if self.prev is None:
            self.prev = gray
            return
        mask = np.full(gray.shape, 255, np.uint8)
        for x0, y0, x1, y1 in boxes:
            cv2.rectangle(mask, (int(x0 * self.scale) - 4, int(y0 * self.scale) - 4),
                          (int(x1 * self.scale) + 4, int(y1 * self.scale) + 4), 0, -1)
        dx = 0.0
        pts = cv2.goodFeaturesToTrack(self.prev, maxCorners=400, qualityLevel=0.01, minDistance=8, mask=mask)
        if pts is not None and len(pts) >= 12:
            nxt, status, _ = cv2.calcOpticalFlowPyrLK(self.prev, gray, pts, None, winSize=(21, 21), maxLevel=3)
            good = status.reshape(-1) == 1
            if good.sum() >= 12:
                m, _ = cv2.estimateAffinePartial2D(pts[good], nxt[good], method=cv2.RANSAC, ransacReprojThreshold=2.0)
                if m is not None:
                    dx = float(m[0, 2]) / self.scale
        self.pan.append(self.pan[-1] + dx)
        self.prev = gray


def depth_scale(samples: list[tuple[float, float]]) -> float:
    """Per-video scale for the depth model from (size-based distance, raw depth) pairs of standing, uncut people:
    their average height is a good ruler; the depth model supplies the relative layout. 1 with too few samples."""
    if len(samples) < 20:
        return 1.0
    ratios = np.array([s / d for s, d in samples if d > 0.3 and np.isfinite(d)])
    if ratios.size < 20:
        return 1.0
    return float(np.clip(np.median(ratios), 0.4, 2.5))


TWO_WHEELERS = {"Xe máy", "Xe đạp"}


def riders(tracks, frame_count: int, fps: float):
    """Which people are riding which two-wheeler, per frame: {frame: {vehicle_key: [person_track, ...]}} and the set
    of (person_key, frame) to hide. A person rides a bike when their box sits over it (centre within the bike's width,
    wide horizontal overlap, feet down in the bike's lower part); decided per pair with a ±0.4 s majority vote so it
    doesn't flicker, and each person goes to the one bike they overlap most (dense traffic has bikes side by side)."""
    bikes = [t for t in tracks if t.label in TWO_WHEELERS]
    people = [t for t in tracks if t.is_person]
    riding: dict[int, dict[str, list]] = {}
    hidden: set[tuple[str, int]] = set()
    if not bikes or not people:
        return riding, hidden
    half = max(1, int(0.4 * fps))
    claims: dict[tuple[str, int], tuple[float, str, object]] = {}   # (person, frame) → best (overlap, bike, person)
    for v in bikes:
        v_at = {int(f): i for i, f in enumerate(v.span)}
        for p in people:
            common = [int(f) for f in p.span if int(f) in v_at]
            if len(common) < 3:
                continue
            p_at = {int(f): i for i, f in enumerate(p.span)}
            on, score = [], []
            for f in common:
                px0, py0, px1, py1 = p.box[p_at[f]]
                vx0, vy0, vx1, vy1 = v.box[v_at[f]]
                overlap = min(px1, vx1) - max(px0, vx0)
                vh = vy1 - vy0
                centre = (px0 + px1) / 2
                on.append(vx0 <= centre <= vx1 and overlap > 0.5 * min(px1 - px0, vx1 - vx0)
                          and vy0 + 0.3 * vh < py1 < vy1 + 0.2 * vh)
                score.append(overlap / max(px1 - px0, 1e-6))
            vote = np.convolve(np.array(on, dtype=float), np.ones(2 * half + 1) / (2 * half + 1), mode="same") > 0.5
            for f, r, sc in zip(common, vote, score):
                if r and sc > claims.get((p.key, f), (-1.0,))[0]:
                    claims[(p.key, f)] = (sc, v.key, p)
    for (pkey, f), (_, vkey, p) in claims.items():
        riding.setdefault(f, {}).setdefault(vkey, []).append(p)
        hidden.add((pkey, f))
    return riding, hidden


VEHICLE_LABELS = {"Xe máy", "Xe đạp", "Ô tô", "Xe buýt", "Xe tải"}


def dedupe_vehicles(tracks):
    """The detector sometimes calls one vehicle two things at once (a bus that is also "Xe tải"): two vehicle tracks
    of different classes overlapping most of the time are one vehicle, and the longer-lived track wins."""
    vehicles = sorted((t for t in tracks if t.label in VEHICLE_LABELS), key=lambda t: -len(t.span))
    dropped = set()
    for i, a in enumerate(vehicles):
        if a.key in dropped:
            continue
        a_at = {int(f): k for k, f in enumerate(a.span)}
        for b in vehicles[i + 1:]:
            if b.key in dropped or b.label == a.label:
                continue
            common = [(a_at[int(f)], k) for k, f in enumerate(b.span) if int(f) in a_at]
            if len(common) < 0.5 * len(b.span):
                continue
            ious = []
            for ia, ib in common:
                (ax0, ay0, ax1, ay1), (bx0, by0, bx1, by1) = a.box[ia], b.box[ib]
                inter = max(0, min(ax1, bx1) - max(ax0, bx0)) * max(0, min(ay1, by1) - max(ay0, by0))
                union = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
                ious.append(inter / max(union, 1e-6))
            if np.median(ious) > 0.6:
                dropped.add(b.key)
    return [t for t in tracks if t.key not in dropped]
