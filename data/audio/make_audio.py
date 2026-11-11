#!/usr/bin/env python3
"""Génère les sons de data/audio/ (OGG Vorbis mono 32 kHz) pour TramAudio (src/audio/tram_audio.gd).

python3 data/audio/make_audio.py [--only nom,nom]

Tous les sons sont synthétisés (aucun extrait d'œuvre protégée). Les paramètres (fréquences, enveloppes,
cadences) reprennent les caractéristiques publiées des tramways modernes : onduleurs IGBT à porteuse
asynchrone puis modes synchrones, roulement acier/acier, crissement de courbe 2-5 kHz, signal de fermeture
des portes, etc. Les enregistrements libres de référence identifiés sur Wikimedia Commons (licences dans
data/audio/sources.json) n'ont pas pu être téléchargés depuis l'environnement de génération (HTTP 429) :
leurs descriptions ont guidé la liste des couches, pas leurs échantillons.
Boucles sans couture (fréquences multiples de 1/T, fondu enchaîné fin/début). Dépendances : numpy, scipy, ffmpeg.
"""
import argparse, os, subprocess, tempfile
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(1985)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def band(x, lo, hi, order=4):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfiltfilt(sos, x)


def lowp(x, fc, order=4):
    sos = signal.butter(order, fc, btype="low", fs=SR, output="sos")
    return signal.sosfiltfilt(sos, x)


def highp(x, fc, order=4):
    sos = signal.butter(order, fc, btype="high", fs=SR, output="sos")
    return signal.sosfiltfilt(sos, x)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def loopify(x, fade=0.25):
    """Boucle sans couture : la fin est fondue dans le début."""
    n = int(SR * fade)
    head, body = x[:n], x[n:].copy()
    w = np.linspace(0, 1, n)
    body[-n:] = body[-n:] * (1 - w) + head * w
    return body


def env_adsr(n, a, d, s, r):
    e = np.ones(n)
    ia, idd, ir = int(a * SR), int(d * SR), int(r * SR)
    e[:ia] = np.linspace(0, 1, ia, endpoint=False) if ia else 1
    e[ia:ia + idd] = np.linspace(1, s, idd, endpoint=False) if idd else s
    e[ia + idd:] = s
    if ir:
        e[-ir:] *= np.linspace(1, 0, ir)
    return e


# ------------------------------------------------------------------ couches (boucles)

def motor():
    """Sifflement d'onduleur IGBT / moteur asynchrone : fondamentale 1000 Hz (hauteur pilotée par pitch_scale
    selon la vitesse, cf. TramAudio.motor_hz), harmoniques 2f et 3f, sous-harmonique magnétostrictive f/2,
    bandes latérales ±(2 × 60 Hz) de la modulation, souffle de ventilation."""
    T = 2.0; t = t_axis(T)
    f = 1000.0
    x = (1.0 * np.sin(2 * np.pi * f * t) + 0.32 * np.sin(2 * np.pi * 2 * f * t + 0.7)
         + 0.16 * np.sin(2 * np.pi * 3 * f * t + 1.9) + 0.22 * np.sin(2 * np.pi * 0.5 * f * t)
         + 0.12 * np.sin(2 * np.pi * (f - 120) * t) + 0.12 * np.sin(2 * np.pi * (f + 120) * t))
    x *= 1.0 + 0.06 * np.sin(2 * np.pi * 4.0 * t)
    hiss = band(noise(T + 0.5), 1500, 6000)[: len(t)]
    x = x + 0.25 * norm(hiss, 1.0) * 0.6
    return norm(x, 0.8)


def carrier():
    """Porteuse de découpage MLI asynchrone (basse vitesse) : raie fixe ~1350 Hz et bandes latérales ±40/80 Hz,
    2fc atténuée — le « bourdon aigu » constant au démarrage des Citadis avant le passage en modes synchrones."""
    T = 2.0; t = t_axis(T)
    fc = 1350.0
    x = (np.sin(2 * np.pi * fc * t) + 0.45 * np.sin(2 * np.pi * (fc - 40) * t) + 0.45 * np.sin(2 * np.pi * (fc + 40) * t)
         + 0.2 * np.sin(2 * np.pi * (fc - 80) * t) + 0.2 * np.sin(2 * np.pi * (fc + 80) * t) + 0.25 * np.sin(2 * np.pi * 2 * fc * t))
    return norm(x, 0.7)


def rolling():
    """Roulement acier/acier : grondement < 300 Hz, rugosité roue-rail 400-1600 Hz, modulation de rotation
    de roue (périmètre ~2 m) ; hauteur et niveau pilotés par la vitesse."""
    T = 4.25; n = noise(T)
    rum = lowp(np.cumsum(n) * 0.02, 260)
    rough = band(n, 400, 1600)
    t = t_axis(T)
    wheel = 1.0 + 0.25 * np.sin(2 * np.pi * 6.0 * t) + 0.1 * np.sin(2 * np.pi * 12.0 * t)
    x = norm(rum, 1.0) * 0.8 + norm(rough, 1.0) * 0.45 * wheel
    return norm(loopify(x), 0.85)


def squeal():
    """Crissement en courbe serrée (stick-slip latéral) : raies étroites 3,2 et 4,1 kHz, glissements de
    fréquence lents, amplitude intermittente."""
    T = 3.25; t = t_axis(T)
    fm = 1 + 0.012 * np.sin(2 * np.pi * 0.7 * t) + 0.006 * np.sin(2 * np.pi * 2.3 * t)
    ph1 = 2 * np.pi * np.cumsum(3200 * fm) / SR
    ph2 = 2 * np.pi * np.cumsum(4100 * fm) / SR
    am = np.clip(0.6 + 0.5 * lowp(noise(T), 3.0) * 8, 0.0, 1.0)
    x = (np.sin(ph1) + 0.5 * np.sin(ph2) + 0.15 * np.sin(2 * ph1)) * am
    x += 0.15 * norm(band(noise(T), 2500, 5000), 1.0)
    return norm(loopify(x), 0.75)


def hvac():
    """Compresseur / climatisation de toiture au ralenti : ventilateur (bruit large bande 150-3000 Hz, raie de
    passage de pales 190 Hz), compresseur (harmoniques 50/100/150 Hz)."""
    T = 4.25; t = t_axis(T)
    fan = band(noise(T), 150, 3000, 2)
    hum = 0.5 * np.sin(2 * np.pi * 50 * t) + 0.35 * np.sin(2 * np.pi * 100 * t) + 0.15 * np.sin(2 * np.pi * 150 * t)
    bpf = 0.25 * np.sin(2 * np.pi * 190 * t) * (1 + 0.2 * np.sin(2 * np.pi * 1.0 * t))
    x = norm(fan, 1.0) * 0.7 + hum * 0.5 + bpf
    return norm(loopify(x), 0.7)


def ambience():
    """Ambiance urbaine lointaine : rumeur de circulation (bruit brun < 500 Hz, houle lente), passages de
    véhicules (bouffées filtrées), pépiements rares."""
    T = 12.5; t = t_axis(T)
    base = lowp(np.cumsum(noise(T)) * 0.01, 500)
    base = norm(base - lowp(base, 20), 1.0) * (0.8 + 0.2 * np.sin(2 * np.pi * t / T * 2))
    x = base * 0.6
    for c in rng.uniform(0.5, T - 2.5, 4):
        n = int(SR * 2.2); s = int(c * SR)
        car = band(noise(2.2), 120, 1800) * np.hanning(n)
        x[s:s + n] += norm(car, 1.0) * 0.35
    for c in rng.uniform(1, T - 1, 6):
        n = int(SR * 0.12); s = int(c * SR); tt = np.arange(n) / SR
        chirp = np.sin(2 * np.pi * (3800 + 1500 * tt / 0.12) * tt) * np.hanning(n)
        x[s:s + n] += chirp * 0.06
    return norm(loopify(x, 0.5), 0.7)


# ------------------------------------------------------------------ ponctuels

def clack(sec=0.25):
    n = int(SR * sec); t = np.arange(n) / SR
    ring = (np.sin(2 * np.pi * 950 * t) * np.exp(-t * 60) + 0.6 * np.sin(2 * np.pi * 2150 * t) * np.exp(-t * 90))
    thump = np.sin(2 * np.pi * 85 * t) * np.exp(-t * 35)
    click = band(rng.standard_normal(n), 800, 6000) * np.exp(-t * 120)
    return ring * 0.5 + thump * 0.9 + norm(click, 1.0) * 0.5


def joint():
    """Joint de rail / cœur d'aiguillage : « ta-tac » des deux essieux d'un bogie (empattement 1,8 m à
    ~40 km/h -> ~0,16 s)."""
    x = np.zeros(int(SR * 0.6))
    a = clack(); x[:len(a)] += a
    s = int(SR * 0.16); x[s:s + len(a)] += a * 0.8
    return norm(x, 0.9)


def brake_mech():
    """Freinage mécanique final (frein à disque / patins, sous ~7 km/h) : frottement 1,5-6 kHz croissant,
    crissement bref 2,7 kHz, à-coup d'arrêt à 2,1 s."""
    T = 2.8; t = t_axis(T)
    fr = norm(band(noise(T), 1500, 6000), 1.0) * np.clip(t / 1.6, 0, 1) * (t < 2.1)
    sq = np.sin(2 * np.pi * 2700 * t * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))) * np.clip((t - 1.4) / 0.4, 0, 1) * (t < 2.1)
    x = fr * 0.6 + sq * 0.35
    s = int(SR * 2.1); th = clack(0.5) * 0.9; x[s:s + len(th)] += th[: len(x) - s]
    return norm(x * env_adsr(len(x), 0.05, 0, 1, 0.15), 0.85)


def brake_release():
    """Desserrage des freins au démarrage : clic d'électrovanne + détente hydraulique / pneumatique."""
    T = 0.8; t = t_axis(T)
    x = norm(band(noise(T), 2000, 9000), 1.0) * np.exp(-t * 6) * 0.5
    c = clack(0.1); x[: len(c)] += c * 0.6
    return norm(x, 0.7)


def emergency():
    """Freinage d'urgence : chute des patins électromagnétiques (choc grave), grincement large bande
    700-5000 Hz modulé, décroissance sur ~3 s, buzzer cabine 800 Hz."""
    T = 3.4; t = t_axis(T)
    grind = norm(band(noise(T), 700, 5000), 1.0) * (0.7 + 0.3 * np.sin(2 * np.pi * 11 * t)) * np.exp(-t * 0.5)
    th = clack(0.6)
    x = grind * 0.7
    x[: len(th)] += th * 1.2
    buzz = signal.square(2 * np.pi * 800 * t) * 0.12 * ((t * 4) % 1 < 0.6) * (t < 2.5)
    x += lowp(buzz, 3000)
    return norm(x * env_adsr(len(x), 0.01, 0, 1, 0.6), 0.9)


def door_motor(sec, f0, f1):
    t = t_axis(sec)
    f = np.linspace(f0, f1, len(t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    whir = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)) * 0.35
    whir += norm(band(noise(sec), 300, 2500), 1.0) * 0.15
    return whir * env_adsr(len(t), 0.08, 0, 1, 0.2)


def door_open():
    """Ouverture des portes louvoyantes-coulissantes : moteur 230 -> 180 Hz (~2,5 s), décollement des joints,
    butée en fin de course."""
    x = np.zeros(int(SR * 3.0))
    d = door_motor(2.4, 230, 180); x[int(SR * 0.1): int(SR * 0.1) + len(d)] += d
    pop = clack(0.15) * 0.4; x[: len(pop)] += pop
    th = clack(0.3) * 0.5; s = int(SR * 2.5); x[s:s + len(th)] += th
    return norm(x, 0.8)


def door_chime():
    """Signal de fermeture des portes (tramways français) : bips 2 kHz, 4 par seconde pendant 2 s."""
    T = 2.0; t = t_axis(T)
    gate = ((t * 4) % 1) < 0.45
    tone = np.sin(2 * np.pi * 2000 * t) + 0.3 * np.sin(2 * np.pi * 4000 * t)
    x = tone * lowp(gate.astype(float), 200)
    return norm(x, 0.6)


def door_close():
    """Fermeture : moteur 180 -> 240 Hz, choc des vantaux et verrouillage."""
    x = np.zeros(int(SR * 3.0))
    d = door_motor(2.3, 180, 240); x[: len(d)] += d
    th = clack(0.4) * 0.9; s = int(SR * 2.3); x[s:s + len(th)] += th
    c = clack(0.1) * 0.4; s = int(SR * 2.55); x[s:s + len(c)] += c
    return norm(x, 0.85)


def gong():
    """Gong de tramway (double tintement) : partiels inharmoniques de cloche (1 ; 2,76 ; 5,40 ; 8,93) sur
    880 Hz, deux frappes à 0,28 s, décroissance ~1,2 s."""
    T = 1.8; t = t_axis(T)
    x = np.zeros(len(t))
    for hit, f0 in ((0.0, 880.0), (0.28, 740.0)):
        u = np.clip(t - hit, 0, None); on = t >= hit
        for r, a, d in ((1.0, 1.0, 3.0), (2.76, 0.45, 5.0), (5.40, 0.25, 8.0), (8.93, 0.12, 12.0)):
            x += on * a * np.sin(2 * np.pi * f0 * r * u) * np.exp(-u * d)
    return norm(x, 0.85)


SYNTH = {"motor": motor, "carrier": carrier, "rolling": rolling, "squeal": squeal, "hvac": hvac, "ambience": ambience,
         "joint": joint, "brake_mech": brake_mech, "brake_release": brake_release, "emergency": emergency,
         "door_open": door_open, "door_chime": door_chime, "door_close": door_close, "gong": gong}

def encode(name, x, q=3):
    with tempfile.TemporaryDirectory() as d:
        w = os.path.join(d, name + ".wav")
        wavfile.write(w, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", w, "-c:a", "libvorbis", "-q:a", str(q),
                        os.path.join(OUT, name + ".ogg")], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    for name, fn in SYNTH.items():
        if only and name not in only:
            continue
        encode(name, fn())
        print("synthèse", name)
    tot = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
    print("total data/audio : %.1f Ko" % (tot / 1024))


if __name__ == "__main__":
    main()
