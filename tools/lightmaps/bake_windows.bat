@echo off
rem Cuisson LightmapGI sur un poste Windows avec GPU (refonte P1/P4) : même procédure que bake.sh.
rem Usage : tools\lightmaps\bake_windows.bat C:\chemin\Godot_v4.6.3-stable_win64.exe [res://…_bake.tscn,…]
rem   1. Cloner le dépôt (git lfs pull), ouvrir une invite dans sa racine.
rem   2. Lancer ce script : il active le greffon tools\lightmaps\addon le temps de la cuisson, ouvre l'éditeur (Vulkan),
rem      cuit chaque scène (bouton « Bake Lightmaps ») et l'enregistre, puis restaure project.godot.
rem   3. Vérifier assets\lightmaps\<id>\*.exr et *.lmbake (taille > 1 Ko), lancer tests\audit\p1_shots.gd, committer.
rem Durée indicative avec un GPU dédié : quelques minutes par scène.
setlocal
set "G=%~1"
if "%G%"=="" ( echo Usage : %~nx0 chemin\vers\godot.exe [scenes] & exit /b 1 )
cd /d "%~dp0\..\.."
set "SCENES=%~2"
if "%SCENES%"=="" set "SCENES=res://assets/lightmaps/angers_ralliement/angers_ralliement_bake.tscn,res://assets/lightmaps/nantes_tremie_l3/nantes_tremie_l3_bake.tscn"
if not exist addons\tramsim_lightmap_bake mkdir addons\tramsim_lightmap_bake
copy /y tools\lightmaps\addon\plugin.cfg addons\tramsim_lightmap_bake\ >nul
copy /y tools\lightmaps\addon\plugin.gd addons\tramsim_lightmap_bake\ >nul
copy /y project.godot project.godot.bak >nul
>>project.godot echo.
>>project.godot echo [editor_plugins]
>>project.godot echo.
>>project.godot echo enabled=PackedStringArray("res://addons/tramsim_lightmap_bake/plugin.cfg")
set "TRAMSIM_BAKE=%SCENES%"
"%G%" --editor --path . --rendering-driver vulkan --audio-driver Dummy
set RC=%ERRORLEVEL%
copy /y project.godot.bak project.godot >nul & del project.godot.bak
rmdir /s /q addons\tramsim_lightmap_bake
exit /b %RC%
