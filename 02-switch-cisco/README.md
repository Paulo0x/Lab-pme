# Brique 02 — Switch Cisco Catalyst 2960C : remise à zéro, sécurisation, VLAN et SSH

> **Tuto pas à pas pour quelqu'un qui débute complètement.**  
> Chaque action a son numéro. Chaque capture est placée **juste sous l'action qu'elle montre**, avec  
> une légende qui dit **ce que tu dois voir** et **quoi faire si ce n'est pas pareil**.  
> Les vraies erreurs faites pendant le lab sont gardées, avec leur correction.

---

## 🧾 Fiche de la brique

| | |
| --- | --- |
| **Objectif** | Prendre un switch Cisco **d'occasion verrouillé**, le **remettre à zéro**, le **sécuriser**, créer les **VLAN** de l'entreprise, le relier au lab par un **trunk** et l'administrer en **SSH** |
| **Durée** | Environ **6 h** (en 3 séances), dont 1 h de dépannage |
| **Niveau** | Débutant, après les briques [00](../00-proxmox/) et [01](../01-pfsense/) |
| **Résultat** | `SW-CORE01` (10.10.99.1), 6 VLAN, ports répartis, trunk Gigabit vers pfSense, SSH v2 depuis `ADM-001`, NTP, bannière légale |
| **Brique précédente** | [01 · pfSense](../01-pfsense/) — **brique suivante** : [03 · Active Directory](../03-active-directory/) |

### Le matériel

| Élément | Ce que j'ai utilisé | Pourquoi |
| --- | --- | --- |
| Switch | **Cisco Catalyst WS-C2960C-8PC-L** (occasion) | Compact, silencieux (sans ventilateur), 8 ports PoE : parfait pour un lab et pour la pratique CCNA |
| Système du switch | IOS 15.0(2)SE5 (2013), licence **LAN Base** | Fait la commutation : VLAN, trunk, STP, SSH. **Ne route pas entre les VLAN** : c'est pfSense qui s'en charge |
| Poste d'admin | **ADM-001** (Acer, Windows 11 Pro) | Poste **dédié** à l'administration (recommandation ANSSI) |
| Câble console | **USB vers RJ45** | Les PC n'ont plus de port série : l'adaptateur crée un port COM virtuel |
| Câbles réseau | 2 câbles RJ45 (Cat 5e minimum, Cat 6 conseillé) | Un pour le trunk vers le serveur, un pour ADM-001 |

### Les logiciels (gratuits)

| Logiciel | Rôle | Où le trouver |
| --- | --- | --- |
| **PuTTY** | Parler au switch par le câble console (et en SSH) | `https://www.chiark.greenend.org.uk/~sgtatham/putty/` (site officiel, vérifier l'empreinte SHA-256) |
| **KeePassXC** | Coffre-fort à mots de passe | `https://keepassxc.org` (adresse tapée à la main) |
| **OpenSSH** | Client SSH intégré à Windows 11 | Déjà installé (`ssh` dans PowerShell) |

### Ce que tu sauras faire à la fin

- Se brancher en **console** sur un équipement réseau.
- **Récupérer** un switch Cisco dont on n'a pas le mot de passe, et l'effacer proprement.
- Faire l'**inventaire** d'un équipement avant sa mise en service.
- Sécuriser les accès : `enable secret`, compte nominatif, console protégée, SSH seul.
- Créer des **VLAN**, répartir les ports, éteindre ceux qui ne servent pas.
- Configurer un **trunk 802.1Q** et diagnostiquer un lien lent.
- Dépanner un PC en **169.254.x.x** et un SSH qui refuse de se connecter.

---

## 📖 Comment lire ce tuto

| Repère | Sens |
| --- | --- |
| 🎯 | **Le but** de l'étape, en une phrase |
| 💡 | **Pourquoi** on le fait, ou une explication pour comprendre |
| **3.2** | Une **action** à faire (étape 3, action 2). Ici, souvent : **une commande à taper** |
| 📸 | **La capture** de ce que tu dois voir, avec sa légende |
| ✅ | **Vérification** : comment savoir que c'est réussi |
| ❌ | **Si ça ne marche pas** (souvent l'erreur que j'ai vraiment eue) |
| 🏢 | **En entreprise**, ce qu'on ferait autrement |
| ⚠️ | Attention, piège ou risque |
| 📷 | **Capture manquante** : l'écran est décrit en texte |

**Taper les commandes Cisco** : chaque ligne d'un bloc se tape puis **Entrée**. Tu peux aussi
**coller tout un bloc** d'un coup dans PuTTY (clic droit = coller). Les lignes commençant par un
espace sont juste indentées pour la lecture : l'espace ne gêne pas.

---

## 🗂️ Sommaire

- [Partie 0 — Comprendre avant de commencer](#partie-0--comprendre-avant-de-commencer)
- [Partie 1 — Se brancher et reprendre la main](#partie-1--se-brancher-et-reprendre-la-main) (étapes 1 à 4)
- [Partie 2 — Sécuriser l'accès au switch](#partie-2--sécuriser-laccès-au-switch) (étapes 5 et 6)
- [Partie 3 — VLAN et ports](#partie-3--vlan-et-ports) (étapes 7 et 8)
- [Partie 4 — Adresse d'administration et SSH](#partie-4--adresse-dadministration-et-ssh) (étape 9)
- [Partie 5 — Le trunk vers le serveur](#partie-5--le-trunk-vers-le-serveur) (étapes 10 et 11)
- [Partie 6 — Le poste d'administration](#partie-6--le-poste-dadministration) (étapes 12 à 14)
- [Partie 7 — Heure et bannière légale](#partie-7--heure-et-bannière-légale) (étapes 15 et 16)
- [Partie 8 — Recette](#partie-8--recette)
- [Annexes](#annexes) : config complète, dépannage, antisèche, écarts, entretien, lexique

---

## Partie 0 — Comprendre avant de commencer

### 0.1 Le besoin

AEROTRANS a des VLAN sur son pare-feu pfSense (brique 01), mais tout passe encore par le réseau
virtuel de Proxmox. Il faut maintenant un **vrai switch physique** pour brancher les postes, le poste
d'administration et, plus tard, la borne Wi-Fi. Le switch a été acheté **d'occasion** : il contient
encore la configuration de son ancien propriétaire.

Le client veut :

- un switch **remis à zéro** : on ne garde jamais la config de quelqu'un d'autre ;
- un switch **sécurisé** : mots de passe forts, comptes nominatifs, pas de Telnet, pas d'interface web ;
- les **VLAN de l'entreprise** sur les bons ports, et les ports inutilisés **éteints** ;
- une **administration à distance chiffrée** (SSH), uniquement depuis le VLAN d'administration.

### 0.2 Le schéma de ce qu'on construit

```
   [ pve01 / Proxmox ]                         [ ADM-001 ] 10.10.99.10
      nic1 (vmbr1)                                  |
         |  trunk 802.1Q (VLAN 10,20,30,40,99)      |  VLAN 99 (access)
         |                                          |
      Gi0/1 ----------- [ SW-CORE01 ] ----------- Fa0/2
                         10.10.99.1 (VLAN 99)
                            |      |
                     Fa0/3-6       Fa0/1, Fa0/7-8, Gi0/2
                     postes        inutilisés : VLAN 999, éteints
                     (VLAN 20)
```

### 0.3 Les 5 notions à comprendre

**1. Les modes de la ligne de commande Cisco (CLI).** L'**invite** te dit où tu es :

| Invite | Mode | Ce qu'on peut faire | Pour y aller |
| --- | --- | --- | --- |
| `Switch>` | Utilisateur | Regarder un peu, rien modifier | (au démarrage) |
| `Switch#` | Privilégié (« enable ») | Tout voir, sauvegarder, redémarrer | `enable` |
| `Switch(config)#` | Configuration globale | Modifier la config | `configure terminal` |
| `Switch(config-if)#` | Configuration d'un port | Régler ce port | `interface fa0/2` |
| `Switch(config-line)#` | Configuration des accès (console, à distance) | Mot de passe, délai | `line console 0` |

`exit` remonte d'un niveau, `end` (ou **Ctrl + Z**) revient directement à `#`.

**2. running-config et startup-config.**

- La **running-config** est la configuration **en cours**, en mémoire vive (RAM). Toute commande
  tapée la modifie **immédiatement**, mais elle **disparaît** si on coupe le courant.
- La **startup-config** est le fichier `flash:config.text`, lu au démarrage.
- `copy running-config startup-config` copie l'une dans l'autre. **Oublier cette commande = tout
  perdre au prochain redémarrage.**
- Les **VLAN** sont rangés à part, dans `flash:vlan.dat`.

**3. Le VLAN.** Un VLAN découpe un switch en plusieurs switchs « virtuels » qui ne se parlent pas.
Les postes (VLAN 20) ne voient pas les serveurs (VLAN 10) directement : ils doivent passer par
pfSense, qui applique les règles du pare-feu.

**4. Port access ou trunk.**

- Un port **access** appartient à **un seul VLAN** : c'est là qu'on branche un PC.
- Un port **trunk** transporte **plusieurs VLAN** sur un même câble, en ajoutant à chaque trame une
  étiquette (802.1Q) qui dit de quel VLAN elle vient : c'est le lien vers le serveur ou un autre switch.

**5. Le STP (Spanning Tree).** Si deux câbles relient deux switchs, les trames tournent en rond à
l'infini (une « boucle ») et le réseau s'effondre en quelques secondes. Le STP détecte les boucles et
bloque les liens en trop. Contrepartie : un port met environ 30 secondes à s'activer. `portfast` saute
cette attente sur les ports où l'on branche un seul PC.

---

## Partie 1 — Se brancher et reprendre la main

### Étape 1 · Se brancher en console

🎯 Parler au switch **directement**, par le câble console, sans réseau.

**1.1** Branche le câble console entre un port **USB** d'ADM-001 et le port **CONSOLE** (bleu, RJ45)
à l'arrière du switch.

**1.2** Sur ADM-001, clic droit sur le bouton **Démarrer** > **Gestionnaire de périphériques**.
Déplie **Ports (COM et LPT)**.

<img src="captures/01-cable-console-usb-serial-com5.png" width="420">

> 📸 **Ce que tu dois voir** : sous **Ports (COM et LPT)**, une ligne **USB Serial Port (COM…)**.  
> Sur cette capture (prise sur mon PC principal), c'est **COM5** ; sur ADM-001, c'était **COM3**.  
> 💡 Chaque PC attribue son propre numéro : **note le tien**.  
> ❌ Triangle jaune sur la ligne : il manque le pilote du câble (Prolific ou FTDI selon le modèle).

**1.3** Ouvre **PuTTY**. Dans **Session** :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Connection type | **Serial** | On passe par le port série (le câble console) |
| Serial line | `COM3` (ton numéro) | |
| Speed | `9600` | La vitesse par défaut du port console de **tous** les équipements Cisco |

**1.4** Menu de gauche **Session > Logging** : coche **Printable output** et mets comme nom de
fichier `console-&Y&M&D-&T.log`.

💡 On garde une **trace écrite** de toute l'intervention (preuve + documentation). `&Y&M&D-&T` met la
date et l'heure dans le nom.

**1.5** Reviens sur **Session**, tape `SW-console-COM3` dans **Saved Sessions**, clique sur **Save**,
puis sur **Open**.

<img src="captures/03-putty-session-sauvegardee.png" width="520">

> 📸 **Ce que tu dois voir** : **PuTTY Configuration** avec **Serial** coché, **Serial line COM3**,  
> **Speed 9600**, et la session **SW-console-COM3** dans la liste.

**1.6** Dans la fenêtre noire qui s'ouvre, appuie sur **Entrée**.

<img src="captures/02-switch-demarrage-username-ancien-proprietaire.png" width="620">

> 📸 **Ce que j'ai vu** : les messages de démarrage du switch, une bannière de l'ancien propriétaire  
> (« Acces reglemente », nom d'entreprise masqué), puis **User Access Verification** et  
> **Username:**. On ne connaît pas ce compte : il faut **reprendre la main** (étape 2).

✅ **Vérification** : le switch répond dans PuTTY.
❌ **Écran noir qui ne réagit pas** : mauvais port COM, ou vitesse différente de 9600.
**Caractères bizarres** : mauvaise vitesse.

---

### Étape 2 · Reprendre la main : récupération du mot de passe

🎯 Démarrer le switch **sans** lire la config de l'ancien propriétaire.

💡 **Pourquoi ça marche** : au lieu de lancer IOS (qui lirait l'ancienne config et son mot de passe),
le switch s'arrête dans son **mini-système de démarrage** (le *bootloader*), qui donne accès aux
fichiers de la mémoire flash. Il faut un **accès physique** au switch : c'est pour ça qu'en entreprise
les switchs sont dans des **baies fermées à clé**.

**2.1** **Débranche** l'alimentation du switch.

**2.2** **Maintiens le bouton MODE** (face avant, à gauche) enfoncé et **rebranche** l'alimentation.

**2.3** Garde le doigt dessus environ **15 secondes**, jusqu'à ce que le voyant **SYST** passe au
**vert fixe**, puis relâche.

> 📷 **Capture manquante** : photo de la face avant (bouton MODE et voyant SYST).

<img src="captures/04-bootloader-invite-switch.png" width="620">

> 📸 **Ce que tu dois voir** : « Base ethernet MAC Address » (masquée), **The password-recovery  
> mechanism is enabled**, « The system has been interrupted prior to initializing the flash  
> filesystem », les commandes proposées `flash_init` et `boot`, puis l'invite **`switch:`**.  
> 💡 **`switch:`** en minuscules = tu es dans le bootloader, pas dans IOS.

💡 « *password-recovery mechanism is enabled* » : l'ancien propriétaire n'avait pas désactivé cette
récupération. En environnement sensible, on peut la désactiver (`no service password-recovery`).

💡 **Question classique de certification** : sur un **routeur** Cisco, la récupération passe par le
**registre de configuration** (`0x2142`) ; sur un **switch** Catalyst, par le **bouton MODE**.

❌ **Le switch redemande `Username:`** : le bouton a été relâché trop tôt. Recommence.

---

### Étape 3 · Effacer la config de l'ancien propriétaire

🎯 Supprimer **tous** les fichiers de l'ancien propriétaire, mais **garder le système**.

💡 **Pourquoi tout effacer ?** Pour repartir propre, et surtout pour la **sécurité** : une config
inconnue peut cacher un compte de l'ancien propriétaire, un accès à distance, une redirection de trafic.

**3.1** « Monte » la mémoire flash (comme brancher une clé USB), puis liste son contenu :

```
flash_init
dir flash:
```

<img src="captures/05-dir-flash-avant-effacement.png" width="560">

> 📸 **Ce que tu dois voir** : « Initializing Flash... done », puis **Directory of flash:/** avec  
> 6 éléments : `multiple-fs`, `vlan.dat`, `config.text`, `express_setup.debug`, le dossier  
> `c2960c405-universalk9-mz.150-2.SE5` et `private-config.text`.

**3.2** Décide quoi garder :

| Fichier trouvé | Rôle | Décision |
| --- | --- | --- |
| `multiple-fs` | Fichier technique d'IOS | **Garder** |
| `c2960c405-universalk9-mz.150-2.SE5` (dossier, `drwx`) | **IOS, le système** | ⚠️ **Ne jamais toucher** : sans lui, le switch ne démarre plus |
| `config.text` | Config de démarrage de l'ancien propriétaire | Supprimer |
| `private-config.text` | Partie sensible de la config (clés SSH, secrets) | Supprimer — **le plus important**, souvent oublié |
| `vlan.dat` | VLAN de l'ancien propriétaire | Supprimer — sinon les anciens VLAN reviennent |
| `express_setup.debug` | Journal de l'assistant web « Express Setup » | Supprimer |

**3.3** Supprime les 4 fichiers. Chaque `delete` demande une confirmation : tape `y`.

```
delete flash:config.text
delete flash:private-config.text
delete flash:vlan.dat
delete flash:express_setup.debug
dir flash:
```

<img src="captures/06-suppression-4-fichiers.png" width="620">

> 📸 **Ce que tu dois voir** : pour chaque fichier, `Are you sure you want to delete … (y/n)?y` puis  
> `File "flash:…" deleted`. Le dernier `dir flash:` ne montre plus que **`multiple-fs`** et le  
> **dossier IOS**.  
> ❌ Sur la capture, un `Unknown cmd: dir` : faute de frappe (ou caractère invisible). Le bootloader ne  
> corrige rien : **retape la commande proprement**.

**3.4** Démarre le système :

```
boot
```

**3.5** Au démarrage, le switch propose un assistant :
`Would you like to enter the initial configuration dialog? [yes/no]:` → tape **`no`**.

<img src="captures/07-dialogue-config-initiale-no.png" width="620">

> 📸 **Ce que tu dois voir** : **System Configuration Dialog**, l'avertissement « Enable secret  
> warning », ta réponse **`no`**, puis l'invite **`Switch>`**.  
> 💡 L'assistant pose des questions une par une ; en entreprise, on tape la config **soi-même** pour  
> savoir exactement ce qu'on met.

**3.6** Vérifie que tout a bien été effacé :

```
enable
show startup-config
show vlan brief
```

<img src="captures/08-verif-startup-vide-vlan-usine.png" width="620">

> 📸 **Ce que tu dois voir** :
>
> | Résultat | Ce que ça prouve |
> | --- | --- |
> | `enable` ne demande **aucun** mot de passe | L'ancien mot de passe a disparu |
> | **`startup-config is not present`** | `config.text` est bien supprimé |
> | Seulement **VLAN 1** (tous les ports) et **1002 à 1005** | `vlan.dat` est bien supprimé (les VLAN 1002-1005 existent sur tous les Cisco et ne se suppriment pas) |

✅ **Vérification** : le switch est **remis à zéro**.

---

### Étape 4 · Fiche d'identité du switch (inventaire)

🎯 Connaître **précisément** l'équipement avant de le mettre en service.

💡 En entreprise, on fait l'inventaire d'un équipement **avant** de le mettre en service : modèle,
version, état de santé, numéro de série (pour la garantie et le parc).

**4.1** Tape `show version` (appuie sur **Espace** quand `--More--` s'affiche).

<img src="captures/09-show-version-1.png" width="620">

> 📸 **Ce que tu vois (début)** : **Cisco IOS Software, C2960C Software (C2960c405-UNIVERSALK9-M),  
> Version 15.0(2)SE5**, compilé le **25-Oct-13**, « Switch uptime », **License Level: lanbase**,  
> **License Type: Permanent**, **cisco WS-C2960C-8PC-L … with 131072K bytes of memory**,  
> **8 FastEthernet interfaces**, **2 Gigabit Ethernet interfaces**.

<img src="captures/10-show-version-2.png" width="620">

> 📸 **Ce que tu vois (fin)** : les numéros de série, la MAC et le code CLEI (**masqués**), le modèle  
> **WS-C2960C-8PC-L**, la version **15.0(2)SE5**, et **Configuration register is 0xF**.

**4.2** Tape les autres commandes d'inventaire, une par une :

```
show inventory
show env all
show power inline
show interfaces status
```

<img src="captures/11-show-inventory.png" width="520">

> 📸 **show inventory** : **PID: WS-C2960C-8PC-L, VID: V01, SN:** (masqué). C'est ce numéro qu'on  
> saisira dans GLPI.

<img src="captures/12-show-env-all.png" width="520">

> 📸 **show env all** : **SYSTEM TEMPERATURE is OK**, **32 Degree Celsius**, état **GREEN** (alerte  
> jaune à 76 °C, rouge à 86 °C), alimentation **Good**.

<img src="captures/13-show-power-inline.png" width="520">

> 📸 **show power inline** : **Available: 124.0 (w)**, Used 0, et **15.4 W maximum** par port  
> (norme PoE 802.3af). Assez pour une borne Wi-Fi (environ 10 W).

<img src="captures/14-show-interfaces-status.png" width="560">

> 📸 **show interfaces status** : les ports **Fa0/1 à Fa0/8** (10/100BaseTX) et **Gi0/1, Gi0/2**  
> (**Not Present**), tous `notconnect` dans le **VLAN 1**.  
> 💡 *Not Present* = les emplacements **SFP** (fibre) sont vides ; ce sont des ports « combo » :  
> la **prise cuivre RJ45** reste utilisable.

**4.3** Recopie la fiche d'identité :

| Élément | Valeur relevée | Interprétation |
| --- | --- | --- |
| Modèle | WS-C2960C-8PC-L | 8 ports FastEthernet PoE + 2 uplinks Gigabit |
| IOS | 15.0(2)SE5, compilé en octobre 2013 | Ancien : vérifier s'il existe une version plus récente |
| Licence | LAN Base, permanente | Commutation seule, pas de routage entre VLAN |
| Mémoire | 128 Mo | Normal pour ce modèle |
| Température | 32 °C, GREEN | En bonne santé |
| Alimentation | Good | OK |
| Budget PoE | 124 W, 15,4 W max par port | Suffisant pour la future borne Wi-Fi |
| Config register | 0xF | Valeur normale sur ce modèle |
| Horloge | 30 mars 2011 | Pas de pile : il faudra le NTP (étape 15) |
| N° de série, MAC, CLEI | relevés | **Masqués** sur toutes les captures publiées. À saisir dans GLPI |

---

## Partie 2 — Sécuriser l'accès au switch

### Étape 5 · Préparer les mots de passe dans KeePassXC

🎯 Créer deux mots de passe **forts**, **générés**, et rangés dans un **coffre-fort**.

💡 En entreprise, on n'écrit **jamais** un mot de passe sur un papier, dans un fichier texte ou dans
un mail.

**5.1** Installe **KeePassXC** depuis `https://keepassxc.org` (adresse tapée à la main, pas via un
moteur de recherche : les faux sites existent).

**5.2** **Base de données** > **Nouvelle base de données** :
- nom `AEROTRANS-admin` ;
- description : *Coffre des comptes d'administration du lab AEROTRANS. Accès réservé à
  l'administrateur.* ;
- un **mot de passe maître** long, jamais écrit nulle part.

**5.3** Clic droit sur **Racine** > **Nouveau groupe** : `Reseau` (notes : *Switch, pare-feu, borne
Wi-Fi*).

**5.4** Dans le groupe **Reseau**, **Entrées** > **Nouvelle entrée** :
- Titre : `SW-CORE01 - enable secret` ;
- clique sur l'**icône dé** à droite du mot de passe pour ouvrir le **générateur**.

**5.5** Dans le générateur : **Longueur 24**, coche **A-Z**, **a-z**, **0-9**, **décoche** les
symboles `/ * + & …`, puis **Appliquer le mot de passe**.

<img src="captures/15-keepass-generateur-24-caracteres.jpg" width="560">

> 📸 **Ce que tu dois voir** : **Générer un mot de passe**, mot de passe masqué par des points,  
> **Qualité du mot de passe : Excellent**, **Caractères : 24**, **Entropie : 127.54 bits**, et les  
> 3 types A-Z, a-z, 0-9 activés (en vert).

💡 **Pourquoi sans symboles ?** Sur la CLI Cisco, `?` affiche l'aide au lieu de s'écrire, et certains
caractères posent problème au collage. 24 caractères alphanumériques = environ 128 bits d'entropie :
impossible à deviner.

**5.6** Clique sur **OK** pour enregistrer l'entrée.

<img src="captures/16-keepass-entree-enable-secret.jpg" width="560">

> 📸 **Ce que tu dois voir** : **Reseau › Ajouter une entrée**, Titre **SW-CORE01 - enable secret**,  
> mot de passe en points.

**5.7** Recommence pour l'entrée `SW-CORE01 - compte admin`, avec **Nom d'utilisateur**
`adm.paulo.rosa` et un mot de passe **généré pareil**.

<img src="captures/17-keepass-entree-compte-admin.jpg" width="560">

> 📸 **Ce que tu dois voir** : Titre **SW-CORE01 - compte admin**, utilisateur **adm.paulo.rosa**.

**5.8** Enregistre la base : **Ctrl + S**.

<img src="captures/18-keepass-groupe-reseau-2-entrees.jpg" width="560">

> 📸 **Ce que tu dois voir** : le groupe **Reseau** avec **2 entrées** SW-CORE01.

⚠️ **Avant de coller un mot de passe dans PuTTY** :
1. **coupe le journal** : clic droit sur la barre de titre de PuTTY > **Change Settings** >
   **Logging** > **None** > **Apply**. Sinon le mot de passe finit **en clair** dans le fichier `.log` ;
2. **aucune capture d'écran** pendant ce temps ;
3. rallume le journal après.

---

### Étape 6 · Nom, enable secret, compte admin et console

🎯 Donner un nom au switch et **protéger tous ses accès**.

**6.1** Entre en configuration et donne un nom :

```
enable
configure terminal
hostname SW-CORE01
no ip domain-lookup
```

| Commande | Ce qu'elle fait | Pourquoi |
| --- | --- | --- |
| `hostname SW-CORE01` | Nomme le switch | Convention du lab : TYPE-RÔLE + numéro (comme `SRV-AD01`). L'invite affiche le nom : on sait toujours sur quel équipement on tape |
| `no ip domain-lookup` | Désactive la recherche DNS des commandes inconnues | Sans ça, une faute de frappe bloque la console ~30 s pendant que le switch cherche un « nom de machine » |

**6.2** Mets le **mot de passe du mode `#`**, haché en **scrypt**. Copie le mot de passe dans
KeePassXC (**Ctrl + C** sur l'entrée), puis tape la commande et **colle** à la fin (clic droit) :

```
enable algorithm-type scrypt secret <colle ici le mot de passe>
```

<img src="captures/19-enable-secret-scrypt-accepte-MASQUE.png" width="620">

> 📸 **Ce que tu dois voir** : l'invite devient **`SW-CORE01(config)#`** (le nom est appliqué), et la  
> commande `…rithm-type scrypt secret` est **acceptée** sans message d'erreur (le mot de passe est  
> masqué sur la capture).  
> 💡 Le `$` au début de la ligne : la commande était trop longue pour l'écran, PuTTY l'a décalée.

💡 **`enable password` ou `enable secret` ?** (question classique d'entretien)

| Commande | Stockage dans la config | Verdict |
| --- | --- | --- |
| `enable password` | En clair (ou type 7, réversible en 2 secondes) | ❌ Jamais |
| `enable secret` | Haché : type 5 (MD5), 8 (PBKDF2) ou **9 (scrypt)** | ✅ Toujours, le plus fort possible |

IOS 15.0(2)SE5 accepte `algorithm-type scrypt`. ❌ Sur un IOS plus ancien qui répond
`% Invalid input`, utilise `enable secret` seul (type 5).

**6.3** Crée le **compte admin nominatif** (même méthode : copier dans KeePassXC, coller à la fin) :

```
username adm.paulo.rosa privilege 15 algorithm-type scrypt secret <colle ici le mot de passe>
```

<img src="captures/20-username-adm-scrypt-mdp-hors-ecran.png" width="620">

> 📸 **Ce que tu vois** : la ligne `username adm.paulo.rosa privilege 15 algorithm-type scrypt s$` :  
> le mot de passe est **hors de l'écran**, coupé par PuTTY.

💡 **Compte nominatif** = on sait **qui** a fait quoi (le journal écrira
`Configured from console by adm.paulo.rosa`). **Privilège 15** = arrive directement en mode `#`.

**6.4** Protège la console et sauvegarde :

```
service password-encryption
line console 0
 login local
 exec-timeout 10 0
 logging synchronous
end
copy running-config startup-config
```

(Appuie sur **Entrée** quand on te demande `Destination filename [startup-config]?`.)

| Commande | Ce qu'elle fait | Pourquoi |
| --- | --- | --- |
| `service password-encryption` | Masque les mots de passe restés en clair | Filet de sécurité (chiffrement faible, type 7) ; nos secrets sont déjà en scrypt |
| `line console 0` + `login local` | La console demande `Username` / `Password` | Plus d'accès libre au port console |
| `exec-timeout 10 0` | Déconnexion après 10 min d'inactivité | Évite une session admin oubliée ouverte |
| `logging synchronous` | Les messages du switch n'interrompent plus la frappe | Confort, et moins d'erreurs |
| `copy running-config startup-config` | **Sauvegarde** | Sinon tout est perdu au redémarrage |

<img src="captures/21-console-login-local-sauvegarde.png" width="620">

> 📸 **Ce que tu dois voir** : les commandes acceptées, le message **`%SYS-5-CONFIG_I: Configured from  
> console by console`**, puis `Building configuration...` et **`[OK]`** : c'est sauvegardé.

**6.5** **Teste** la console : tape `exit`, puis **Entrée**. Le switch demande `Username:` :
`adm.paulo.rosa`, puis le mot de passe **collé** (rien ne s'affiche quand on tape un mot de passe :
c'est normal).

<img src="captures/22-test-connexion-compte-admin.png" width="420">

> 📸 **Ce que tu dois voir** : **Username: adm.paulo.rosa**, **Password:**, puis directement  
> **`SW-CORE01#`** (mode privilégié, grâce au privilège 15).

❌ **`% Password: timeout expired!`** : tu as mis plus de 30 secondes à saisir le mot de passe.
Recommence en ayant **copié le mot de passe dans KeePassXC avant** de taper le nom d'utilisateur.

✅ **Vérification** : la console demande un compte, et `adm.paulo.rosa` arrive en `#`.

---

## Partie 3 — VLAN et ports

### Étape 7 · Créer les VLAN de l'entreprise

🎯 Créer les 6 VLAN du [plan d'adressage](../docs/plan-adressage.md).

**7.1** Tape :

```
configure terminal
vlan 10
 name SERVEURS
vlan 20
 name POSTES
vlan 30
 name WIFI_SALARIES
vlan 40
 name WIFI_INVITES
vlan 99
 name ADMINISTRATION
vlan 999
 name PARKING
end
show vlan brief
```

💡 Noms **sans accent ni espace** (les équipements réseau les gèrent mal).

💡 **Le VLAN 999 « PARKING »** : un VLAN qui ne mène **nulle part** (aucune interface sur pfSense).
Les ports inutilisés y sont placés **et éteints**. Quelqu'un qui branche un PC sur une prise libre
n'arrive sur rien. Recommandation ANSSI et Cisco : **ne jamais laisser des ports dans le VLAN 1**.

<img src="captures/23-vlan-crees-show-vlan-brief.png" width="560">

> 📸 **Ce que tu dois voir** : dans `show vlan brief`, les VLAN **10 SERVEURS, 20 POSTES,  
> 30 WIFI_SALARIES, 40 WIFI_INVITES, 99 ADMINISTRATION, 999 PARKING**, tous **active**. Les ports sont  
> encore tous dans le VLAN 1 : normal, on les range à l'étape 8.  
> ❌ Sur la capture, `name POSTES*` (faute de frappe) : il suffit de retaper `vlan 20` puis  
> `name POSTES`, le nouveau nom remplace l'ancien.

✅ **Vérification** : 6 VLAN avec les bons noms.

---

### Étape 8 · Répartir les ports

🎯 Mettre chaque port dans **son** VLAN, et **éteindre** ceux qui ne servent pas.

**8.1** Écris d'abord le **plan des ports** (on ne configure jamais « au feeling ») :

| Port | Branché | Mode | VLAN | État |
| --- | --- | --- | --- | --- |
| Gi0/1 | Serveur Proxmox (pfSense) | trunk | 10, 20, 30, 40, 99 | Étape 10 |
| Fa0/1 | Future borne Wi-Fi | access (provisoire) | 999 | Éteint |
| Fa0/2 | ADM-001 | access | 99 | Actif |
| Fa0/3 – Fa0/6 | Postes de travail | access | 20 | Actifs |
| Fa0/7, Fa0/8, Gi0/2 | — | access | 999 | Éteints |

**8.2** Le port du poste d'administration :

```
configure terminal
interface fa0/2
 description ADM-001 poste d'administration
 switchport mode access
 switchport access vlan 99
 spanning-tree portfast
 spanning-tree bpduguard enable
 exit
```

<img src="captures/24-port-fa0-2-adm-vlan99.png" width="620">

> 📸 **Ce que tu dois voir** : les commandes acceptées, et un **`%Warning: portfast should only be  
> enabled on ports connected to a single host`**.  
> 💡 **Ce n'est pas une erreur** : c'est un rappel. `bpduguard` est justement là pour couvrir ce risque.

**8.3** Les 4 ports des postes, en une seule fois avec `interface range` :

```
interface range fa0/3 - 6
 description Postes de travail
 switchport mode access
 switchport access vlan 20
 spanning-tree portfast
 spanning-tree bpduguard enable
 exit
```

<img src="captures/25-ports-fa0-3-6-postes-vlan20.png" width="620">

> 📸 **Ce que tu dois voir** : l'invite `SW-CORE01(config-if-range)#` (plusieurs ports à la fois), le  
> même avertissement portfast, puis « Portfast will be configured in 4 interfaces ».

**8.4** Les ports inutilisés : parking **et** éteints :

```
interface range fa0/1 , fa0/7 - 8 , gi0/2
 description NON UTILISE - parking
 switchport mode access
 switchport access vlan 999
 shutdown
end
```

<img src="captures/26-ports-parking-shutdown.png" width="620">

> 📸 **Ce que tu dois voir** : les 5 commandes acceptées sur `interface range fa0/1 , fa0/7 - 8 , gi0/2`.  
> 💡 Attention aux espaces autour des virgules et du tiret : `fa0/7 - 8`.

| Commande | Pourquoi |
| --- | --- |
| `description` | Étiquette visible dans `show interfaces status` : le technicien suivant sait ce qui est branché |
| `switchport mode access` | Le port reste dans **un seul VLAN** et ne peut pas devenir trunk tout seul (protection contre le « VLAN hopping ») |
| `switchport access vlan 20` | Range le port dans le VLAN |
| `spanning-tree portfast` | Le port s'active tout de suite (pas d'attente STP de ~30 s) |
| `spanning-tree bpduguard enable` | Si un **switch** est branché sur une prise prévue pour un PC, le port se coupe (`err-disabled`) : protection contre les boucles |
| `shutdown` | Éteint le port |

**8.5** Vérifie :

```
show interfaces status
show vlan brief
```

<img src="captures/27-verif-interfaces-status-vlan-brief.png" width="620">

> 📸 **Ce que tu dois voir** :  
> - **Fa0/1, Fa0/7, Fa0/8, Gi0/2** : « NON UTILISE - park », **disabled**, VLAN **999** ;  
> - **Fa0/2** : « ADM-001 poste d'ad », VLAN **99** ;  
> - **Fa0/3 à Fa0/6** : « Postes de travail », VLAN **20** ;  
> - **Gi0/1** : seul encore en VLAN **1** (il deviendra le trunk) ;  
> - dans `show vlan brief` : 20 POSTES = Fa0/3-6, 99 = Fa0/2, 999 PARKING = Fa0/1, Fa0/7, Fa0/8, Gi0/2.

**8.6** Sauvegarde : `copy running-config startup-config`.

❌ **Un port en `err-disabled`** : bpduguard a détecté un switch. Débranche l'équipement, puis sur le
port : `shutdown` puis `no shutdown`.

---

## Partie 4 — Adresse d'administration et SSH

### Étape 9 · Donner une adresse au switch et activer le SSH

🎯 Pouvoir administrer le switch **à distance**, **chiffré**, **depuis le VLAN 99 seulement**.

💡 Un switch n'a pas d'adresse IP sur ses ports : il en reçoit une sur une **interface virtuelle de
VLAN** (SVI). On la met dans le **VLAN 99 (Administration)**.

**9.1** L'adresse d'administration et la passerelle :

```
configure terminal
interface vlan 99
 description Administration SW-CORE01
 ip address 10.10.99.1 255.255.255.0
 no shutdown
 exit
interface vlan 1
 shutdown
 exit
ip default-gateway 10.10.99.254
```

<img src="captures/28-svi-vlan99-passerelle.png" width="620">

> 📸 **Ce que tu dois voir** : les commandes acceptées, et le message  
> `%LINEPROTO-5-UPDOWN: Line protocol on Interface Vlan99, changed state to down`.  
> 💡 **down** est normal pour l'instant : voir 9.5.

| Commande | Pourquoi |
| --- | --- |
| `interface vlan 99` + `ip address 10.10.99.1` | Adresse d'administration (plage fixe `.1`-`.99` du plan d'adressage) |
| `interface vlan 1` + `shutdown` | Le VLAN 1 ne sert à rien ici : on éteint son interface |
| `ip default-gateway 10.10.99.254` | pfSense : permet au switch de répondre aux machines des autres VLAN |

**9.2** La clé de chiffrement et le SSH :

```
ip domain-name lab.home.arpa
crypto key generate rsa modulus 2048
ip ssh version 2
ip ssh time-out 60
ip ssh authentication-retries 3
```

<img src="captures/29-cle-rsa-2048-ssh-v2.png" width="620">

> 📸 **Ce que tu dois voir** : « The name for the keys will be: **SW-CORE01.lab.home.arpa** »,  
> « The key modulus size is **2048** bits », « Generating 2048 bit RSA keys, keys will be  
> **non-exportable**... **[OK] (elapsed time was 26 seconds)** », puis **`%SSH-5-ENABLED: SSH 1.99  
> has been enabled`**.

| Commande | Pourquoi |
| --- | --- |
| `ip domain-name lab.home.arpa` | Obligatoire pour générer la clé SSH. On reprend le domaine du lab |
| `crypto key generate rsa modulus 2048` | Crée la paire de clés qui chiffre le SSH. 2048 bits = minimum sérieux aujourd'hui (26 s de calcul sur ce switch) |
| `ip ssh version 2` | « SSH 1.99 » = compatible v1 **et** v2. La v1 est cassée : on force la **v2** |
| `ip ssh time-out 60` / `authentication-retries 3` | 60 s pour se connecter, 3 essais : freine les attaques par force brute |

**9.3** Les accès à distance (VTY) : SSH seulement, et on coupe l'interface web :

```
line vty 0 15
 login local
 transport input ssh
 exec-timeout 10 0
 exit
no ip http server
no ip http secure-server
end
copy running-config startup-config
```

<img src="captures/30-vty-ssh-only-http-off-sauvegarde.png" width="620">

> 📸 **Ce que tu dois voir** : les commandes acceptées, `Configured from console by adm.paulo.rosa`,  
> puis la sauvegarde **[OK]**.

| Commande | Pourquoi |
| --- | --- |
| `line vty 0 15` | Les 16 « lignes » de connexion à distance |
| `login local` | Connexion avec le compte `adm.paulo.rosa` |
| `transport input ssh` | **SSH seulement, pas Telnet** (Telnet envoie tout en clair, mots de passe compris) |
| `no ip http server` / `secure-server` | Coupe l'interface web (celle de l'Express Setup) : une porte d'entrée en moins |

**9.4** Vérifie :

```
show ip interface brief
show ip ssh
```

<img src="captures/31-verif-ip-interface-brief-show-ip-ssh.png" width="620">

> 📸 **Ce que tu dois voir** :  
> - `Vlan1` **administratively down** (éteinte volontairement) ;  
> - **`Vlan99  10.10.99.1  YES manual  up  down`** ;  
> - **`SSH Enabled - version 2.0`**, **`Authentication timeout: 60 secs; Authentication retries: 3`** ;  
> - la **clé publique** `ssh-rsa AAAA…`.

💡 **9.5 Pourquoi Vlan99 est « up / down » ?** Une SVI ne passe en `up/up` que si **au moins un port
actif** appartient à son VLAN (ou si un trunk le transporte). Rien n'est encore branché sur Fa0/2 et
le trunk vient à l'étape 10 : **c'est normal**.

💡 **La clé publique affichée** n'est pas un secret : c'est la partie envoyée à tous ceux qui se
connectent. La clé **privée** reste sur le switch, et elle est `non-exportable`.

✅ **Vérification** : SSH v2 actif, adresse 10.10.99.1 posée.

---

## Partie 5 — Le trunk vers le serveur

### Étape 10 · Configurer le trunk

🎯 Relier le switch au serveur Proxmox par **un seul câble** qui transporte **tous les VLAN**.

**10.1** **L'état des lieux d'abord** (on ne modifie jamais un réseau sans l'avoir regardé) : dans
Proxmox, **pve01** > **Système** > **Réseau**.

<img src="captures/32-proxmox-reseau-vmbr1-nic1.png" width="720">

> 📸 **Ce que tu dois voir** : **vmbr0** sur **nic0** avec `192.168.1.210` (le réseau de la box, on  
> n'y touche pas) et **vmbr1** sur **nic1**, **Gère les VLAN : Oui** (créé à la brique 01). À gauche,  
> les VM déjà en place : 100 (FW01), 200 (SRV-AD01), 210 (SRV-GLPI), 300 (PC-001)…

**10.2** Double-clique sur **vmbr1** pour vérifier ses réglages (puis **Annuler**, sans rien changer).

<img src="captures/33-proxmox-vmbr1-gere-les-vlan.png" width="560">

> 📸 **Ce que tu dois voir** : **Éditer : Linux Bridge**, Nom **vmbr1**, **IPv4/CIDR vide**,  
> **Gère les VLAN** ✅, **Ports du pont : nic1**, commentaire **LAN entreprise - trunk vers…**,  
> **Identifiants de VLAN : 2-4094**.  
> 💡 Les VM sont déjà sur vmbr1 avec leur étiquette (« tag 10 », « tag 20 »…). Un pont « VLAN aware »  
> transmet ces étiquettes telles quelles sur `nic1` : **côté Proxmox, il n'y a rien à modifier**.

**10.3** Repère la **prise de nic1** sur le mini PC.

<img src="captures/34-minipc-prises-reseau.jpg" width="520">

> 📸 **Ce que tu vois** : l'arrière du mini PC avec ses **deux prises réseau**. Celle de **gauche**  
> (câble blanc, voyants allumés) = **nic0**, reliée à la box. Celle de **droite**, libre = **nic1**.

**10.4** Configure le port **Gi0/1** du switch :

```
configure terminal
interface gi0/1
 description TRUNK vers PVE01 nic1 (vmbr1)
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,30,40,99
 switchport mode trunk
 switchport nonegotiate
 no shutdown
end
copy running-config startup-config
```

<img src="captures/35-trunk-gi0-1-config.png" width="620">

> 📸 **Ce que tu dois voir** : les 7 lignes acceptées dans `SW-CORE01(config-if)#`, puis  
> `%SYS-5-CONFIG_I: Configured from console by adm.paulo.rosa on console`.

| Commande | Pourquoi |
| --- | --- |
| `switchport mode trunk` | Le port transporte plusieurs VLAN, chaque trame étiquetée 802.1Q (le 2960 ne connaît que 802.1Q : pas besoin de `encapsulation`) |
| `allowed vlan 10,20,30,40,99` | Seuls les VLAN de l'entreprise passent : moindre privilège |
| `native vlan 999` | Le VLAN natif passe **sans étiquette**. Laissé sur le VLAN 1, il permet l'attaque par « double étiquetage » (*double tagging*). On le place sur le VLAN parking |
| `nonegotiate` | Coupe DTP, le protocole qui négocie automatiquement le mode trunk : une porte d'attaque de moins |

**10.5** Branche un câble entre le port **Gi0/1** du switch et la **prise nic1** du mini PC.

**10.6** Vérifie :

```
show interfaces status
show interfaces trunk
show ip interface brief
ping 10.10.99.254
```

<img src="captures/36-verif-trunk-vlan99-up-ping-pfsense.png" width="620">

> 📸 **Ce que tu dois voir** :  
> - `show interfaces status` : **Gi0/1 « TRUNK vers PVE01 n » connected trunk** ;  
> - `show interfaces trunk` : Gi0/1 **on**, **802.1q**, **trunking**, native vlan **999**, VLAN  
>   **10,20,30,40,99** autorisés, actifs et en *forwarding* ;  
> - `show ip interface brief` : **Vlan99 10.10.99.1 … up up** (le trunk apporte le VLAN 99) ;  
> - `ping 10.10.99.254` : **`!!!!!`**, **Success rate is 100 percent (5/5)** : **pfSense répond au  
>   switch à travers le trunk** ✅.
>
> ⚠️ Mais regarde la vitesse de Gi0/1 : **`a-100`** (100 Mb/s) au lieu de 1000. → Étape 11.

---

### Étape 11 · Dépannage : le trunk bloqué à 100 Mb/s

❌ **Constat** : Gi0/1 négocie à **100 Mb/s** (`a-100`) alors que le switch et le mini PC savent faire
**1 Gb/s**, avec un câble annoncé Cat 5e.

💡 **Ce qu'il faut savoir** : le Gigabit a besoin des **4 paires** de fils du câble ; s'il en manque
une, les cartes se replient **automatiquement** sur 100 Mb/s (qui n'utilise que 2 paires).

**Les pistes** : câble abîmé ou mal serti, connecteur mal enfoncé, carte réseau du mini PC,
économie d'énergie (EEE).

**11.1** **Diagnostic par échange** (la méthode du technicien quand on n'a pas de testeur de câble) :
**intervertis** le câble du trunk et celui d'ADM-001.

💡 Le port Fa0/2 d'ADM-001 est en FastEthernet : il plafonne à 100 Mb/s et n'utilise que 2 paires.
Un câble fatigué y passe inaperçu.

**11.2** Revérifie avec `show interfaces status`.

<img src="captures/48-trunk-gi0-1-a-1000-apres-echange-cable.png" width="620">

> 📸 **Ce que tu dois voir** : **Gi0/1 TRUNK vers PVE01 connected trunk a-full a-1000** ✅.  
> Et Fa0/2 (ADM-001) en `a-100`, normal pour ce port.

✅ **Conclusion** : **c'était le câble**. Il reste sur le poste d'admin (100 Mb/s suffit) et sera
remplacé.
🏢 En entreprise, il serait passé au **testeur** puis jeté, et les cordons seraient étiquetés.

---

## Partie 6 — Le poste d'administration

### Étape 12 · Brancher ADM-001 (et le piège du DHCP)

🎯 Relier le poste d'administration au **VLAN 99**.

**12.1** Branche ADM-001 sur le port **Fa0/2**, puis dans PowerShell : `ipconfig`.

<img src="captures/37-adm001-apipa-169-254-pas-de-dhcp.png" width="560">

> 📸 **❌ Ce que j'ai eu** : sur la **Carte Ethernet Ethernet**, **Adresse d'autoconfiguration IPv4 :  
> 169.254.21.244**, masque 255.255.0.0, **pas de passerelle**. (Le Wi-Fi, lui, a 192.168.1.110 par la  
> box.)  
> 💡 **Une adresse en 169.254.x.x (APIPA) = Windows n'a reçu de réponse d'aucun serveur DHCP** et  
> s'est donné une adresse de secours. Le lien, lui, fonctionne (sinon : « Média déconnecté »).

**12.2** **Diagnostic, de bas en haut.** Le switch voit-il le PC ? Sur le switch :

```
show interfaces status
show mac address-table vlan 99
```

<img src="captures/38-fa0-2-connected-vlan99.png" width="560">

> 📸 **Ce que tu dois voir** : **Fa0/2 ADM-001 poste d'ad connected 99 a-full a-100**. Le câble et le  
> port sont bons, dans le bon VLAN. ✅

<img src="captures/39-table-mac-vlan99-acer-fa0-2.png" width="420">

> 📸 **Ce que tu dois voir** : en bas de la table, une ligne **99 [adresse masquée] DYNAMIC Fa0/2** :  
> le switch a **appris** l'adresse MAC de l'Acer sur Fa0/2. ✅ (Les lignes « All … STATIC CPU » sont  
> des adresses internes du switch.)  
> 💡 La table MAC est l'**annuaire** du switch : quelle machine derrière quel port. Une entrée  
> inutilisée disparaît au bout de 5 minutes.

**12.3** Le serveur DHCP répond-il ? Dans pfSense : **Services** > **DHCP Server**.

<img src="captures/40-pfsense-dhcp-relay-actif.png" width="620">

> 📸 **Ce que tu vois** : le bandeau rouge **« DHCP Relay is currently enabled. DHCP Server cannot be  
> enabled while the DHCP Relay is enabled on any interface. »**

💡 **La cause** : depuis la brique 03, c'est **SRV-AD01** (Windows) qui distribue les adresses ; pfSense
**relaie** les demandes. pfSense ne peut pas être **relais et serveur** en même temps. Le plan
d'adressage annonçait **par erreur** « DHCP pfSense » pour le VLAN 99.

**12.4** **Décision** : **pas de DHCP dans le VLAN 99**. Comme en entreprise, le VLAN d'administration
ne contient que de l'infrastructure (switch, borne Wi-Fi, poste d'admin), toujours en **adresse
fixe** : un intrus qui se branche sur une prise du VLAN 99 ne reçoit rien, et le pare-feu peut viser
précisément le poste d'admin.

**12.5** Sur ADM-001 : **Paramètres** > **Réseau et Internet** > **Ethernet** > **Attribution
d'adresse IP** > **Modifier** > **Manuel** > active **IPv4**, et remplis :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Adresse IP | `10.10.99.10` | Plage fixe : `.1` = switch, `.10` = postes d'admin |
| Masque | `255.255.255.0` | |
| Passerelle | **vide** | ADM-001 a déjà une passerelle par le Wi-Fi (box). Deux passerelles = Windows ne sait plus par où sortir et Internet peut se couper |
| DNS | vide | |

**Enregistrer**.

> 📷 **Capture manquante** : la fenêtre « Modifier les paramètres IP » de Windows.

<img src="captures/41-adm001-ip-fixe-10-10-99-10.png" width="560">

> 📸 **Ce que tu dois voir** (`ipconfig`) : **Carte Ethernet Ethernet : Adresse IPv4 10.10.99.10**,  
> masque 255.255.255.0, passerelle **vide**. Le Wi-Fi garde 192.168.1.110 et sa passerelle .254.

**12.6** Teste : `ping 10.10.99.1`

<img src="captures/42-ping-switch-depuis-adm001.png" width="560">

> 📸 **Ce que tu dois voir** : **« Délai d'attente de la demande dépassé »** pour le 1er paquet, puis  
> 3 × **Réponse de 10.10.99.1 … TTL=255**. Perte 25 %.  
> 💡 Le **premier** paquet est perdu : c'est le temps qu'**ARP** trouve l'adresse MAC du switch  
> (« qui a 10.10.99.1 ? »). **C'est normal.** TTL=255 = valeur de départ typique d'un équipement Cisco.

✅ **Vérification** : ADM-001 joint le switch.

---

### Étape 13 · Se connecter en SSH depuis ADM-001

🎯 Administrer le switch **sans câble console**, à travers le réseau, chiffré.

**13.1** Dans PowerShell :

```
ssh adm.paulo.rosa@10.10.99.1
```

<img src="captures/43-ssh-refus-kex-puis-cipher.png" width="720">

> 📸 **❌ Ce que j'ai eu** : **`no matching key exchange method found. Their offer:  
> diffie-hellman-group-exchange-sha1, diffie-hellman-group14-sha1, diffie-hellman-group1-sha1`**.  
> Puis, après avoir réautorisé l'échange de clés : **`no matching cipher found. Their offer:  
> aes128-cbc, 3des-cbc, aes192-cbc, aes256-cbc`**.

💡 **Pourquoi ?** Le switch de 2013 et Windows 11 ne trouvent pas d'algorithme **commun**. Une
connexion SSH, c'est **4 négociations successives**, et on les a vues échouer une par une :

| N° | Négociation | Question | Message d'erreur | Choix retenu (le moins faible proposé par le switch) |
| --- | --- | --- | --- | --- |
| 1 | KEX (échange de clés) | Comment fabriquer une clé secrète commune sans qu'elle soit interceptée ? | `no matching key exchange method` | `diffie-hellman-group14-sha1` |
| 2 | HostKey | Comment être sûr de parler au vrai switch ? | `no matching host key type` | `ssh-rsa` (la clé RSA 2048 de l'étape 9) |
| 3 | Cipher (chiffrement) | Avec quoi chiffrer ? | `no matching cipher` | `aes256-cbc` (pas `3des-cbc`, trop faible) |
| 4 | MAC (intégrité) | Comment prouver qu'un paquet n'a pas été modifié ? | `no matching MAC` | `hmac-sha1` (pas `hmac-md5`, cassé). Ici MAC = *Message Authentication Code*, rien à voir avec l'adresse MAC |

<img src="captures/44-ssh-refus-mac.png" width="720">

> 📸 **❌ 3e refus** : **`no matching MAC found. Their offer: hmac-sha1, hmac-sha1-96, hmac-md5,  
> hmac-md5-96`**.

**13.2** Réautorise les 4 algorithmes, **seulement pour cette connexion** :

```
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o Ciphers=+aes256-cbc -o MACs=+hmac-sha1 adm.paulo.rosa@10.10.99.1
```

💡 Le `+` **ajoute** l'algorithme à la liste par défaut, sans retirer les modernes.

**13.3** À la première connexion, SSH affiche l'**empreinte** (*fingerprint*) du switch et demande
`Are you sure you want to continue connecting (yes/no/[fingerprint])?` : tape **`yes`**, puis le mot
de passe du compte admin.

<img src="captures/45-ssh-reussi-sw-core01.png" width="720">

> 📸 **Ce que tu dois voir** : « The authenticity of host '10.10.99.1' can't be established »,  
> l'empreinte **RSA key fingerprint is SHA256:…**, ta réponse **yes**, **Permanently added  
> '10.10.99.1' (RSA) to the list of known hosts**, puis **Password:** et **`SW-CORE01#`** ✅.

💡 Windows garde l'empreinte dans `known_hosts`. Si un jour un autre appareil se fait passer pour
10.10.99.1, SSH refusera (« HOST IDENTIFICATION HAS CHANGED ») : c'est la protection contre
l'**homme du milieu**.

**13.4** Sur le switch, `show users` montre la console (`con 0`) **et** ta session SSH (`vty 0`,
depuis 10.10.99.10).

---

### Étape 14 · Ne plus retaper la longue commande : le fichier ~/.ssh/config

🎯 Se connecter avec un simple `ssh sw-core01`.

**14.1** Ouvre le **Bloc-notes** et écris exactement :

```
Host sw-core01
    HostName 10.10.99.1
    User adm.paulo.rosa
    KexAlgorithms +diffie-hellman-group14-sha1
    HostKeyAlgorithms +ssh-rsa
    Ciphers +aes256-cbc
    MACs +hmac-sha1
```

**14.2** Enregistre-le dans `C:\Users\admlocal\.ssh\` sous le nom **`config`**, **sans extension**.

<img src="captures/46-fichier-ssh-config.png" width="520">

> 📸 **❌ Ce que j'ai eu** : le Bloc-notes a enregistré **`config.txt`** (regarde l'onglet). SSH cherche  
> un fichier nommé `config` tout court : il ne le trouve pas et répond `Could not resolve hostname  
> sw-core01`.

**14.3** Corrige le nom dans PowerShell, puis vérifie et connecte-toi :

```
Rename-Item $HOME\.ssh\config.txt config
dir $HOME\.ssh
ssh sw-core01
```

<img src="captures/47-ssh-sw-core01-raccourci.png" width="560">

> 📸 **Ce que tu dois voir** : dans `dir`, deux fichiers **`config`** (190 octets) et  
> **`known_hosts`**, puis `ssh sw-core01` → **(adm.paulo.rosa@10.10.99.1) Password:** ✅.

💡 Les réglages anciens ne s'appliquent **qu'à ce switch**, pas aux autres serveurs.
💡 **Réflexe** : afficher les extensions dans l'Explorateur (**Affichage** > **Afficher** >
**Extensions de noms de fichiers**).

---

## Partie 7 — Heure et bannière légale

### Étape 15 · Mettre le switch à l'heure (NTP)

🎯 Avoir des journaux **à la bonne heure**.

💡 Le switch n'a pas de pile : il croyait être le **30 mars 2011**. Des journaux à la mauvaise heure
rendent impossible l'enquête après un incident (on compare les journaux de plusieurs équipements).

**15.1** Tape (en SSH) :

```
configure terminal
clock timezone CET 1 0
clock summer-time CEST recurring last Sun Mar 2:00 last Sun Oct 3:00
ntp server 10.10.99.254
service timestamps log datetime msec localtime show-timezone
end
```

<img src="captures/49-ntp-fuseau-horaire.png" width="620">

> 📸 **Ce que tu dois voir** : les commandes acceptées, puis des messages `%SYS-6-CLOCKUPDATE` (le  
> fuseau change l'heure affichée), et à la fin un journal daté **`Oct 30 20:19:56.630 CET`** : le  
> switch a pris l'heure de pfSense.

| Commande | Pourquoi |
| --- | --- |
| `clock timezone CET 1 0` | Fuseau de Paris, heure d'hiver UTC+1 |
| `clock summer-time CEST recurring …` | Heure d'été automatique (dernier dimanche de mars → dernier dimanche d'octobre) |
| `ntp server 10.10.99.254` | pfSense donne l'heure (lui-même la prend sur Internet) |
| `service timestamps log … localtime show-timezone` | Journaux datés à la milliseconde, en heure locale |

**15.2** Attends 2 à 5 minutes, puis vérifie :

```
show clock
show ntp status
```

<img src="captures/51-show-clock-ntp-synchronise.png" width="620">

> 📸 **Ce que tu dois voir** : **`20:21:56.671 CET Fri Oct 30 2026`**, puis **`Clock is synchronized,  
> stratum 3, reference is 10.10.99.254`**.  
> 💡 **Stratum 3** : le switch est à 3 « étages » d'une horloge de référence (horloge atomique →  
> serveur Internet → pfSense → switch).

---

### Étape 16 · La bannière légale

🎯 Afficher un avertissement juridique **avant** la connexion.

💡 Un message « accès réservé » affiché **avant** la connexion a une valeur juridique : un intrus ne
peut pas prétendre ignorer que l'accès était interdit (recommandation ANSSI).

**16.1** Tape :

```
configure terminal
banner login #
Acces reserve aux administrateurs AEROTRANS.
Toute connexion est enregistree.
Tout acces non autorise est puni par la loi (art. 323-1 du Code penal).
#
end
copy running-config startup-config
```

💡 Le `#` est le **délimiteur** de début et de fin (un caractère absent du texte). **Pas d'accents** :
la console Cisco les affiche mal.

<img src="captures/50-banniere-login-sauvegarde.png" width="620">

> 📸 **Ce que tu dois voir** : « Enter TEXT message. End with the character '#'. », les 3 lignes, le  
> `#` final, puis la sauvegarde **[OK]**.

**16.2** Déconnecte-toi (`exit`) et reconnecte-toi : `ssh sw-core01`.

<img src="captures/52-banniere-affichee-connexion-ssh.png" width="620">

> 📸 **Ce que tu dois voir** : la bannière **Acces reserve aux administrateurs AEROTRANS…** affichée  
> **avant** `Password:` ✅.

---

## Partie 8 — Recette

| # | Test | Commande | Résultat attendu | Résultat |
| --- | --- | --- | --- | --- |
| 1 | Remise à zéro | `show startup-config` (avant config) | `startup-config is not present` | ✅ |
| 2 | Console protégée | Débrancher / rebrancher PuTTY | `Username:` demandé | ✅ |
| 3 | VLAN | `show vlan brief` | 10, 20, 30, 40, 99, 999 | ✅ |
| 4 | Ports | `show interfaces status` | Fa0/2 en 99, Fa0/3-6 en 20, parking `disabled` | ✅ |
| 5 | Trunk | `show interfaces trunk` | Gi0/1 trunking, native 999, VLAN 10,20,30,40,99 | ✅ |
| 6 | Vitesse du trunk | `show interfaces status` | Gi0/1 `a-1000` | ✅ (après échange du câble) |
| 7 | Joindre pfSense | `ping 10.10.99.254` | `!!!!!` | ✅ |
| 8 | SSH | `ssh sw-core01` depuis ADM-001 | Bannière puis `SW-CORE01#` | ✅ |
| 9 | Telnet coupé | `transport input ssh` dans la config | Telnet refusé | ✅ |
| 10 | Heure | `show ntp status` | `Clock is synchronized` | ✅ |

---

## Annexes

### A. La config complète

Les secrets sont remplacés par `<haché>` :

```
hostname SW-CORE01
!
enable secret 9 <haché>
username adm.paulo.rosa privilege 15 secret 9 <haché>
service password-encryption
no ip domain-lookup
ip domain-name lab.home.arpa
!
vlan 10
 name SERVEURS
vlan 20
 name POSTES
vlan 30
 name WIFI_SALARIES
vlan 40
 name WIFI_INVITES
vlan 99
 name ADMINISTRATION
vlan 999
 name PARKING
!
interface FastEthernet0/1
 description NON UTILISE - parking
 switchport access vlan 999
 switchport mode access
 shutdown
interface FastEthernet0/2
 description ADM-001 poste d'administration
 switchport access vlan 99
 switchport mode access
 spanning-tree portfast
 spanning-tree bpduguard enable
interface range FastEthernet0/3 - 6
 description Postes de travail
 switchport access vlan 20
 switchport mode access
 spanning-tree portfast
 spanning-tree bpduguard enable
interface range FastEthernet0/7 - 8 , GigabitEthernet0/2
 description NON UTILISE - parking
 switchport access vlan 999
 switchport mode access
 shutdown
interface GigabitEthernet0/1
 description TRUNK vers PVE01 nic1 (vmbr1)
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,30,40,99
 switchport mode trunk
 switchport nonegotiate
!
interface Vlan1
 shutdown
interface Vlan99
 description Administration SW-CORE01
 ip address 10.10.99.1 255.255.255.0
!
ip default-gateway 10.10.99.254
no ip http server
no ip http secure-server
ip ssh version 2
ip ssh time-out 60
ip ssh authentication-retries 3
!
clock timezone CET 1 0
clock summer-time CEST recurring last Sun Mar 2:00 last Sun Oct 3:00
service timestamps log datetime msec localtime show-timezone
ntp server 10.10.99.254
!
banner login #
Acces reserve aux administrateurs AEROTRANS.
Toute connexion est enregistree.
Tout acces non autorise est puni par la loi (art. 323-1 du Code penal).
#
!
line con 0
 exec-timeout 10 0
 logging synchronous
 login local
line vty 0 15
 exec-timeout 10 0
 login local
 transport input ssh
```

(Présentation simplifiée : IOS affiche chaque interface séparément, sans `range`.)

### B. Dépannage — récapitulatif

| Symptôme | Cause | Correction |
| --- | --- | --- |
| Écran noir dans PuTTY | Mauvais port COM ou vitesse ≠ 9600 | Gestionnaire de périphériques, Speed 9600 |
| Le switch redemande `Username:` après MODE | Bouton relâché trop tôt | Recommencer, attendre SYST vert fixe |
| `Unknown cmd: dir` dans le bootloader | Faute de frappe ou caractère invisible | Retaper la commande proprement |
| `% Password: timeout expired!` | Plus de 30 s pour saisir le mot de passe | Copier le mot de passe **avant** de taper le nom |
| `% Invalid input` sur `algorithm-type scrypt` | IOS trop ancien | `enable secret` seul (type 5) |
| Port en `err-disabled` | bpduguard a vu un switch | Débrancher, `shutdown` / `no shutdown` |
| Vlan99 `up / down` | Aucun port actif ni trunk dans le VLAN 99 | Brancher Fa0/2 ou monter le trunk |
| Trunk en `a-100` | Câble défectueux (une paire HS) | Échanger / tester / remplacer le câble |
| PC en 169.254.x.x | Aucun serveur DHCP dans le VLAN (ici : relais DHCP sur pfSense) | Adresse fixe (VLAN d'administration) |
| `no matching key exchange / cipher / MAC` | Équipement ancien, algorithmes désactivés par Windows | Les réautoriser pour cet hôte seulement (étapes 13-14) |
| `Could not resolve hostname sw-core01` | Fichier `config.txt` au lieu de `config` | `Rename-Item … config` |
| Premier ping perdu | Résolution ARP | Normal |

### C. Antisèche des commandes

| Commande | Utilité |
| --- | --- |
| `show running-config` | Config en cours |
| `show startup-config` | Config sauvegardée |
| `show vlan brief` | VLAN et leurs ports |
| `show interfaces status` | État, VLAN, vitesse de chaque port |
| `show interfaces trunk` | État des trunks |
| `show ip interface brief` | Adresses IP et état des interfaces |
| `show mac address-table vlan 99` | Quelles machines derrière quels ports |
| `show ip ssh` | État du SSH |
| `show version` / `show inventory` | Modèle, IOS, licence / numéro de série |
| `show env all` / `show power inline` | Température, alimentation / budget PoE |
| `show clock` / `show ntp status` | Heure / synchronisation |
| `show users` | Qui est connecté |
| `copy running-config startup-config` | **Sauvegarder** |
| `?` | Aide contextuelle (`show ?`, `interface ?`) |
| **Tab** | Complète une commande |

### D. Écarts entre le lab et une vraie entreprise

| Sujet | Dans le lab | En entreprise | Pourquoi l'écart |
| --- | --- | --- | --- |
| Mot de passe exposé | Le mot de passe enable est apparu en clair sur une capture partagée pendant la séance ; **choix assumé : pas changé** | Un mot de passe vu, même une seconde, est **compromis** : on le régénère et on le remplace immédiatement | Lab personnel, sans enjeu réel. La règle est connue et documentée ici |
| Authentification | Un compte local unique (`adm.paulo.rosa`) | Comptes des admins dans l'**AD**, vérifiés par **RADIUS ou TACACS+** (NPS) ; un seul compte local « de secours » dans un coffre partagé | Un seul admin dans la PME fictive. RADIUS est prévu avec la brique Wi-Fi |
| Coffre à mots de passe | Fichier KeePassXC local sur ADM-001 | Coffre d'équipe (Vaultwarden, Bitwarden Entreprise, CyberArk…) avec sauvegarde et partage contrôlé | À faire : **sauvegarder le fichier `.kdbx`** (brique 07) |
| Version d'IOS | 15.0(2)SE5 (2013) | Dernière version recommandée par Cisco, matériel encore supporté | Matériel d'occasion. À vérifier : dernière version et fin de support |
| Heure | NTP vers pfSense | NTP vers 2 sources minimum | Une seule source dans le lab |
| Redondance | Un seul switch, une seule alimentation | Deux switchs empilés, alimentations redondantes, onduleur | Budget lab |
| Sauvegarde de la config | `copy running-config startup-config` uniquement | Copie automatique hors du switch (SCP, Oxidized, RANCID) à chaque modification | À voir avec la brique 07 |
| Récupération de mot de passe | Laissée active | Parfois désactivée en environnement sensible | Utile en lab |
| Algorithmes SSH | Algorithmes anciens réautorisés côté client | Signal d'alerte : mettre IOS à jour ou remplacer le matériel | Matériel d'occasion de 2013 |
| Poste d'admin | ADM-001 relié au Wi-Fi de la box **et** au VLAN 99 | Relié **uniquement** au réseau d'administration | Lab à la maison |
| Pont vmbr1 | Laisse passer tous les VLAN (2-4094) | Limité aux VLAN utilisés | Amélioration à faire |
| Câblage | Câble défectueux identifié par échange, laissé sur le poste d'admin | Câbles testés et certifiés, étiquetés ; câble HS jeté | Pas de testeur à la maison |
| Bannière légale | En place | Texte validé par le service juridique | — |

### E. Questions d'entretien

| Question | Réponse courte |
| --- | --- |
| Différence entre running-config et startup-config ? | running = en RAM, appliquée tout de suite, perdue à l'extinction ; startup = `flash:config.text`, lue au démarrage |
| Où sont stockés les VLAN sur un Catalyst ? | Dans `flash:vlan.dat`, pas dans la config : à effacer aussi pour une remise à zéro |
| Comment récupérer un switch Catalyst sans le mot de passe ? | Bouton MODE au démarrage → bootloader → `flash_init` → supprimer `config.text`. Sur un routeur : registre 0x2142 |
| `enable password` ou `enable secret` ? | Toujours `enable secret` (haché, idéalement type 9 scrypt) |
| Access ou trunk ? | Access : un seul VLAN (un PC). Trunk : plusieurs VLAN étiquetés 802.1Q |
| Pourquoi changer le VLAN natif d'un trunk ? | Il passe sans étiquette ; laissé sur le VLAN 1, il permet le double étiquetage |
| À quoi servent portfast et bpduguard ? | portfast : activation immédiate ; bpduguard : coupe le port si on y branche un switch |
| Pourquoi un VLAN parking ? | Les prises libres ne mènent nulle part et sont éteintes |
| Un PC en 169.254.x.x ? | Aucun serveur DHCP n'a répondu. Le lien physique, lui, fonctionne |
| Pourquoi le premier ping est-il souvent perdu ? | Le temps de la résolution ARP |
| SSH refusé avec « no matching key exchange method » ? | Pas d'algorithme commun : réautoriser l'ancien côté client (temporaire) et planifier la mise à jour |
| Un lien Gigabit négocie à 100 Mb/s ? | Le plus souvent le câble (une des 4 paires HS). Diagnostic par échange ou testeur |

### F. Améliorations possibles

- [x] Vitesse du trunk : réglée par échange de câbles (Gi0/1 en a-1000).
- [x] NTP et bannière.
- [ ] Remplacer le câble défectueux (actuellement sur ADM-001 ↔ Fa0/2).
- [ ] Limiter `vmbr1` aux VLAN 10, 20, 30, 40, 99.
- [ ] Journal du switch vers un serveur (syslog) — avec la brique Wazuh.
- [ ] Authentification des admins par l'AD (RADIUS / NPS) — avec la brique Wi-Fi.
- [ ] Ajouter SW-CORE01 au DNS (`sw-core01.lab.home.arpa`) et dans GLPI.
- [ ] Vérifier la dernière version d'IOS et la fin de support du WS-C2960C-8PC-L.
- [ ] Supprimer la règle WAN temporaire de pfSense.
- [ ] Sauvegarde automatique de la config hors du switch (brique 07).

### G. Captures manquantes

| Étape | Écran à photographier |
| --- | --- |
| 2.3 | Face avant du switch : bouton MODE et voyant SYST |
| 12.5 | Fenêtre Windows « Modifier les paramètres IP » |

### H. Lexique

| Mot | Sens |
| --- | --- |
| **APIPA** | Adresse de secours 169.254.x.x que Windows se donne sans DHCP |
| **ARP** | Protocole qui trouve l'adresse MAC correspondant à une adresse IP |
| **Bootloader** | Mini-système de démarrage du switch (invite `switch:`) |
| **bpduguard** | Coupe un port si un switch y est branché |
| **DTP** | Protocole Cisco de négociation automatique du trunk (coupé par `nonegotiate`) |
| **IOS** | Le système d'exploitation des équipements Cisco |
| **Native VLAN** | Le VLAN qui passe **sans étiquette** sur un trunk |
| **PoE** | *Power over Ethernet* : alimentation électrique par le câble réseau |
| **scrypt (type 9)** | Algorithme de hachage fort pour les mots de passe Cisco |
| **SVI** | Interface virtuelle de VLAN (`interface vlan 99`) qui porte l'adresse du switch |
| **VTY** | Lignes de connexion à distance (SSH) |
