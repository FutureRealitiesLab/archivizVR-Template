@echo off
:: ============================================================
:: build_quest.bat  -  Force-Clean-Build fuer Meta Quest
:: Ausfuehren VOR dem Godot-Export (Doppelklick oder CMD)
:: ============================================================

echo === ArchViz VR - Force-Clean Quest Build ===
echo.

:: Gradle-Daemon hart beenden (taskkill ist zuverlaessiger als --stop)
echo [1/3] Beende Gradle-Daemon (Java-Prozesse)...
taskkill /F /IM java.exe 2>nul
if %errorlevel%==0 (
    echo   Java-Prozesse beendet.
) else (
    echo   Kein Java-Prozess gefunden (ok).
)
echo.

:: Gradle-Cache und Build-Output loeschen
echo [2/3] Loesche Cache und Build-Output...
if exist "android\build\.gradle" (
    rmdir /s /q "android\build\.gradle"
    echo   .gradle geloescht
)
if exist "android\build\build" (
    rmdir /s /q "android\build\build"
    echo   build\ geloescht
)
echo.

:: Hinweis: Godot-Export manuell aus dem Editor starten
echo [3/3] Fertig! Jetzt im Godot Editor exportieren:
echo   Project ^> Export ^> Android (Meta Quest) ^> Export Project
echo.
echo APK installieren:
echo   adb install -r export\archviz_vr.apk
echo.
pause
