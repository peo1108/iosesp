@echo off
rem ESP tren link live / video / webcam bang GPU.  Vi du:
rem   run.bat rtsp://192.168.1.10:554/stream
rem   run.bat https://www.youtube.com/watch?v=XXXX --animals
rem   run.bat 0                      (webcam)
rem   run.bat video.mp4 --record esp.mp4
cd /d "%~dp0"
".venv\Scripts\python.exe" esp_live.py %*
