#!/usr/bin/env python3
"""Dérive une texture de roulement d'une captation libre de tram lyonnais.
Original conservé pour reproduction : data/audio/reference/lyon-citadis-original.ogg.
Glaneur de sons, 2007-03-20, CC BY 3.0. Coupe 8–12 s, filtre, raccord 250 ms,
normalisation -20 LUFS. Ce n'est pas une banque spécifique à chaque matériel.
"""
from pathlib import Path
import subprocess,json,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
 src=ROOT/'data/audio/reference/lyon-citadis-original.ogg';out=ROOT/'data/audio/real_rail.ogg'
 # Une seule période avec chevauchement de la fin et du début : raccord continu.
 filters='atrim=start=8:end=12,asetpts=PTS-STARTPTS,highpass=f=85,lowpass=f=1500,asplit=3[a][b][c];[a]atrim=start=0.25:end=3.75,asetpts=PTS-STARTPTS[mid];[b]atrim=start=3.75:end=4,asetpts=PTS-STARTPTS[tail];[c]atrim=start=0:end=0.25,asetpts=PTS-STARTPTS[head];[tail][head]acrossfade=d=0.25:c1=tri:c2=tri[join];[mid][join]concat=n=2:v=0:a=1,loudnorm=I=-20:TP=-1:LRA=7'
 subprocess.run(['ffmpeg','-v','error','-y','-i',str(src),'-filter_complex',filters,'-ar','32000','-ac','1','-c:a','libvorbis','-q:a','4',str(out)],check=True)
 p=ROOT/'data/audio/sources.json';d=json.loads(p.read_text());d['version']=3;d['statut']='Synthèse procédurale complétée par une texture issue d’une captation réelle libre. Ce mixage ne prétend pas reproduire chaque série de rames.'
 d['files']['real_rail.ogg']={'origine':'Glaneur de sons — Tram sound in Lyon, France (20 mars 2007)','licence':'CC BY 3.0 https://creativecommons.org/licenses/by/3.0/','source':'https://commons.wikimedia.org/wiki/File:Tram_sound_in_Lyon,_France.ogg','original':'reference/lyon-citadis-original.ogg','modifications':'extrait 8–12 s, passe-bande 85–1500 Hz, raccord 250 ms, mono 32 kHz, normalisation -20 LUFS','lufs':-20.0,'duree_s':3.75}
 p.write_text(json.dumps(d,ensure_ascii=False,indent=1)+'\n')
if __name__=='__main__':main()
