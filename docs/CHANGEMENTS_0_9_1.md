# 0.9.1 — contraste et listes déroulantes

Les menus de ville, ligne, service, départ, matériel et livrée utilisent désormais
`TouchChoice`. Un panneau est ouvert dans le viewport principal, avec une liste
`TouchScroll`, des lignes de 54 px, une recherche et un bouton Fermer. Un glissement
annule le clic même s'il traverse plusieurs lignes ou sort de la liste ; la page
derrière le panneau ne reçoit pas le geste. Une sélection retrouve son indice
original après filtrage. Retour Android ferme le panneau sans quitter le jeu ;
le comportement de sortie est restauré après la fermeture, aussi lors d'une
réouverture immédiate.

L'ancien correctif portait sur le ScrollContainer du formulaire. Le PopupMenu
natif d'OptionButton, ouvert dans une fenêtre distincte, échappait à cette
capture. Les tests injectent maintenant des pressions et glissements dans une
liste réellement ouverte, plutôt que de tester uniquement le formulaire fermé.

Le rendu réduit le remplissage ambiant de jour (0,55 → 0,30), renforce la teinte
froide et la profondeur des ombres cel shading, réduit le voile atmosphérique
proche et augmente modérément la saturation des matériaux. Une courbe de
contraste douce est intégrée à la passe des effets de vitesse, avant le HUD.
Elle préserve les extrémités noir/blanc et s'atténue la nuit. Les réglages sont
communs au renderer Compatibility sur Android et Windows ; le calcul des
lumières par fragment est explicitement conservé pour les shaders personnalisés.
Référence moteur : https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html#light-built-ins

Vérifications : tests tactiles sur fenêtres 640×360 et 800×450 (défilement du
menu ouvert, absence de sélection accidentelle, immobilité du formulaire,
recherche, sélection et fermeture Échap/Retour), tests du HUD et des commandes,
captures OpenGL comparables à 9 h avec le profil graphique mobile, puis capture
avec les ombres activées. Aucun essai sur téléphone Android physique ici.
Les données géographiques et la physique de conduite restent celles de 0.9.
