#!/usr/bin/env python3
"""Reconstruction explicite (réseau requis pour les sources absentes), puis contrôles.
Utilise les extraits versionnés lorsqu'ils sont disponibles. Aucun téléchargement
n'est effectué par le jeu. Les références de profils sont figées sur la version 0.7.
"""
import subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
steps=['tools/import/fetch_railways.py','tools/import/fetch_rail_elevations.py',
       'tools/import/extend_terrain.py','tools/import/physical_network.py',
       'tools/import/identify_depots.py','tools/import/depot_buildings.py',
       'tools/import/extend_scenery.py','tools/import/sync_mission_terrain.py',
       'tools/maintenance/conform_ground.py','tools/world_quality_report.py']
if __name__=='__main__':
    for step in steps:
        print(step,flush=True)
        subprocess.run([sys.executable,str(ROOT/step)],cwd=ROOT,check=True)
    subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py'],cwd=ROOT,check=True)
