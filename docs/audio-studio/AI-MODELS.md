# Évaluation IA locale — aucune génération effectuée

Vérifications pendant la mission : API Hugging Face et sources officielles GitHub.
Aucun poids téléchargé ; aucun résultat d'inférence, aucune écoute IA à revendiquer.

| Solution | Code / poids | Ressources / interface | Décision |
|---|---|---|---|
| Soundbox (HamSanders) | Application MIT ; licence de chaque moteur et poids indépendante | Node/TypeScript, HTTP localhost:17494, jobs/SSE, backends audio.cpp CPU possibles | Adaptateur de soumission implémenté et contrat testé avec réponse simulée. Application non installée, pas d'inférence réelle testée. |
| Stable Audio Open Small | stable-audio-tools MIT ; métadonnées de poids `stability-ai-community`, accès `gated:auto` | Modèle principal 341 M paramètres + conditionnement ; safetensors officiel 1 676 829 212 octets ; sorties annoncées jusqu'à 11 s, CPU possible mais lent | README/LICENSE raw officiels HTTP 401 dans cet environnement. Éligibilité et conditions commerciales non validées. Aucun téléchargement. |
| Stable Audio 3 Small SFX via Soundbox/audio.cpp | Poids annoncés sous conditions Stability ; licence de chaque révision à vérifier | Backend local quantifié exposé par Soundbox ; CPU possible, durée annoncée jusqu'à 120 s | Candidat d'évolution, pas de vérification complète des poids/dépendances ni de mesure RAM/temps. Non approuvé. |
| AudioGen / AudioCraft | Code MIT ; LICENSE_weights **CC BY-NC 4.0** | PyTorch, CPU/GPU ; dépendances et modèles absents | Poids exclus de la chaîne commerciale. Pas d'installation. |

Matériel réellement détecté : quota CPU 2 cœurs, limite mémoire 8 Gio, aucun GPU,
PyTorch absent. Disque racine presque plein, environ 3,4 Gio de tmpfs libres après
l'audit. Le tmpfs consomme la même mémoire que l'inférence : ce n'est pas du disque
supplémentaire indépendant. Ni RAM de pic ni vitesse d'un modèle ne sont inventées.
Le poids de 1,68 Go n'est pas une estimation de la RAM totale requise : runtime,
conditionnement et buffers s'ajoutent. Les solutions plus lourdes ne sont pas installées.

La licence Community n'est pas une licence commerciale inconditionnelle. Vérifier
l'accord en vigueur, l'éligibilité de l'entité, les éventuelles obligations de
registration/attribution et les conditions de distribution avant activation.
Un code MIT ne libère pas les poids. Le gate HF n'a pas été contourné par un miroir.

Sources primaires consultées :

- https://github.com/HamSanders/soundbox — README, LICENSE, docs/GENERATING.md, docs/INSTALL-AGENT.md.
- https://huggingface.co/api/models/stabilityai/stable-audio-open-small?blobs=true — métadonnées publiques, taille des fichiers, gate et licence déclarée.
- https://huggingface.co/stabilityai/stable-audio-open-small — accord soumis à acceptation par le compte utilisateur.
- https://stability.ai/license — conditions actuelles à consulter avant usage commercial.
- https://github.com/facebookresearch/audiocraft/blob/main/LICENSE_weights — NC explicite.

Les fichiers de recherche bruts sont en cache local, pas des poids inclus au dépôt.
La configuration livrée est entièrement désactivée. L'adaptateur ne télécharge ni
n'installe rien. Son reçu indique `submitted_not_generated` : la fin d'un job doit
être vérifiée dans Soundbox et le WAV exporté avant toute inscription au catalogue
comme fichier généré. Les résultats devront rester `ai_generated` et passer les
mêmes contrôles de droits, empreintes, niveau, clipping et validation humaine.
