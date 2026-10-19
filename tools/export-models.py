"""Exports YOLO11m-pose and YOLO11m to CoreML (640x480, the models' 4:3 input) and compiles them into
App/Models/pose.mlmodelc and App/Models/objects.mlmodelc. Runs on the macOS CI runner (needs
`xcrun coremlcompiler`). The app loads the models by those stable names, so changing size here is enough.

Ultralytics models are AGPL-3.0: fine for this personal app, not for redistribution.
"""
import os
import pathlib
import shutil
import subprocess

from ultralytics import YOLO

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "models"
OUT = ROOT / "App" / "Models"
# "m": the most accurate size that still runs in real time on the Neural Engine.
SIZE = "m"

WORK.mkdir(parents=True, exist_ok=True)
if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir(parents=True)
os.chdir(WORK)  # weights download next to the exports

for weights, nms, stable in ((f"yolo11{SIZE}-pose", False, "pose"), (f"yolo11{SIZE}", True, "objects")):
    exported = pathlib.Path(YOLO(f"{weights}.pt").export(format="coreml", imgsz=(480, 640), half=True, nms=nms))
    print(f"exported {exported}")
    subprocess.run(["xcrun", "coremlcompiler", "compile", str(exported), str(WORK)], check=True)
    (WORK / f"{exported.stem}.mlmodelc").rename(OUT / f"{stable}.mlmodelc")

for compiled in sorted(OUT.iterdir()):
    print(f"compiled {compiled.name}")
