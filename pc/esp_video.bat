@echo off
rem Keo tha 1 hoac nhieu video vao file nay. Video ESP ra canh video goc: <ten>_esp.mp4
rem Muon them con vat: them  --animals  vao sau %%f o dong python ben duoi.
set PYTHONUTF8=1
set "ESP=C:\Users\cam\Desktop\ESPNGH~1\pc"
if "%~1"=="" (
  echo Keo video tha vao file nay de xuat video ESP.
  pause
  exit /b
)
for %%f in (%*) do (
  "%ESP%\.venv\Scripts\python.exe" "%ESP%\esp_video.py" %%f
)
pause