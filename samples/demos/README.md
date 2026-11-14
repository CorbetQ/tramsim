# Captures réelles du mixage Godot

- `citadis_302_godot_mix.ogg` : Citadis 302 Angers, mixage utilisant une captation de Citadis 302 du Mans, retraitée pour le moteur.
- `citadis_305_godot_mix.ogg` : Citadis 305 Toulouse, son modélisé ; ce fichier ne constitue pas une captation d'une rame 305 réelle.
- Les WAV sont les maîtres PCM stéréo 16 bits, 48 000 Hz. Les OGG sont encodés par FFmpeg/libvorbis qualité 4, sans normalisation ni amplification supplémentaire.

Il s'agit bien des sorties du moteur Godot 4.6.3 : AudioEffectRecord ajouté au bus Master, après les bus cabine, environnement et TramFX. Les lecteurs AudioStreamPlayer et AudioStreamPlayer3D, leurs gains, leurs hauteurs et les effets Godot produisent le signal. Aucun signal n'a été recréé par Python.

Le scénario est prescrit, et ne représente pas une conduite manuelle : une MissionSession fournit l'interface d'état réelle, tandis que le programme impose sa vitesse pour comparer les deux modèles. La vue est un petit Node3D avec caméra ; aucun décor n'est nécessaire. Les zones de tunnel/pont sont imposées sur les spans de l'arête de test. Les JSON contiennent la chronologie des états, gains et compteurs d'événements ; ces valeurs d'instrumentation seules ne prouvent pas une audibilité.

## Scénario de 48 secondes

| Secondes | État |
| --- | --- |
| 0–2 | Arrêt, cabine |
| 2–5 | Ouverture et maintien des portes |
| 5–7 | Signal et fermeture différée, gong |
| 7–23 | Accélération graduelle 0–50 km/h, cran progressif |
| 23–27 | Roue libre 50–46 km/h, passage en extérieur |
| 27–39 | Freinage progressif 46–0 km/h |
| 27–31 | Tunnel, extérieur |
| 31–35 | Pont ; retour cabine à 33 s |
| 39–42 | Ouverture des portes à l'arrêt |
| 42–44 | Fermeture et fin des événements |
| 44–46 | Pause des lecteurs |
| 46–48 | Reprise à l'arrêt |

## Reproduction Linux

Depuis la racine du dépôt :

```sh
bash tools/audio/capture_driving_audio.sh citadis_302 angers__citadis_302
bash tools/audio/capture_driving_audio.sh citadis_305 toulouse__citadis_305
```

Exécuter ces commandes séquentiellement. Le script compile un petit adaptateur local `alsa_null_clock.c`, crée une configuration ALSA null temporaire et force temporairement `audio/driver/mix_rate=48000` dans override.cfg, restauré ensuite. Il utilise le pilote ALSA explicite et le rendu headless. `--headless` seul sélectionnerait Dummy ; Dummy ne constitue pas une preuve de sortie mixée.

Le périphérique ALSA null accepte les trames sans les cadencer. L'adaptateur intercepte uniquement la résolution `snd_pcm_writei` et attend une échéance monotone absolue calculée en fonction du nombre de trames acceptées / 48000. Il ne lit ni ne modifie le tampon PCM. Cette attente assure la cadence du vrai mélangeur Godot. Le premier essai sans cadence était inexploitable ; le mode movie avec rendu Dummy provoquait un crash de texture. Les fichiers livrés proviennent de la méthode ALSA cadencée validée.

Les deux captures finales durent respectivement 47,957 s et 47,925 s pour 48 s de scénario. L'écart inférieur à 0,08 s couvre le début/arrêt de l'enregistrement et les tampons. Le taux déclaré par AudioServer et par les WAV est 48000 Hz. Les logs `CAPTURE_BEGIN` / `CAPTURE_END` attestent du pilote ALSA, du taux et du nombre de données reçues. Les fichiers n'ont pas été étirés pour masquer cet écart.

Les métriques objectives ne certifient ni l'absence de tout clic perceptible ni la fidélité industrielle. L'avis d'écoute sur le timbre reste nécessaire avant publication.
