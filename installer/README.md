# Installeurs natifs Windows

L’ancien `tramsim.wxs`/wixl créait deux MSI de plateforme x64, y compris pour l’EXE ARM64.
Cette voie n’est plus utilisée. La génération est centralisée dans :

```powershell
python tools/windows/build_installer.py --source build/win-arm64 --arch arm64 --version 0.13.2 --output build/arm64.wxs
dotnet tool install wix --version 5.0.2 --tool-path .tools/wix
.tools/wix/wix.exe build -arch arm64 -o build/TramSimFrance-arm64.msi build/arm64.wxs
```

WiX 5.0.2 est épinglé (MS-RL, avant le changement de conditions de WiX 6).
Le MSI complet est construit **et installé** sur un runner Windows ARM64 natif ; x64 utilise son propre runner.
La plateforme MSI est vérifiée via son SummaryInformation. Tous les fichiers, y compris les éventuels
sous-dossiers, sont installés et comparés octet par octet à la version portable.
Les composants par utilisateur utilisent des clés HKCU et des GUID propres à chaque architecture.
Les mises à jour de même version sont permises ; aucune action personnalisée n’est exécutée.

Le moteur officiel est signé et ne doit subir aucune modification de ressources ni ajout du PCK dans l’EXE.
La signature du **conteneur MSI** est distincte. Les secrets optionnels `WINDOWS_SIGNING_PFX_BASE64`
et `WINDOWS_SIGNING_PFX_PASSWORD` permettent de le signer avec un certificat de projet reconnu.
Aucun certificat auto-signé n’est ajouté aux autorités de confiance et aucun service payant n’est activé.
Sans ces secrets, le rapport indique explicitement `NotSigned` pour le MSI.

Ne pas confondre validation d’installation, confiance Authenticode et politique Smart App Control :
la CI contrôle les deux premières, pas la configuration locale du PC du joueur.
