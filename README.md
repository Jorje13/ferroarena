# Ferro Arena

Jeu de tir à la troisième personne en arène, sous Godot 4.7 (Forward+, Jolt), jouable seul contre des bots ou en ligne.
Une seule arme, le **Ferro** : un tir par chargeur, un rechargement lent, projectile avec temps de vol.

## Modes de jeu

- **Élimination par équipes** : de 1v1 à 10v10, en manches, avec mise à terre et relevage.
- **Battle royale** : chacun pour soi, bots au choix, départs répartis sur la carte, zone qui se resserre, le dernier en vie gagne.
- **Prop hunt** : un chasseur tiré au sort contre des props qui se transforment en objets de la carte (**E**). Le chasseur est aveugle 30 s, un tir tue, les props sifflent toutes les 20 s. Sans bots, 2 joueurs minimum.

- **Survie zombies** : coopération, 10 vagues de monstres (Faucheurs aux griffes qui balayent le sol, Bondisseurs qui bondissent). Entre les vagues, les tombés se relèvent et les caisses se remplissent. Seul ou en équipe, sans bots.

Les bots ont quatre niveaux de difficulté (Facile, Normal, Difficile, Expert).

## Lancer

Ouvrir `project.godot` dans Godot 4.7 puis F5. Le menu propose l'entraînement solo, l'hébergement d'un salon (port UDP 7777) et la connexion à un hôte par IP. Tous les joueurs doivent avoir la même version (`Game.GAME_VERSION`).

Export : `Godot --headless --path . --export-release Windows ../build/FerroArena.exe`.

## Commandes (touches physiques, rebindables dans le menu)

| Action | Touche |
|---|---|
| Se déplacer | ZQSD |
| Sprint | Maj |
| Accroupi / glissade (pendant un sprint) | C / Ctrl |
| Roulade | Alt |
| Saut, escalade, franchissement | Espace |
| Viser / Tirer | Clic droit / Clic gauche |
| Recharger | R |
| Changer d'épaule | F |
| Arme / objets | 1 / 2 à 5 |
| Bandage | A |
| Bouclier | X |
| Fouiller une caisse, relever un allié, se transformer (prop hunt) | E |
| Scores | Tab |

## Mises à jour

Le jeu exporté vérifie au lancement les releases GitHub et se met à jour tout seul (`scripts/autoload/updater.gd`).
Chaque release contient le zip complet et des patchs incrémentiels (`.fdl`, quelques Mo) depuis chacune des douze versions précédentes : le jeu applique d'un coup le patch de sa version vers la dernière, sans passer par les intermédiaires (au-delà, zip complet) ; format et code dans `scripts/util/fdl_source.gd`. Publier : `tools/release.ps1 -Version X.Y.Z -Message "..."` (Git, GitHub CLI et modèles d'export Godot requis, variable `GODOT` pour le chemin de Godot si besoin).

## Architecture

```
scripts/autoload/   réglages, réseau (ENet), audio, mise à jour
scripts/match/      arène, manches, mode battle royale (zone) et prop hunt
scripts/player/     mouvement, arme, animation (AnimationTree, IK), caméra, hitbox
scripts/ai/         IA des bots
scripts/maps/       terrain, bâtiments, props ; cartes dans map_dam.gd et map_pass.gd
scripts/items/      grenades, fumigènes, barricades, caisses
scripts/ui/         menu, HUD, armurerie, réticule
tools/              utilitaires de développement
```

Réseau : chaque client fait autorité sur son mouvement ; le serveur valide les tirs et gère PV, mises à terre et manches. Les autres joueurs sont affichés légèrement dans le passé, interpolés entre deux états réels. Les hitbox suivent le squelette animé.

## Crédits et licences

- **Raider** : *Sci-Fi Soldier / Futuristic Combat Trooper* par **ART_LOLL** (Sketchfab, CC BY 4.0), rigué avec Mixamo. Animations : Mixamo (Adobe).
- **Ferro** : *IZH-27* par **PeLmEsHkO** (Sketchfab, CC BY 4.0).
- **Personnages, monstres et fusils (Longshot, fusil à vapeur)** : modèles générés avec Meshy AI (`assets/characters/`, `assets/monsters/`, `assets/weapons/`).
- **Épaves et conteneur** (Sketchfab, CC BY 4.0) : *Crashed Abandoned Car*, *Abandoned Generic Sedan 1 et 2*, *Crashed Abandoned Truck* par **rashad-brahimli** ; *Freight shipping container - Rusted* par **sousinho**.
- **Poly Haven** (CC0) : textures, ciels, modèles scannés et kits de façades.
- **Audio** (OpenGameArt, CC0 sauf indication) : sons de tirs, d'armes, d'explosions, de pas, de voix et de vent de divers auteurs, *Boom Pack 1* par dklon (CC BY 3.0), musiques de TinyWorlds et HaelDB.

Ces crédits s'affichent aussi sur l'écran titre.
