"""Exports YOLO11n-pose and YOLO11n to CoreML (640x480, the camera's 4:3) and compiles them into
App/Models/*.mlmodelc. Runs on the macOS CI runner (needs `xcrun coremlcompiler`).

Ultralytics models are AGPL-3.0: fine for this personal app, not for redistribution.
"""
import os
import pathlib
import subprocess

from ultralytics import YOLO

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "models"
OUT = ROOT / "App" / "Models"

WORK.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
os.chdir(WORK)  # weights download next to the exports

for name, nms in (("yolo11n-pose", False), ("yolo11n", True)):
    exported = YOLO(f"{name}.pt").export(format="coreml", imgsz=(480, 640), half=True, nms=nms)
    print(f"exported {exported}")
    subprocess.run(["xcrun", "coremlcompiler", "compile", str(exported), str(OUT)], check=True)

for compiled in sorted(OUT.iterdir()):
    print(f"compiled {compiled.name}")
