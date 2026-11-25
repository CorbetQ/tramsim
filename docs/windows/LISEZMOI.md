# Tram Sim France pour Windows

- **Snapdragon / Surface Pro X / Windows sur ARM** : choisir **ARM64**.
- **Intel / AMD** : choisir **x64**.

Portable : extraire **tout** le ZIP puis ouvrir `TramSimFrance.exe`. Garder le fichier
`TramSimFrance.pck` à côté. L’exécutable est le moteur Godot officiel, signé par
**Prehensile Tales B.V.**, distribué sans modification. Il lance les données TramSim
contenues dans le PCK. Son icône et ses propriétés restent celles de Godot afin de
conserver sa signature. Ce n’est pas une signature de TramSim par cet éditeur.

Le MSI installe pour le compte courant, sans exiger les droits administrateur, dans
`%LOCALAPPDATA%\Programs\TramSimFrance\arm64` ou `x64`. Un raccourci est ajouté au
menu Démarrer. La désinstallation laisse les sauvegardes Godot dans AppData.
Les anciens MSI étaient par machine : s’il en reste un, le désinstaller depuis
Paramètres → Applications avant de choisir cette nouvelle installation.

**Contrôle intelligent des applications** : le message « application potentiellement
dangereuse » diffère de l’avertissement SmartScreen. « Exécuter quand même » n’est
pas une option pour ce blocage. Ne pas désactiver la protection Windows.
La signature du moteur est vérifiée par la CI Windows. Le fichier MSI lui-même
reste non signé tant qu’un certificat de signature de code TramSim reconnu n’est
pas configuré. Si une politique refuse ce MSI, choisir le ZIP portable avec son
moteur signé ; ne pas importer de certificat auto-signé pour contourner la protection.

Les rapports CI vérifient le démarrage du vrai jeu sans ses sources, l’installation,
la réinstallation et la désinstallation sur Windows x64 et Windows ARM64 natifs.
Ils ne reproduisent pas toutes les politiques locales de sécurité ni le GPU physique.

Provenance : `RUNTIME-PROVENANCE.json`, `GODOT-LICENSE.txt`, `GODOT-COPYRIGHT.txt`.
Les crédits du jeu et des données se trouvent dans `CREDITS.md`.
