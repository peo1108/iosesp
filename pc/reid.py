"""Re-identification: the same person or vehicle leaving and coming back (or hidden too long for the tracker) is
joined back into one track, so their clock keeps running and they aren't counted twice.

During detection a few crops of every track are turned into appearance embeddings (DINOv2); after the whole video
is known, tracks that never overlap in time are stitched when they look alike (and, for short gaps, when the newcomer
appears near where the other vanished)."""
from __future__ import annotations

import cv2
import numpy as np

EMBED_MODEL = "facebook/dinov2-small"


class Embedder:
    """DINOv2-small CLS features of box crops, L2-normalised. Fast (batched, FP16)."""

    def __init__(self, model_id: str = EMBED_MODEL):
        import torch
        from transformers import AutoImageProcessor, AutoModel

        self.torch = torch
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.dtype = torch.float16 if self.device == "cuda" else torch.float32
        self.processor = AutoImageProcessor.from_pretrained(model_id)
        self.model = AutoModel.from_pretrained(model_id, torch_dtype=self.dtype).to(self.device).eval()

    def embed(self, bgr: np.ndarray, boxes) -> list[np.ndarray]:
        crops = []
        H, W = bgr.shape[:2]
        for x0, y0, x1, y1 in boxes:
            x0, y0, x1, y1 = max(int(x0), 0), max(int(y0), 0), min(int(x1), W), min(int(y1), H)
            crop = bgr[y0:y1, x0:x1]
            crops.append(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB) if crop.size else np.zeros((8, 8, 3), np.uint8))
        if not crops:
            return []
        inputs = self.processor(images=crops, return_tensors="pt").to(self.device)
        with self.torch.inference_mode():
            out = self.model(pixel_values=inputs["pixel_values"].to(self.dtype))
        feats = out.last_hidden_state[:, 0].float()
        feats = feats / feats.norm(dim=1, keepdim=True).clamp_min(1e-6)
        return [f for f in feats.cpu().numpy()]


def should_sample(track, frame: int, fps: float, box, max_samples: int = 8) -> bool:
    """A crop every ~0.7 s, up to `max_samples` per track, only from boxes big enough to show anything."""
    x0, y0, x1, y1 = box
    if (x1 - x0) < 24 or (y1 - y0) < 40 or len(track.embeds) >= max_samples:
        return False
    return not track.embed_frames or frame - track.embed_frames[-1] >= 0.7 * fps


def stitch(tracks: dict, fps: float, W: int, H: int, near_gap_s: float = 2.0, max_gap_s: float = 120.0):
    """Joins tracks of the same kind that are one object seen twice; candidates never overlap in time.

    Appearance alone is weak here (at night, every motorbike looks alike to a general-purpose embedding: two random
    tracks already score ~0.66, the top 10% of pairs >0.8), so:
    - a short gap (≤ `near_gap_s`, a missed detection or brief occlusion) also needs the newcomer to start where the
      old track's last motion says it should be, and above-typical similarity;
    - a long gap (left the frame and came back) needs similarity in this video's top 0.5% and ≥ 0.9, a clear margin
      over the next-best candidate, and a few samples on both sides.
    Greedy by similarity, chains allowed. Returns the merged dict and the number of joins."""
    items = [t for t in tracks.values() if t.embeds and t.frames]
    mean = {t.key: _unit(np.mean(np.asarray(t.embeds, np.float32), axis=0)) for t in items}
    size = max(W, H)
    near, far = [], []
    for a in items:
        a_end, fr = a.frames[-1], np.array(a.frames)
        boxes = np.array(a.boxes, np.float64)
        recent = fr >= a_end - 0.5 * fps
        centres = (boxes[recent, :2] + boxes[recent, 2:]) / 2
        span_s = (fr[recent][-1] - fr[recent][0]) / fps
        velocity = (centres[-1] - centres[0]) / span_s if span_s > 0 else np.zeros(2)
        width = boxes[-1, 2] - boxes[-1, 0]
        for b in items:
            if a is b or a.label != b.label or b.frames[0] <= a_end:
                continue
            gap = (b.frames[0] - a_end) / fps
            if gap > max_gap_s:
                continue
            sim = float(mean[a.key] @ mean[b.key])
            if gap <= near_gap_s:
                start = (np.array(b.boxes[0][:2]) + np.array(b.boxes[0][2:])) / 2
                miss = np.hypot(*(centres[-1] + velocity * gap - start))
                if miss <= max(1.5 * width, 0.08 * size):
                    near.append((sim, a.key, b.key))
            elif len(a.embeds) >= 3 and len(b.embeds) >= 3:
                far.append((sim, a.key, b.key))

    def typical(pairs, q):
        return float(np.quantile([p[0] for p in pairs], q)) if len(pairs) >= 20 else 0.0

    pairs = [p for p in near if p[0] >= max(0.78, typical(near, 0.5))]
    far_bar = max(0.9, typical(far, 0.995))
    best = {}
    for sim, a, b in far:
        best.setdefault(b, []).append(sim)
    for sim, a, b in far:
        others = sorted(best[b], reverse=True)
        runner_up = others[1] if len(others) > 1 else 0.0
        if sim >= far_bar and sim == others[0] and sim - runner_up >= 0.04:
            pairs.append((sim, a, b))

    # Greedy: each track may continue into one later track and be continued from one earlier track.
    next_of, prev_of = {}, {}
    for sim, a, b in sorted(pairs, reverse=True):
        if a in next_of or b in prev_of:
            continue
        next_of[a], prev_of[b] = b, a

    merged = dict(tracks)
    joins = 0
    for head in [k for k in next_of if k not in prev_of]:
        root = merged[head]
        k = next_of.get(head)
        while k is not None:
            t = merged.pop(k)
            root.returns.append(t.frames[0])
            for name in ("frames", "boxes", "torsos", "depths"):
                getattr(root, name).extend(getattr(t, name))
            root.embeds.extend(t.embeds)
            root.embed_frames.extend(t.embed_frames)
            joins += 1
            k = next_of.get(k)
    return merged, joins


def _unit(v):
    return v / max(np.linalg.norm(v), 1e-6)
