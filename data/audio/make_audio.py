#!/usr/bin/env python3
"""Génère les sons de data/audio/ (OGG Vorbis mono 32 kHz) pour TramAudio (src/audio/tram_audio.gd).

python3 data/audio/make_audio.py [--only nom,nom] [--demo sortie.wav]

Tous les sons sont synthétisés (aucun extrait d'œuvre protégée). v2 (« moins strident ») : timbres filtrés
passe-bas, harmoniques décroissantes, bruits rose/brun, niveaux normalisés en sonie (LUFS, pondération K de
l'ITU-R BS.1770) ; le mixage relatif est fait dans tram_audio.gd. Calibrage (aucun enregistrement libre n'a pu
être téléchargé : Wikimedia HTTP 429, Freesound / BigSoundBank inaccessibles) sur la littérature publique :
- roulement acier/acier : bande dominante 250-2000 Hz, niveau ~ 30 log10(v) (Thompson, « Railway Noise and
  Vibration », 2009 ; mesures ISO 3095 de tramways), grondement de structure < 200 Hz en cabine ;
- traction : onduleurs IGBT à MLI asynchrone (porteuse fixe ~ 0,8-1,5 kHz) au démarrage puis modes synchrones
  (rapport porteuse/fréquence statorique décroissant par paliers) ; raies magnétiques des moteurs asynchrones
  à 2f et 6f statorique (f_stat ~ 1,9 Hz par km/h pour un tramway à moteurs 4 pôles, roues 0,6 m, réduction 6,5) ;
- crissement en courbe : raies étroites 1-5 kHz (modes axiaux de roue), intermittent, rayons < 50 m ;
- signal de fermeture des portes : bips doubles ~ 1 kHz (Citadis), gong double tintement.
Boucles sans couture (fréquences multiples de 1/T, fondu enchaîné). Dépendances : numpy, scipy, ffmpeg.
--demo : rendu WAV de 30 s (départ, accélération, croisière, freinage, portes) qui reproduit en Python les
courbes de gain / hauteur de tram_audio.gd et le bus (égaliseur, compresseur, limiteur).
"""
import argparse, json, os, subprocess, tempfile
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(1985)
LOOP_LUFS = -20.0      # boucles : sonie intégrée
SHOT_LUFS = -18.0      # ponctuels : sonie momentanée max (400 ms)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def colored(sec, beta):
    """Bruit en 1/f^beta (beta=1 rose, 2 brun), périodique sur sec (boucle parfaite)."""
    n = int(SR * sec)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR); f[0] = f[1]
    x = np.fft.irfft(spec / f ** (beta / 2), n)
    return x / np.std(x)


def band(x, lo, hi, order=2):
    return signal.sosfiltfilt(signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lowp(x, fc, order=2):
    return signal.sosfiltfilt(signal.butter(order, fc, btype="low", fs=SR, output="sos"), x)


def highp(x, fc, order=2):
    return signal.sosfiltfilt(signal.butter(order, fc, btype="high", fs=SR, output="sos"), x)


def cyc_lowp(x, fc, order=2):
    """Passe-bas circulaire (FFT) : préserve la continuité d'une boucle."""
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X / np.sqrt(1 + (f / fc) ** (2 * order)), len(x))


def cyc_band(x, lo, hi, order=2):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR) + 1e-3
    h = 1 / np.sqrt(1 + (f / hi) ** (2 * order)) / np.sqrt(1 + (lo / f) ** (2 * order))
    return np.fft.irfft(X * h, len(x))


def unit(x):
    return x / (np.std(x) or 1.0)


def loopify(x, fade=0.25):
    n = int(SR * fade)
    head, body = x[:n], x[n:].copy()
    w = np.sin(np.linspace(0, np.pi / 2, n)) ** 2
    body[-n:] = body[-n:] * (1 - w) + head * w
    return body


def env(n, a, r):
    e = np.ones(n); ia, ir = int(a * SR), int(r * SR)
    if ia: e[:ia] = np.linspace(0, 1, ia) ** 2
    if ir: e[-ir:] *= np.linspace(1, 0, ir) ** 2
    return e


def put(x, s, sec):
    i = int(sec * SR); m = min(len(s), len(x) - i)
    x[i:i + m] += s[:m]


# ------------------------------------------------------------------ sonie (ITU-R BS.1770)

def _biquad_k():
    # pré-filtre K (étagement haut +4 dB à 1681 Hz, passe-haut 38 Hz) recalculé pour SR (formules RBJ)
    G, f0, Q = 3.99984385397, 1681.97445095, 0.7071752369554193
    K = np.tan(np.pi * f0 / SR); Vh = 10 ** (G / 20); Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087613982, 0.5003270373253953
    K = np.tan(np.pi * f0 / SR); a0 = 1 + K / Q + K * K
    b2 = [1, -2, 1]; a2 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return b1, a1, b2, a2


def kweight(x):
    b1, a1, b2, a2 = _biquad_k()
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x))


def lufs(x, momentary=False):
    y = kweight(np.tile(x, 2) if not momentary else x)
    if momentary:
        w = int(0.4 * SR); h = int(0.1 * SR)
        ms = [np.mean(y[i:i + w] ** 2) for i in range(0, max(1, len(y) - w), h)]
        return -0.691 + 10 * np.log10(max(max(ms), 1e-12))
    return -0.691 + 10 * np.log10(np.mean(y ** 2) + 1e-12)


def master(x, loop):
    tgt = LOOP_LUFS if loop else SHOT_LUFS
    x = x * 10 ** ((tgt - lufs(x, not loop)) / 20)
    pk = np.max(np.abs(x))
    if pk > 0.89:                                  # crête max -1 dBFS : limiteur doux
        x = np.tanh(x / 0.89) * 0.89
    return x


# ------------------------------------------------------------------ boucles

def motor():
    """Raie d'onduleur / moteur asynchrone (modes synchrones) : fondamentale 600 Hz (hauteur pilotée par
    pitch_scale, cf. TramAudio.motor_hz), harmoniques en 1/n^1,6 (2f, 3f, 4f) + 6f magnétique discrète,
    composante de bruit étroite autour de chaque raie (instabilité de la MLI), passe-bas 2,2 kHz : timbre de
    « sifflement chanté » doux plutôt que sinus pur."""
    T = 4.0; t = t_axis(T); f = 600.0
    x = np.zeros(len(t))
    for k, a in ((1, 1.0), (2, 0.42), (3, 0.24), (4, 0.11), (6, 0.08)):
        x += a * np.sin(2 * np.pi * f * k * t + 0.9 * k)
        x += a * 0.35 * unit(cyc_band(noise(T), f * k * 0.985, f * k * 1.015, 2)) * 0.25
    x *= 1 + 0.05 * np.sin(2 * np.pi * 3.0 * t) + 0.03 * np.sin(2 * np.pi * 7.5 * t)
    x += 0.10 * unit(cyc_band(colored(T, 1), 300, 3000))
    return cyc_lowp(x, 2200, 2)


def motor_hum():
    """Ronronnement électromagnétique des moteurs de traction : raie 2f statorique 120 Hz (hauteur pilotée par
    la vitesse), harmoniques en 1/n^1,3 jusqu'à 1 kHz, souffle de ventilation brun, légère ondulation de couple."""
    T = 4.0; t = t_axis(T); f = 120.0
    x = sum((1 / k ** 1.3) * np.sin(2 * np.pi * f * k * t + 0.5 * k * k) for k in range(1, 9))
    x *= 1 + 0.08 * np.sin(2 * np.pi * 6.0 * t)
    x = unit(x) + 0.35 * unit(cyc_band(colored(T, 2), 60, 900))
    return cyc_lowp(x, 1100, 2)


def carrier():
    """Porteuse de découpage MLI asynchrone (démarrage, < ~8 km/h) : raie ~1050 Hz entourée de bandes latérales
    ±2f et ±4f (le « bourdon » qui précède le chant de l'onduleur), adoucie (passe-bas 1,6 kHz, niveau bas)."""
    T = 4.0; t = t_axis(T); fc = 1050.0
    x = np.sin(2 * np.pi * fc * t)
    for df, a in ((24, 0.5), (48, 0.3), (72, 0.15)):
        x += a * (np.sin(2 * np.pi * (fc - df) * t + df) + np.sin(2 * np.pi * (fc + df) * t + 2 * df))
    x += 0.3 * np.sin(2 * np.pi * fc / 2 * t)
    x += 0.4 * unit(cyc_band(noise(T), 900, 1200)) * 0.3
    return cyc_lowp(x, 1600, 2)


def rolling():
    """Roulement acier/acier : bruit brun (grondement de caisse < 200 Hz) + bruit rose 250-1600 Hz (rugosité
    roue/rail, bande dominante des mesures), modulation de rotation de roue (6 et 12 Hz) ; niveau ~ 30 log v."""
    T = 8.0; t = t_axis(T)
    rum = unit(cyc_band(colored(T, 2), 25, 220))
    rough = unit(cyc_band(colored(T, 1), 250, 1600))
    hiss = unit(cyc_band(colored(T, 1), 1600, 4000))
    wheel = 1 + 0.18 * np.sin(2 * np.pi * 6.0 * t) + 0.08 * np.sin(2 * np.pi * 12.0 * t + 1)
    return rum * 1.0 + rough * 0.8 * wheel + hiss * 0.12


def squeal():
    """Crissement en courbe serrée : raies étroites 2,4 et 3,6 kHz (modes axiaux de roue), dérive lente,
    intermittence marquée (plages muettes), passe-bas doux ; joué rarement et bas dans le mixage."""
    T = 6.0; t = t_axis(T)
    fm = 1 + 0.008 * np.sin(2 * np.pi * (1 / 3) * t) + 0.004 * np.sin(2 * np.pi * (5 / 6) * t)
    ph = 2 * np.pi * np.cumsum(2400 * fm) / SR
    am = np.clip(cyc_lowp(noise(T), 1.5, 2) * 40 + 0.2, 0, 1) ** 1.5
    x = (np.sin(ph) + 0.35 * np.sin(1.5 * ph)) * am
    x += 0.1 * unit(cyc_band(noise(T), 1800, 4000))
    return loopify(cyc_lowp(x, 3500, 2), 0.4)


def hvac():
    """Climatisation / ventilation de toiture et compresseur : bruit rose 100-2000 Hz (ventilateurs), raie de
    passage de pales 165 Hz, ronflement de compresseur 50/100 Hz, cycle lent."""
    T = 6.0; t = t_axis(T)
    fan = unit(cyc_band(colored(T, 1), 100, 2000))
    hum = 0.5 * np.sin(2 * np.pi * 50 * t) + 0.3 * np.sin(2 * np.pi * 100 * t) + 0.12 * np.sin(2 * np.pi * 150 * t)
    bpf = 0.18 * np.sin(2 * np.pi * 165 * t) * (1 + 0.3 * np.sin(2 * np.pi * (1 / 3) * t))
    return cyc_lowp(fan * 0.6 + hum * 0.45 + bpf, 1800, 2)


def ambience():
    """Ambiance urbaine discrète : rumeur de circulation (bruit brun < 400 Hz, houle lente), passages lointains
    de véhicules, voix indistinctes très basses, quelques oiseaux faibles."""
    T = 20.0; t = t_axis(T)
    x = unit(cyc_band(colored(T, 2), 30, 400)) * (0.85 + 0.15 * np.sin(2 * np.pi * t / T * 3))
    for c in rng.uniform(0.5, T - 4, 5):
        d = rng.uniform(2.5, 4.0)
        put(x, unit(band(colored(d, 1), 120, 1200)) * np.hanning(int(SR * d)) * 0.4, c)
    for c in rng.uniform(1, T - 3, 6):                         # murmure : bruit formanté modulé syllabiquement
        d = 1.5; tt = t_axis(d)
        v = band(noise(d), 300, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 4.5 * tt)) * np.hanning(len(tt))
        put(x, unit(v) * 0.12, c)
    for c in rng.uniform(1, T - 1, 5):
        n = int(SR * 0.09); tt = np.arange(n) / SR
        put(x, np.sin(2 * np.pi * (3200 + 900 * tt / 0.09) * tt) * np.hanning(n) * 0.04, c)
    return loopify(lowp(x, 2500), 0.8)


# ------------------------------------------------------------------ ponctuels

def thud(sec, f=70.0, ring=520.0, click=0.2):
    n = int(SR * sec); t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * 28) + 0.35 * np.sin(2 * np.pi * ring * t) * np.exp(-t * 45)
    x += click * unit(band(rng.standard_normal(n), 500, 3000)) * np.exp(-t * 90) * 0.3
    return lowp(x * env(n, 0.002, 0.02), 3000)


def joint():
    """Joint de rail / soudure / cœur d'aiguillage : « ta-dam » sourd des deux essieux d'un bogie (choc grave
    70 Hz, résonance de roue 520 Hz amortie), écart 0,16 s."""
    x = np.zeros(int(SR * 0.6))
    put(x, thud(0.35), 0.0); put(x, thud(0.35, 64, 480) * 0.8, 0.16)
    return x


def brake_mech():
    """Fin de freinage (frein mécanique sous ~7 km/h) : frottement doux 400-2500 Hz croissant, brève plainte
    tonale 1,1 kHz très basse, à-coup d'arrêt (balancement de caisse) à 2,0 s."""
    T = 2.8; t = t_axis(T)
    fr = unit(band(colored(T, 1), 400, 2500)) * np.clip(t / 1.4, 0, 1) * (t < 2.0) * 0.5
    moan = np.sin(2 * np.pi * 1100 * t * (1 + 0.003 * np.sin(2 * np.pi * 4 * t))) * np.clip((t - 1.2) / 0.6, 0, 1) * (t < 2.0) * 0.08
    x = lowp(fr + moan, 2500)
    put(x, thud(0.7, 45, 300, 0.1) * 1.6, 2.0)
    return x * env(len(x), 0.05, 0.2)


def brake_release():
    """Desserrage des freins au démarrage : clic d'électrovanne étouffé + détente hydraulique (souffle bref)."""
    T = 0.8; t = t_axis(T)
    x = unit(band(colored(T, 1), 600, 3500)) * np.exp(-t * 7) * 0.3
    put(x, thud(0.12, 160, 900, 0.5) * 0.6, 0.0)
    return x


def emergency():
    """Freinage d'urgence : chute des patins électromagnétiques (choc grave), frottement des patins sur le rail
    400-3000 Hz modulé, décroissance ~3 s, buzzer cabine 620 Hz adouci."""
    T = 3.4; t = t_axis(T)
    grind = unit(band(colored(T, 1), 400, 3000)) * (0.75 + 0.25 * np.sin(2 * np.pi * 9 * t)) * np.exp(-t * 0.5)
    x = lowp(grind * 0.6, 3000)
    put(x, thud(0.6, 50, 350) * 1.5, 0.0)
    buzz = lowp(signal.square(2 * np.pi * 620 * t) * ((t * 3) % 1 < 0.6) * (t < 2.6), 1500) * 0.12
    return (x + buzz) * env(len(x), 0.005, 0.6)


def door_motor(sec, f0, f1):
    t = t_axis(sec); ph = 2 * np.pi * np.cumsum(np.linspace(f0, f1, len(t))) / SR
    w = (np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * 0.3
    w += unit(band(colored(sec, 1), 200, 1500)) * 0.12
    return lowp(w, 1500) * env(len(t), 0.15, 0.3)


def door_open():
    """Ouverture des portes louvoyantes-coulissantes : décollement des joints (souffle), moteur 150 -> 120 Hz,
    butée amortie en fin de course."""
    x = np.zeros(int(SR * 3.0))
    put(x, door_motor(2.3, 150, 120), 0.15)
    put(x, unit(band(colored(0.4, 1), 800, 3000)) * np.exp(-t_axis(0.4) * 9) * 0.2, 0.0)
    put(x, thud(0.3, 90, 400) * 0.5, 2.45)
    return x


def door_chime():
    """Signal de fermeture des portes (type Citadis) : « bip-bip » doubles à 1 kHz, sinus quasi pur à attaque
    adoucie (10 ms), 3 paires sur 2 s."""
    T = 2.2; t = t_axis(T); x = np.zeros(len(t))
    for p in (0.0, 0.7, 1.4):
        for b in (0.0, 0.22):
            n = int(SR * 0.14); tt = np.arange(n) / SR
            put(x, (np.sin(2 * np.pi * 1000 * tt) + 0.12 * np.sin(2 * np.pi * 2000 * tt)) * env(n, 0.01, 0.03), p + b)
    return lowp(x, 3000)


def door_close():
    """Fermeture : moteur 120 -> 160 Hz, contact des joints des vantaux et verrouillage (deux chocs sourds)."""
    x = np.zeros(int(SR * 3.0))
    put(x, door_motor(2.2, 120, 160), 0.0)
    put(x, thud(0.4, 80, 380) * 0.9, 2.2)
    put(x, thud(0.12, 200, 1100, 0.6) * 0.3, 2.45)
    return x


def gong():
    """Gong de tramway « ding-ding » : partiels inharmoniques de cloche (1 ; 2,0 ; 2,76 ; 5,40) sur 660 puis
    550 Hz, attaque frappée adoucie, décroissance ~1,5 s, passe-bas 4 kHz."""
    T = 2.0; t = t_axis(T); x = np.zeros(len(t))
    for hit, f0 in ((0.0, 660.0), (0.32, 550.0)):
        u = np.clip(t - hit, 0, None); on = t >= hit
        for r, a, d in ((1.0, 1.0, 2.2), (2.0, 0.35, 3.5), (2.76, 0.22, 5.0), (5.40, 0.07, 9.0)):
            x += on * a * np.sin(2 * np.pi * f0 * r * u) * np.exp(-u * d) * (1 - np.exp(-u * 600))
    return lowp(x, 4000)


LOOPS = {"motor": motor, "motor_hum": motor_hum, "carrier": carrier, "rolling": rolling, "squeal": squeal,
         "hvac": hvac, "ambience": ambience}
SHOTS = {"joint": joint, "brake_mech": brake_mech, "brake_release": brake_release, "emergency": emergency,
         "door_open": door_open, "door_chime": door_chime, "door_close": door_close, "gong": gong}


def encode(name, x, q=4):
    with tempfile.TemporaryDirectory() as d:
        w = os.path.join(d, name + ".wav")
        wavfile.write(w, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", w, "-c:a", "libvorbis", "-q:a", str(q),
                        os.path.join(OUT, name + ".ogg")], check=True)


def write_sources(stats):
    p = os.path.join(OUT, "sources.json")
    old = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    files = {}
    for name, fn in {**LOOPS, **SHOTS}.items():
        files[name + ".ogg"] = {"origine": "synthèse (data/audio/make_audio.py:%s)" % fn.__name__,
                                "licence": "création du projet (même licence que le code)",
                                "description": " ".join(fn.__doc__.split()), **stats.get(name, {})}
    d = {"generated_by": "data/audio/make_audio.py", "version": 2, "sample_rate": SR,
         "format": "OGG Vorbis mono 32 kHz, qualité 4",
         "sonie": "boucles %.0f LUFS intégrés, ponctuels %.0f LUFS momentanés max (ITU-R BS.1770) ; crête ≤ -1 dBFS"
                  % (LOOP_LUFS, SHOT_LUFS),
         "statut": "Synthèses calibrées sur la littérature publique (voir l'en-tête de make_audio.py). Tentatives de "
                   "téléchargement des enregistrements libres de référence (2026-11-11, User-Agent descriptif, 1 requête / 10 s) : "
                   "Wikimedia Commons (API et upload.wikimedia.org) HTTP 429 à 3 reprises -> abandon ; Freesound et "
                   "BigSoundBank (CC0) inaccessibles depuis l'environnement (proxy). Aucun échantillon externe inclus.",
         "files": files, "references": old.get("references", [])}
    json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


# ------------------------------------------------------------------ rendu de démonstration

def _decode(name):
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", os.path.join(OUT, name + ".ogg"), "-f", "s16le",
                        "-ac", "1", "-ar", str(SR), "-"], check=True, capture_output=True)
    return np.frombuffer(r.stdout, np.int16).astype(float) / 32767


def demo(path):
    """30 s : portes qui se ferment, gong, départ, accélération, croisière, freinage, arrêt, ouverture des portes.
    Reproduit les courbes de TramAudio (gains, hauteurs, ponctuels) à 100 Hz de contrôle, vue extérieure à 8 m."""
    # mêmes constantes que tram_audio.gd
    LDB = {"motor": -15.0, "motor_hum": -13.0, "carrier": -24.0, "rolling": -8.0, "squeal": -26.0, "hvac": -21.0, "ambience": -20.0}
    SDB = {"joint": -13.0, "brake_mech": -14.0, "brake_release": -20.0, "door_open": -15.0, "door_chime": -17.0,
           "door_close": -14.0, "gong": -11.0}
    S = {n: _decode(n) for n in list(LDB) + list(SDB)}
    D = 30.0; N = int(D * SR); out = np.zeros(N); ctl = 100; dt = 1 / ctl
    pos = {n: 0.0 for n in LDB}; g = {n: 0.0 for n in LDB}
    v = 0.0; joint_left = 9.0; shots = []
    r = np.random.default_rng(7)
    for i in range(int(D * ctl)):
        tt = i * dt
        if tt < 3.0: notch = 0.0
        elif v < 12.0 and tt < 14.0: notch = 1.0
        elif tt < 17.0: notch = 0.0
        else: notch = -0.7
        acc = 1.15 * notch if notch > 0 else (-1.2 if notch < 0 else -0.03)
        pv = v; v = max(0.0, min(12.0, v + acc * dt))
        doors = tt < 0.05 or tt > 28.0
        trac = max(notch, 0.0); eb = max(-notch, 0.0) * np.clip((v - 0.8) / 1.7, 0, 1)
        load = max(trac, eb); kmh = v * 3.6
        tg = {"motor": (0.35 + 0.65 * load) if load > 0.02 else 0.1 * np.clip((v - 1) / 5, 0, 1),
              "motor_hum": (0.4 + 0.6 * load) * np.clip(v / 1.0, 0.3, 1) if load > 0.02 else 0.2 * np.clip(v / 6, 0, 1),
              "carrier": load * (1 - np.clip((v - 1.5) / 1.0, 0, 1)) * (0.6 + 0.4 * trac),
              "rolling": min(v / 16.0, 1.0) ** 1.5, "squeal": 0.0,
              "hvac": 0.6 + 0.4 * (1 - np.clip(v / 6, 0, 1)), "ambience": 1.0}
        k = min(dt * 6, 1)
        for n in g: g[n] += (tg[n] - g[n]) * k
        pitch = {"motor": motor_hz(v) / 600.0, "motor_hum": hum_hz(v) / 120.0, "carrier": 1.0,
                 "rolling": 0.75 + 0.5 * min(v / 19.4, 1), "squeal": 1.0, "hvac": 1.0, "ambience": 1.0}
        a, b = int(tt * SR), int((tt + dt) * SR)
        for n in LDB:
            s = S[n]; ph = pos[n] + pitch[n] * np.arange(b - a)
            idx = ph % len(s); i0 = idx.astype(int); fr = idx - i0
            out[a:b] += (s[i0] * (1 - fr) + s[(i0 + 1) % len(s)] * fr) * g[n] * 10 ** (LDB[n] / 20)
            pos[n] = (ph[-1] + pitch[n]) % len(s)
        joint_left -= v * dt
        if joint_left <= 0:
            joint_left = r.uniform(14, 36)
            if v > 1.5: shots.append(("joint", tt, min(0.35 + kmh / 60, 1)))
        if notch < -0.05 and pv >= 2.0 > v > 0.05: shots.append(("brake_mech", tt, 0.85))
        if pv < 0.05 <= v: shots.append(("brake_release", tt, 0.8))
    shots += [("door_chime", 0.1, 1.0), ("door_close", 0.55, 1.0), ("gong", 2.0, 1.0), ("door_open", 28.3, 1.0)]
    for n, tt, vol in shots:
        put(out, S[n] * vol * 10 ** (SDB[n] / 20), tt)
    # bus : égaliseur (atténuation douce > 4 kHz), compresseur (-18 dB, 3:1), limiteur (-1 dBFS)
    out = out - 0.3 * lowp(highp(out, 4000), 12000)
    e = np.sqrt(lowp(out ** 2, 8) .clip(1e-12)); lvl = 20 * np.log10(e)
    gr = np.where(lvl > -18, (lvl + 18) * (1 - 1 / 3), 0)
    out = out * 10 ** (-gr / 20)
    out *= 10 ** ((-16.0 - lufs(out)) / 20)          # écoute : -16 LUFS (gain de sortie, mixage inchangé)
    out = np.tanh(out / 0.89) * 0.89
    wavfile.write(path, SR, (out * 32767).astype(np.int16))
    print("démo %s : %.1f s, %.1f LUFS" % (path, D, -0.691 + 10 * np.log10(np.mean(kweight(out) ** 2))))


def motor_hz(v):
    """Copie de TramAudio.motor_hz (paliers de modes synchrones à 18 et 38 km/h)."""
    kmh = v * 3.6
    if kmh < 4: return 300 + 120 * kmh / 4
    if kmh < 18: return 420 + 400 * (kmh - 4) / 14
    if kmh < 38: return 540 + 360 * (kmh - 18) / 20
    return 620 + 380 * min((kmh - 38) / 32, 1)


def hum_hz(v):
    return 55 + 3.2 * v * 3.6


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--demo", default="")
    a = ap.parse_args()
    if a.demo:
        demo(a.demo); return
    only = [s for s in a.only.split(",") if s]
    stats = {}
    for name, fn in {**LOOPS, **SHOTS}.items():
        if only and name not in only:
            continue
        loop = name in LOOPS
        x = master(fn(), loop)
        encode(name, x)
        stats[name] = {"lufs": round(lufs(x, not loop), 1), "duree_s": round(len(x) / SR, 2)}
        print("synthèse %-14s %5.1f LUFS  %.2f s" % (name, stats[name]["lufs"], len(x) / SR))
    if not only:
        write_sources(stats)
    tot = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
    print("total data/audio : %.1f Ko" % (tot / 1024))


if __name__ == "__main__":
    main()
