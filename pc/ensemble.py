"""Two detectors, one set of people: RF-DETR Large (transformer, strong on crowds and half-hidden people) and
YOLO11x-pose (keypoints), merged box by box, then tracked by BoT-SORT outside Ultralytics' own predictor."""
from __future__ import annotations

from pathlib import Path

import numpy as np


def iou_matrix(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Pairwise IoU of xyxy boxes, shape (len(a), len(b))."""
    if len(a) == 0 or len(b) == 0:
        return np.zeros((len(a), len(b)))
    x0 = np.maximum(a[:, None, 0], b[None, :, 0])
    y0 = np.maximum(a[:, None, 1], b[None, :, 1])
    x1 = np.minimum(a[:, None, 2], b[None, :, 2])
    y1 = np.minimum(a[:, None, 3], b[None, :, 3])
    inter = np.clip(x1 - x0, 0, None) * np.clip(y1 - y0, 0, None)
    area_a = (a[:, 2] - a[:, 0]) * (a[:, 3] - a[:, 1])
    area_b = (b[:, 2] - b[:, 0]) * (b[:, 3] - b[:, 1])
    return inter / np.maximum(area_a[:, None] + area_b[None, :] - inter, 1e-9)


def fuse(yolo_boxes, yolo_conf, detr_boxes, detr_conf, match_iou=0.55, solo_penalty=0.85):
    """Weighted box fusion of two models' person boxes.

    A person both models see gets the confidence-weighted average box and the higher score; a person only one
    model sees is kept (that's the point of two models) with its score × `solo_penalty`, so the tracker leans on
    agreement. Returns (boxes, scores, yolo_index) where yolo_index points at the YOLO detection in the pair
    (for its keypoints) or is -1.
    """
    yolo_boxes = np.asarray(yolo_boxes, np.float64).reshape(-1, 4)
    detr_boxes = np.asarray(detr_boxes, np.float64).reshape(-1, 4)
    yolo_conf, detr_conf = np.asarray(yolo_conf, np.float64), np.asarray(detr_conf, np.float64)
    iou = iou_matrix(yolo_boxes, detr_boxes)
    pairs = sorted(((iou[i, j], i, j) for i in range(len(yolo_boxes)) for j in range(len(detr_boxes))
                    if iou[i, j] >= match_iou), reverse=True)
    used_y, used_d = set(), set()
    boxes, scores, index = [], [], []
    for _, i, j in pairs:
        if i in used_y or j in used_d:
            continue
        used_y.add(i), used_d.add(j)
        w = np.array([yolo_conf[i], detr_conf[j]])
        boxes.append((yolo_boxes[i] * w[0] + detr_boxes[j] * w[1]) / w.sum())
        scores.append(max(w))
        index.append(i)
    for i in range(len(yolo_boxes)):
        if i not in used_y:
            boxes.append(yolo_boxes[i]); scores.append(yolo_conf[i] * solo_penalty); index.append(i)
    for j in range(len(detr_boxes)):
        if j not in used_d:
            boxes.append(detr_boxes[j]); scores.append(detr_conf[j] * solo_penalty); index.append(-1)
    return np.array(boxes).reshape(-1, 4), np.array(scores), np.array(index, dtype=int)


class Detections:
    """The minimal results object Ultralytics' trackers read: numpy conf/cls/xyxy/xywh with boolean indexing."""

    def __init__(self, xyxy, conf, cls=None):
        self.xyxy = np.asarray(xyxy, np.float32).reshape(-1, 4)
        self.conf = np.asarray(conf, np.float32).reshape(-1)
        self.cls = np.zeros(len(self.conf), np.float32) if cls is None else np.asarray(cls, np.float32).reshape(-1)

    @property
    def xywh(self):
        x0, y0, x1, y1 = self.xyxy.T
        return np.stack([(x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0], axis=1)

    def __len__(self):
        return len(self.conf)

    def __getitem__(self, mask):
        return Detections(self.xyxy[mask], self.conf[mask], self.cls[mask])


def make_tracker(config: Path, frame_rate: float):
    """BoT-SORT from our yaml; ReID through a small classification model (the fused boxes have no detector features)."""
    from ultralytics.trackers.bot_sort import BOTSORT
    from ultralytics.utils import YAML, IterableSimpleNamespace

    cfg = YAML.load(str(config))
    if cfg.get("with_reid") and cfg.get("model", "auto") == "auto":
        cfg["model"] = "yolo11s-cls.pt"
    cfg["track_buffer"] = int(round(cfg["track_buffer"] * frame_rate / 30))
    return BOTSORT(args=IterableSimpleNamespace(**cfg))


def load_detr(resolution: int):
    """RF-DETR Large at `resolution` (rounded to a multiple of 32), FP16-optimized on the GPU."""
    import torch
    from rfdetr import RFDETRLarge

    resolution = max(320, int(round(resolution / 32)) * 32)
    model = RFDETRLarge(resolution=resolution)
    if torch.cuda.is_available():
        try:
            model.inference(dtype=torch.float16)
        except Exception as e:  # optional speed-up; plain inference still works
            print(f"(RF-DETR chạy không tối ưu: {e})")
    return model, resolution


# RF-DETR returns COCO category ids: person 1, animals 16 (bird) … 25 (giraffe). Ultralytics' index is id − 2.
DETR_PERSON = 1
DETR_ANIMALS = {coco_id: coco_id - 2 for coco_id in range(16, 26)}
# Bicycle 2, car 3, motorcycle 4, bus 6, truck 8 (below the first gap in COCO ids, so index = id − 1).
DETR_VEHICLES = {2: 1, 3: 2, 4: 3, 6: 5, 8: 7}


def detr_detect(model, rgb: np.ndarray, threshold: float):
    """RF-DETR on the frame and its mirror image, merged (flip TTA). Returns xyxy, scores, COCO class ids."""
    from PIL import Image

    w = rgb.shape[1]
    out = []
    for flip in (False, True):
        img = rgb[:, ::-1] if flip else rgb
        d = model.predict(Image.fromarray(np.ascontiguousarray(img)), threshold=threshold)
        xyxy = np.asarray(d.xyxy, np.float64).reshape(-1, 4)
        if flip:
            xyxy = np.stack([w - xyxy[:, 2], xyxy[:, 1], w - xyxy[:, 0], xyxy[:, 3]], axis=1)
        out.append((xyxy, np.asarray(d.confidence, np.float64), np.asarray(d.class_id, int)))
    boxes, scores, classes = [], [], []
    for cls in set(out[0][2].tolist()) | set(out[1][2].tolist()):
        (a, ca, ka), (b, cb, kb) = out
        fa, fb = ka == cls, kb == cls
        fused, conf, idx = fuse(a[fa], ca[fa], b[fb], cb[fb], solo_penalty=0.9)
        boxes.append(fused); scores.append(conf); classes.append(np.full(len(conf), cls))
    if not boxes:
        return np.zeros((0, 4)), np.zeros(0), np.zeros(0, int)
    return np.concatenate(boxes), np.concatenate(scores), np.concatenate(classes)


def nms(boxes: np.ndarray, scores: np.ndarray, iou: float = 0.5) -> np.ndarray:
    """Indices kept by greedy non-maximum suppression, best first."""
    order = np.argsort(-scores)
    keep = []
    while order.size:
        i = order[0]
        keep.append(i)
        if order.size == 1:
            break
        rest = order[1:]
        order = rest[iou_matrix(boxes[i:i + 1], boxes[rest])[0] < iou]
    return np.array(keep, dtype=int)


def detr_tiles(model, rgb: np.ndarray, threshold: float, grid: int = 2, overlap: float = 0.25):
    """RF-DETR on a grid × grid of overlapping tiles, each blown up to the model's input, for people and vehicles
    only a few dozen pixels tall. Keeps only small detections (big ones are the full-frame pass's job) that don't
    touch an inner tile edge (the overlapping neighbour sees those whole), merged across tiles."""
    from PIL import Image

    H, W = rgb.shape[:2]
    tw, th = int(W / (grid - (grid - 1) * overlap)), int(H / (grid - (grid - 1) * overlap))
    xs = np.linspace(0, W - tw, grid).astype(int)
    ys = np.linspace(0, H - th, grid).astype(int)
    boxes, scores, classes = [], [], []
    for y in ys:
        for x in xs:
            d = model.predict(Image.fromarray(np.ascontiguousarray(rgb[y:y + th, x:x + tw])), threshold=threshold)
            b = np.asarray(d.xyxy, np.float64).reshape(-1, 4)
            if not len(b):
                continue
            edge = 3
            inner = ((b[:, 0] < edge) & (x > 0)) | ((b[:, 2] > tw - edge) & (x + tw < W)) \
                | ((b[:, 1] < edge) & (y > 0)) | ((b[:, 3] > th - edge) & (y + th < H))
            small = (b[:, 3] - b[:, 1]) < 0.5 * th
            ok = small & ~inner
            boxes.append(b[ok] + [x, y, x, y])
            scores.append(np.asarray(d.confidence, np.float64)[ok])
            classes.append(np.asarray(d.class_id, int)[ok])
    if not boxes:
        return np.zeros((0, 4)), np.zeros(0), np.zeros(0, int)
    boxes, scores, classes = np.concatenate(boxes), np.concatenate(scores), np.concatenate(classes)
    keep = np.concatenate([np.flatnonzero(classes == c)[nms(boxes[classes == c], scores[classes == c])]
                           for c in np.unique(classes)]) if len(classes) else np.zeros(0, int)
    return boxes[keep], scores[keep], classes[keep]


def merge_detections(full, extra, match_iou: float = 0.5, extra_penalty: float = 0.9):
    """Class-wise merge of the full-frame detections with extra ones (the tiles): a pair becomes one confidence-
    weighted box; full-frame-only boxes keep their score; extra-only boxes (the far, small finds) get
    `extra_penalty` so the tracker leans on boxes both passes agree on."""
    (fb, fc, fk), (eb, ec, ek) = full, extra
    boxes, scores, classes = [], [], []
    for cls in set(fk.tolist()) | set(ek.tolist()):
        a, ca = fb[fk == cls], fc[fk == cls]
        b, cb = eb[ek == cls], ec[ek == cls]
        iou = iou_matrix(a, b)
        used_a, used_b = set(), set()
        for _, i, j in sorted(((iou[i, j], i, j) for i in range(len(a)) for j in range(len(b))
                               if iou[i, j] >= match_iou), reverse=True):
            if i in used_a or j in used_b:
                continue
            used_a.add(i), used_b.add(j)
            w = np.array([ca[i], cb[j]])
            boxes.append((a[i] * w[0] + b[j] * w[1]) / w.sum()); scores.append(w.max()); classes.append(cls)
        for i in range(len(a)):
            if i not in used_a:
                boxes.append(a[i]); scores.append(ca[i]); classes.append(cls)
        for j in range(len(b)):
            if j not in used_b:
                boxes.append(b[j]); scores.append(cb[j] * extra_penalty); classes.append(cls)
    if not boxes:
        return np.zeros((0, 4)), np.zeros(0), np.zeros(0, int)
    return np.array(boxes).reshape(-1, 4), np.array(scores), np.array(classes, dtype=int)
