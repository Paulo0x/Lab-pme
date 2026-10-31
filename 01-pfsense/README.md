# Brique 01 — Le pare-feu pfSense et le découpage du réseau en VLAN

> **Tuto pas à pas pour quelqu'un qui débute complètement.**  
> Chaque action a son numéro. Chaque capture est placée **juste sous l'action qu'elle montre**, avec  
> une légende qui dit **ce que tu dois voir** et **quoi faire si ce n'est pas pareil**.  
> Les vraies erreurs faites pendant le lab sont gardées, avec leur correction.

---

## 🧾 Fiche de la brique

| | |
| --- | --- |
| **Objectif** | Installer **le pare-feu** de l'entreprise et **découper le réseau** en 5 réseaux séparés (VLAN), puis **prouver** que la séparation marche |
| **Durée** | Environ **4 à 5 h** la première fois |
| **Niveau** | Débutant, après la [brique 00](../00-proxmox/) |
| **Résultat** | VM `fw01` (pfSense CE 2.9.0), WAN `192.168.1.211`, 5 VLAN avec pfSense en `.254`, règles du VLAN Postes testées |
| **Brique précédente** | [00 · Proxmox](../00-proxmox/) — **brique suivante** : [02 · switch Cisco](../02-switch-cisco/) |

### Ce qu'il faut avant de commencer

| Élément | Détail |
| --- | --- |
| Proxmox installé | `pve01` (192.168.1.210), voir brique 00 |
| 2 cartes réseau sur le serveur | `nic0` (déjà utilisée, côté box) et `nic1` (libre, future liaison vers le switch) |
| Un PC d'administration | Sur le réseau de la box (chez moi `192.168.1.98`) |
| L'ISO de pfSense | **Netgate Installer** (gratuit, voir étape 1) |
| L'ISO Alpine Linux | `alpine-virt` (67 Mo) pour la VM de test de la fin. Site officiel : `https://alpinelinux.org/downloads/` |

### Ce que tu sauras faire à la fin

- Expliquer à quoi sert un **pare-feu** et des **VLAN**.
- Créer une VM avec **deux cartes réseau** (Internet d'un côté, entreprise de l'autre).
- Installer pfSense et **dépanner** une erreur d'installation par élimination.
- Créer des VLAN, leur donner une adresse, et vérifier les masques **par une commande**.
- Écrire des **règles de pare-feu** dans le bon ordre.
- Faire une **recette** : prouver ce qui passe **et** ce qui est bloqué.

---

## 📖 Comment lire ce tuto

| Repère | Sens |
| --- | --- |
| 🎯 | **Le but** de l'étape, en une phrase |
| 💡 | **Pourquoi** on le fait, ou une explication pour comprendre |
| **3.2** | Une **action** à faire (étape 3, action 2) |
| 📸 | **La capture** de ce que tu dois voir, avec sa légende |
| ✅ | **Vérification** : comment savoir que c'est réussi |
| ❌ | **Si ça ne marche pas** (souvent l'erreur que j'ai vraiment eue) |
| 🏢 | **En entreprise**, ce qu'on ferait autrement |
| ⚠️ | Attention, piège ou risque |
| 📷 | **Capture manquante** : l'écran est décrit en texte |

**Dans l'installateur de pfSense** (écran bleu, sans souris) : **flèches** pour se déplacer,
**Entrée** pour valider, **Tab** pour passer d'un bouton à l'autre (OK / Cancel), la **lettre en
rouge** d'une ligne pour l'ouvrir directement.

---

## 🗂️ Sommaire

- [Partie 0 — Comprendre avant de commencer](#partie-0--comprendre-avant-de-commencer)
- [Partie 1 — Préparer l'installateur](#partie-1--préparer-linstallateur) (étapes 1 et 2)
- [Partie 2 — Le réseau dans Proxmox](#partie-2--le-réseau-dans-proxmox) (étape 3)
- [Partie 3 — La machine virtuelle du pare-feu](#partie-3--la-machine-virtuelle-du-pare-feu) (étapes 4 et 5)
- [Partie 4 — Installer pfSense](#partie-4--installer-pfsense) (étapes 6 à 11)
- [Partie 5 — Accéder à l'interface web](#partie-5--accéder-à-linterface-web) (étapes 12 et 13)
- [Partie 6 — Créer les VLAN](#partie-6--créer-les-vlan) (étapes 14 à 16)
- [Partie 7 — DHCP et règles du VLAN Postes](#partie-7--dhcp-et-règles-du-vlan-postes) (étapes 17 et 18)
- [Partie 8 — La recette](#partie-8--la-recette-on-prouve-que-la-segmentation-marche) (étapes 19 et 20)
- [Annexes](#annexes) : dépannage, antisèche, entreprise, entretien, écarts, lexique

---

## Partie 0 — Comprendre avant de commencer

### 0.1 Le besoin

AEROTRANS a besoin :

- d'**une seule porte** entre Internet et son réseau, qui **contrôle** ce qui entre et ce qui sort ;
- de **séparer** ses machines par usage : serveurs, postes, Wi-Fi des salariés, Wi-Fi des invités,
  administration. **Un invité ne doit jamais atteindre un serveur. Un poste infecté ne doit jamais
  toucher aux équipements réseau.**

### 0.2 Les images à retenir

| Notion | Image |
| --- | --- |
| **Pare-feu** | Le **vigile** à l'entrée de l'immeuble : il a une liste de qui a le droit d'aller où |
| **VLAN** (réseau virtuel) | Des **étages séparés** dans le même immeuble : même câblage, mais on ne passe pas d'un étage à l'autre sans passer devant le vigile |
| **Trunk 802.1Q** | Un **ascenseur** qui dessert tous les étages : un seul câble transporte tous les VLAN, chaque paquet porte une **étiquette** (le « tag ») avec son numéro de VLAN |
| **Passerelle** | La **porte de l'étage** : pour sortir de son VLAN, une machine passe par pfSense (`.254`) |
| **WAN / LAN** | **WAN** = le côté Internet (ici la box). **LAN** = le côté entreprise |
| **Règle « refus par défaut »** | Le vigile refuse **tout le monde**, sauf ceux qui sont **sur la liste** |

### 0.3 Pourquoi pfSense

| Critère | pfSense CE | OPNsense | Pare-feu de la box |
| --- | --- | --- | --- |
| Présence en PME et en ESN | Très répandu | En hausse | Inadapté |
| VLAN, VPN, règles fines | Oui | Oui | Non |
| Coût | Gratuit | Gratuit | Inclus |

**Choix : pfSense CE** (*Community Edition*), le plus rencontré chez les clients et en entretien.
Il tourne en **machine virtuelle** sur Proxmox.

### 0.4 Le schéma de ce qu'on construit

```
            INTERNET
               |
         [ Freebox ] 192.168.1.254       réseau de la box 192.168.1.0/24
               |
     nic0 -> [ vmbr0 ] -- Proxmox 192.168.1.210
               |
          WAN 192.168.1.211  (carte vtnet0)
          [ fw01 : pfSense ]   le seul passage entre la box et l'entreprise
          LAN : carte vtnet1 = trunk 802.1Q (tous les VLAN)
               |
     nic1 -> [ vmbr1 ] (VLAN aware, sans IP)  -> switch Cisco (brique 02)
               |
   VLAN 10       VLAN 20       VLAN 30        VLAN 40        VLAN 99
   Serveurs      Postes        Wi-Fi salariés Wi-Fi invités  Administration
   10.10.10.254  10.10.20.254  10.10.30.254   10.10.40.254   10.10.99.254
```

💡 **Règle mnémotechnique** : dans chaque VLAN, le **3e nombre** de l'adresse est le **numéro du VLAN**
(10.10.**20**.x = VLAN 20), et pfSense est toujours en **.254**. Toutes les adresses :
[plan d'adressage](../docs/plan-adressage.md).

---

## Partie 1 — Préparer l'installateur

### Étape 1 · Récupérer l'installateur et vérifier son empreinte

🎯 Avoir un installateur **officiel** et **intact**.

💡 Depuis la version 2.8, pfSense CE s'installe avec le **Netgate Installer**. Il se récupère
gratuitement sur la boutique officielle de Netgate (l'éditeur de pfSense).

**1.1** Va sur `https://www.pfsense.org/download/`, puis suis le lien vers la boutique Netgate.

**1.2** Ajoute **Netgate Installer**, version **AMD64 ISO**, au panier (prix : **0 €**) et valide la
commande. Le lien de téléchargement arrive sur la page de confirmation et par e-mail.

> 📷 **Capture manquante** : la page de la boutique avec le choix **AMD64 / ISO**.

💡 **AMD64** = processeurs 64 bits Intel **et** AMD (comme pour Proxmox). **ISO** = image de CD,
celle qu'on donne à une VM.

**1.3** Le fichier arrive **compressé** (`netgate-installer-v1.2-RELEASE-amd64.iso.gz`). Sous Linux ou
WSL (Linux dans Windows), dans le dossier du fichier :

```bash
gzip -t netgate-installer-*.iso.gz
gunzip netgate-installer-*.iso.gz
sha256sum netgate-installer-*.iso
```

| Commande | Ce qu'elle fait | Résultat attendu |
| --- | --- | --- |
| `gzip -t` | **Teste** l'archive (abîmée ou pas) sans la décompresser | Rien ne s'affiche = archive OK |
| `gunzip` | **Décompresse** : on obtient le `.iso` | Le `.gz` disparaît, le `.iso` apparaît |
| `sha256sum` | Calcule l'**empreinte** de l'ISO | Une ligne de 64 caractères, à garder pour l'étape 2 |

💡 Une ISO abîmée pendant un transfert peut faire planter l'installation **au milieu**, et on
chercherait la panne au mauvais endroit.

> 📷 **Capture manquante** : le résultat des 3 commandes.

---

### Étape 2 · Envoyer l'ISO dans Proxmox avec contrôle

🎯 Copier l'ISO dans Proxmox, et laisser Proxmox **vérifier lui-même** l'empreinte.

**2.1** Dans Proxmox (`https://192.168.1.210:8006`), arbre de gauche : déplie **pve01** et clique
sur **local (pve01)**.

**2.2** Dans le menu du milieu, clique sur **Images ISO**, puis sur le bouton **Téléverser** (en haut).

<img src="captures/02-upload-iso-sha256.png" width="720">

> 📸 **Ce que tu vois** : la fenêtre **Téléverser**, avec **Fichier**, **Nom de fichier**  
> (`netgate-installer-v1.2-RELEASE-amd64.iso`), **Taille du fichier** (1010.17 Mio),  
> **Algorithme de hachage** et **Somme de contrôle**.  
> ⚠️ Sur la capture, l'algorithme est encore sur **None** : c'est l'état **avant** de le régler (2.4).  
> Le bandeau orange rappelle que le fichier passe d'abord par `/var/tmp/` : il faut assez de place.

**2.3** Clique sur **Choisir un fichier…** et sélectionne l'ISO.

**2.4** Dans **Algorithme de hachage**, choisis **SHA-256**. Dans **Somme de contrôle**, colle
l'empreinte de l'étape 1.3.

**2.5** Clique sur **Téléverser** et attends la fin.

<img src="captures/03-upload-iso-checksum-ok.png" width="720">

> 📸 **Ce que tu dois voir** : la fenêtre **Task viewer: Copier les données**, avec les lignes  
> **`calculating checksum...OK, checksum verified`** puis **`TASK OK`**.  
> 💡 Proxmox a **recalculé** l'empreinte après réception et l'a comparée à la tienne.  
> ❌ Si tu vois `checksum mismatch` : le fichier est abîmé, retélécharge-le.

✅ **Vérification** : l'ISO apparaît dans **local (pve01) > Images ISO**.

---

## Partie 2 — Le réseau dans Proxmox

### Étape 3 · Créer le pont vmbr1 pour le réseau de l'entreprise

🎯 Le serveur a **deux cartes réseau** : `nic0` (déjà reliée au pont **vmbr0**, côté box) et `nic1`
(libre). On crée un **pont vmbr1** sur `nic1` : ce sera le réseau **interne** de l'entreprise.

💡 Un **pont** (*bridge*) est un **switch virtuel** à l'intérieur de Proxmox : les VM s'y branchent
comme sur une vraie prise réseau.

**3.1** Arbre de gauche : clique sur **pve01**. Menu du milieu : **Système** > **Réseau**.

<img src="captures/01-proxmox-cartes-reseau.png" width="720">

> 📸 **Ce que tu vois (avant)** : la liste des cartes. **nic0**, **nic1**, **nic2** (cartes  
> physiques), **vmbr0** (Linux Bridge, ports du pont = **nic0**), **wlp4s0** (le Wi-Fi). Les noms  
> alternatifs sont floutés.  
> 💡 `nic1` est **Actif : Non** : rien n'est encore branché ni configuré dessus. C'est elle qu'on prend.

**3.2** Clique sur **Créer** > **Linux Bridge**, puis remplis :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Nom | `vmbr1` | Suite logique de vmbr0 |
| IPv4/CIDR | **vide** | Proxmox ne doit **pas** être joignable depuis le réseau de l'entreprise |
| Passerelle (IPv4) | **vide** | Même raison |
| **Gère les VLAN** (*VLAN aware*) | ✅ coché | Un seul pont pour **tous** les VLAN : chaque VM reçoit juste un **tag** |
| Ports du pont | `nic1` | Le câble qui partira vers le switch Cisco |
| Commentaire | `LAN entreprise - trunk VLAN` | |

**3.3** Clique sur **Créer**.

> 📷 **Capture manquante** : la fenêtre **Créer : Linux Bridge** remplie.

**3.4** ⚠️ La modification n'est **pas encore active** : clique sur **Appliquer la configuration**
(en haut du tableau), puis confirme.

<img src="captures/04-vmbr1-cree.png" width="720">

> 📸 **Ce que tu dois voir (après)** : une nouvelle ligne **vmbr1**, **Linux Bridge**, **Actif : Oui**,  
> **Gère les VLAN : Oui**, ports du pont **nic1**.

💡 **Alternative écartée** : un pont par VLAN (vmbr10, vmbr20…). Plus lourd : chaque nouveau VLAN
obligerait à modifier le réseau de Proxmox.

✅ **Vérification** : `vmbr1` est **actif**, sur `nic1`, avec « Gère les VLAN » à Oui.

---

## Partie 3 — La machine virtuelle du pare-feu

### Étape 4 · Créer la VM 100 · fw01

🎯 Créer une VM avec **une carte côté Internet** (vmbr0) ; la carte côté entreprise viendra à l'étape 5.

**4.1** En haut à droite, clique sur **Créer une VM**. Coche **Avancé** (en bas de la fenêtre) pour
voir toutes les options.

**4.2** Remplis chaque onglet, puis **Suivant** :

| Onglet | Réglage | Valeur | Pourquoi |
| --- | --- | --- | --- |
| **Général** | ID de la VM | `100` | La centaine = l'infrastructure réseau |
| | Nom | `fw01` | *firewall* n°1 |
| | Démarrer au démarrage | ✅ | Le pare-feu doit redémarrer tout seul après une coupure |
| | Ordre de démarrage / délai | `1` / `30` | Il démarre **en premier** ; les autres VM attendent 30 s qu'il soit prêt |
| **Système d'exploitation** | Image ISO | `netgate-installer-…amd64.iso` | |
| | Type | **Other** | pfSense tourne sur **FreeBSD**, pas sur Linux |
| **Système** | Machine | **q35** | Modèle de carte mère virtuelle récent |
| | BIOS | SeaBIOS | Pas besoin d'UEFI |
| | Contrôleur SCSI | VirtIO SCSI single | |
| **Disques** | Bus / taille | **SCSI**, `16` Gio | Un pare-feu stocke peu |
| | Options | ✅ Discard, ✅ Émulation SSD, ✅ IO thread | Meilleures performances sur SSD |
| **Processeur** | Cœurs / type | `2`, **host** | Le vrai processeur est transmis, avec ses instructions **AES-NI** (chiffrement rapide pour les VPN) |
| **Mémoire** | Taille | `2048` Mio | |
| | Ballooning | ❌ décoché | Le ballooning (mémoire « élastique ») marche mal sous FreeBSD |
| **Réseau** | Pont / modèle | **vmbr0** / **VirtIO** | La carte **WAN**, côté box |
| | Pare-feu | ❌ décoché | C'est pfSense qui filtre, pas Proxmox |

❌ **Piège évité** : avec le type « Other », Proxmox propose par défaut un disque **IDE** et une carte
**Intel E1000**, lents. On passe sur **SCSI** et **VirtIO**.

**4.3** Onglet **Confirmation** : relis tout. Laisse **Démarrer après création** décoché.

<img src="captures/05-vm-fw01-recapitulatif.png" width="640">

> 📸 **Ce que tu dois voir** : le récapitulatif. Contrôle surtout :  
> `balloon 0` · `cores 2` · `cpu host` · `ide2 local:iso/netgate-installer…` (l'ISO dans le lecteur) ·  
> `machine q35` · `memory 2048` · `name fw01` · `net0 virtio,bridge=vmbr0` · `onboot 1` ·  
> `ostype other` · `scsi0 local-lvm:16,discard=on,ssd=on,iothread=on` · `scsihw virtio-scsi-single`.

**4.4** Clique sur **Terminer**.

---

### Étape 5 · Ajouter la carte côté entreprise (le trunk)

**5.1** Dans l'arbre, clique sur **100 (fw01)**, puis sur **Matériel**.

**5.2** Clique sur **Ajouter** > **Carte réseau**, et remplis :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Pont | **vmbr1** | Le réseau de l'entreprise |
| Étiquette VLAN | **vide** | Voir ci-dessous |
| Modèle | **VirtIO** | Le plus rapide |
| Pare-feu | ❌ | |

**5.3** Clique sur **Ajouter**.

💡 **Sans étiquette VLAN** = cette carte reçoit **tous** les VLAN avec leur étiquette : c'est le
**trunk**. C'est pfSense qui lira lui-même les étiquettes.

<img src="captures/06-vm-fw01-materiel-2-cartes.png" width="720">

> 📸 **Ce que tu dois voir** : dans **Matériel**, deux lignes **Carte réseau** :  
> **net0** `virtio=…,bridge=vmbr0` et **net1** `virtio=…,bridge=vmbr1` (adresses MAC floutées).  
> Plus Mémoire 2 Gio, Processeurs 2 [host], BIOS SeaBIOS, Machine q35, le lecteur CD avec l'ISO et  
> le disque `scsi0` de 16 Go.

💡 **Note l'adresse MAC de net0** (survole ou double-clique la ligne) : elle servira à l'étape 6.2
pour reconnaître la carte WAN.

✅ **Vérification** : 2 cartes réseau, net0 sur vmbr0 et net1 sur vmbr1.

---

## Partie 4 — Installer pfSense

### Étape 6 · Démarrer l'installateur et choisir la carte WAN

**6.1** Clique sur **Démarrer** (en haut à droite), puis sur **Console**.

<img src="captures/07-installateur-accueil.png" width="560">

> 📸 **Ce que tu dois voir** : **Netgate Installer – v1.2-RELEASE**, fenêtre **Welcome to pfSense!**,  
> avec **Install** (installer) ou **Rescue Shell** (dépannage).  
> **Install** est sélectionné : appuie sur **Entrée** (OK).

**6.2** L'installateur demande quelle carte est le **WAN**.

<img src="captures/08-choix-wan-vtnet0.png" width="560">

> 📸 **Ce que tu vois** : **WAN Interface Assignment and Configuration**, avec **vtnet0** et  
> **vtnet1** (les MAC sont floutées), toutes deux **active**.  
> 💡 Les noms changent d'un système à l'autre : `net0` dans Proxmox devient `vtnet0` dans FreeBSD.  
> **L'adresse MAC, elle, ne change jamais** : compare-la avec celle de **net0** notée à l'étape 5.  
> Choisis **vtnet0** (celle de vmbr0, côté box), puis **OK**.

---

### Étape 7 · Le WAN : d'abord en DHCP

<img src="captures/09-wan-mode-dhcp-defaut.png" width="560">

> 📸 **Ce que tu vois** : **WAN (vtnet0) Network Mode Setup**, avec **Interface Mode = DHCP (client)**,  
> VLAN Tagging disabled, Use local resolver false.

**7.1** Pour l'instant, garde ce réglage : sélectionne **>> Continue** et **OK**.

💡 On voulait mettre tout de suite l'adresse fixe `192.168.1.211`. Ça a échoué : c'est la panne de
l'étape 8. **Si tu suis ce tuto, fais directement dans cet ordre** : laisse le WAN en DHCP,
configure le **LAN d'abord** (étape 9), puis reviens sur le WAN.

---

### Étape 8 · Dépannage : « Cannot set WAN interface IP address »

❌ **Ce qui s'est passé** : en voulant passer le WAN en adresse fixe :

<img src="captures/10-wan-statique-211.png" width="560">

> 📸 **Ce que j'avais rempli** : Interface Mode **STATIC**, IP Address **192.168.1.211/24**,  
> Default Gateway **192.168.1.254**, DNS Server **192.168.1.254**.

<img src="captures/11-erreur-wan-statique.png" width="560">

> 📸 **Le refus** : fenêtre **Warning!** : **« Cannot set WAN interface IP address: 192.168.1.211/24 »**.

💡 **La méthode** : on liste les hypothèses, et on les teste **une par une** :

| Hypothèse | Test | Résultat |
| --- | --- | --- |
| Conflit d'adresse (quelqu'un a déjà .211) | `ping` + `arp -a` depuis le PC admin | ❌ Écartée : l'adresse est libre |
| Le format `/24` est refusé | Saisie sans `/24` | ❌ Fausse piste : accepté, mais le masque devient `/32` |
| **Chevauchement de réseaux** | Regarder le LAN proposé par défaut | ✅ **Confirmée** |

<img src="captures/12-test-conflit-ip-211.png" width="560">

> 📸 **Le test de conflit** : `ping 192.168.1.211` → 4 fois « Réponse de **192.168.1.98** : Impossible  
> de joindre l'hôte » (c'est **ton PC** qui répond, comme en brique 00), et `arp -a | findstr  
> 192.168.1.211` ne renvoie **rien**. Personne n'a cette adresse : **pas de conflit**.

<img src="captures/13-lan-defaut-chevauchement.png" width="560">

> 📸 **La vraie cause** : **LAN (vtnet1) Network Mode Setup** montre le LAN **par défaut** :  
> **IP Address 192.168.1.1/24**, DHCP de `192.168.1.100` à `.199`.  
> 💡 C'est **le même réseau** que le WAN (192.168.1.x) ! Un routeur ne peut pas avoir deux portes  
> **dans le même réseau** : il ne saurait pas par laquelle envoyer les paquets. D'où le refus.

✅ **Correction : configurer le LAN avant le WAN.** C'est l'étape 9.

---

### Étape 9 · Configurer le LAN sur le VLAN 99 (administration)

🎯 Mettre le LAN de pfSense dans le réseau d'administration `10.10.99.0/24`, sur le **VLAN 99**.

**9.1** Dans **LAN (vtnet1) Network Mode Setup**, ouvre **VLAN Settings** (touche **V**).

<img src="captures/14-lan-vlan99.png" width="560">

> 📸 **Ce que tu dois voir** : **LAN (vtnet1) VLAN Setup** avec **Enable VLAN = YES**,  
> **VLAN Tag = 99**, **Priority Tag = 0**.  
> 💡 Le LAN de pfSense devient `vtnet1.99` : la carte vtnet1, **VLAN 99**.

**9.2** Remplis comme sur la capture, puis **>> Continue** > **OK**.

**9.3** De retour dans **LAN Network Mode Setup**, règle l'adresse et le DHCP :

| Ligne (touche) | Valeur |
| --- | --- |
| Interface Mode (**M**) | STATIC |
| IP Address (**I**) | `10.10.99.254/24` |
| DHCPD Enabled (**D**) | true |
| DHCPD Range Start (**S**) | `10.10.99.100` |
| DHCPD Range End (**E**) | `10.10.99.199` |

<img src="captures/15-lan-config-complete.png" width="560">

> 📸 **Ce que tu dois voir** : **STATIC**, **VLAN Tagging enabled. Tag: 99**, **10.10.99.254/24**,  
> DHCPD Enabled **true**, plage **10.10.99.100** à **10.10.99.199**.  
> 💡 Ce DHCP provisoire sera retiré plus tard (en brique 02, le VLAN 99 passe en adresses fixes).

**9.4** **>> Continue** > **OK**.

<img src="captures/16-affectation-interfaces.png" width="560">

> 📸 **Ce que tu dois voir** : **Interface Assignment and Configuration**, « Detected: QEMU Guest »,  
> avec **LAN → vtnet1 (active) vlan 99** et **WAN → vtnet0 (active)**.  
> 💡 *QEMU Guest* = pfSense a compris qu'il tourne dans une VM Proxmox.

✅ **Vérification** : LAN = vtnet1 vlan 99, WAN = vtnet0.

---

### Étape 10 · Le WAN en adresse fixe, puis l'installation

**10.1** Choisis **[Assign/Configure]** pour revenir au **WAN**, puis règle :

| Ligne | Valeur |
| --- | --- |
| Interface Mode | STATIC |
| IP Address | `192.168.1.211/24` |
| Default Gateway | `192.168.1.254` |
| DNS Server | `192.168.1.254` |

<img src="captures/17-wan-statique-24-apres-lan.png" width="560">

> 📸 **Ce que tu dois voir** : les mêmes valeurs qu'à l'étape 8, mais **cette fois c'est accepté** :  
> le LAN n'est plus dans le réseau de la box.

**10.2** **>> Continue** > **OK**, puis **Continue** sur l'écran d'affectation.

<img src="captures/18-validation-abonnement-install-ce.png" width="560">

> 📸 **Ce que tu vois** : **Active Subscription Validation** : « This device does not have an active  
> pfSense Plus subscription ». Le **NDI** (identifiant de l'appareil) est flouté.  
> 💡 **pfSense Plus** est la version payante. On veut la version **gratuite** : choisis  
> **[ Install CE ]** puis **Entrée**.

**10.3** Pour le disque, choisis :

| Question | Choix | Pourquoi |
| --- | --- | --- |
| Système de fichiers | **ZFS** | Il résiste aux **coupures de courant** et permet de **revenir en arrière** après une mise à jour ratée |
| Partitions | **GPT** | Le schéma moderne |
| Disque | `da0` | Le seul disque de la VM (16 Go) |
| Version | **pfSense CE 2.9.0** | La stable actuelle |

> 📷 **Capture manquante** : les écrans ZFS / GPT / disque `da0` / choix de version.

**10.4** Confirme : l'installation dure quelques minutes.

❌ **Problème du lab** : à la fin, le bouton **Reboot** de l'installateur ouvre un shell et
l'affichage **se fige**. L'installation était pourtant terminée (« Post Installation setup… done »).
**Correction** :
1. Dans Proxmox, **Matériel** > **Lecteur CD/DVD** > **Éditer** > **Ne pas utiliser de média** > **OK**
   (on « éjecte » l'ISO) ;
2. En haut à droite, **Réinitialiser** la VM.
ZFS encaisse cette coupure sans dégât.

**10.5** Au démarrage, attends le **menu console**.

<img src="captures/19-menu-console-pfsense-2-9.png" width="640">

> 📸 **Ce que tu dois voir** : « Bootup complete », **Welcome to pfSense 2.9.0-RELEASE (amd64)**, puis :  
> - `WAN (wan) -> vtnet0 -> v4: 192.168.1.211/24`  
> - `LAN (lan) -> vtnet1.99 -> v4: 10.10.99.254/24`
>
> et le menu numéroté de **0** à **16** (les options **7) Ping host** et **8) Shell** servent juste après).

✅ **Vérification** : WAN en `.211/24`, LAN en `10.10.99.254/24` sur `vtnet1.99`.

---

### Étape 11 · Tester le réseau, du plus proche au plus loin

🎯 Prouver que pfSense sort bien sur Internet.

💡 **Pourquoi du plus proche au plus loin** : si la box ne répond pas, inutile de tester Internet.
On trouve **où** ça casse.

**11.1** Dans le menu console, tape `7` (**Ping host**) puis **Entrée**, et donne `192.168.1.254`.

<img src="captures/20-recette-ping-box.png" width="560">

> 📸 **Ce que tu dois voir** : 3 réponses `64 bytes from 192.168.1.254`, **0.0% packet loss**,  
> environ 0,7 ms. **Le WAN et vmbr0 fonctionnent.** Appuie sur **Entrée** pour revenir au menu.

**11.2** Recommence avec `1.1.1.1` (un serveur sur Internet, chez Cloudflare).

<img src="captures/21-recette-ping-internet.png" width="560">

> 📸 **Ce que tu dois voir** : 3 réponses de `1.1.1.1`, **0.0% packet loss**, environ 4,8 ms.  
> **Le routage vers Internet marche.**

**11.3** Recommence avec un **nom** : `netgate.com`.

<img src="captures/22-recette-dns-erreur.png" width="560">

> 📸 **❌ Ce que j'ai eu** : **`ping: UDP connect: Invalid argument`**.  
> On pourrait croire que le DNS (la traduction nom → adresse) est en panne. **Vérifions avant de  
> conclure.**

**11.4** Tape `8` (**Shell**) puis :

```sh
drill netgate.com A
```

💡 `drill` interroge le DNS ; `A` demande l'adresse **IPv4** du nom.

<img src="captures/23-recette-dns-drill-ok.png" width="560">

> 📸 **Ce que tu dois voir** : `rcode: NOERROR`, et dans **ANSWER SECTION** deux adresses  
> `199.60.103.104` et `199.60.103.4`, avec `SERVER: 192.168.1.254`. **Le DNS répond très bien.**

**11.5** Force le ping en IPv4 :

```sh
ping -4 -c 3 netgate.com
```

💡 `-4` = IPv4 obligatoire ; `-c 3` = 3 essais seulement.

<img src="captures/24-recette-ping-nom-ipv4-ok.png" width="560">

> 📸 **Ce que tu dois voir** : `PING netgate.com (199.60.103.104)`, 3 réponses, **0.0% packet loss**.

💡 **Cause** : sans `-4`, le nom était traduit en adresse **IPv6**, alors que pfSense n'a **pas**
d'IPv6 configuré. Rien de cassé.

**11.6** Tape `exit` pour revenir au menu.

✅ **Vérification** : box, Internet et Internet par nom (en IPv4) répondent.

---

## Partie 5 — Accéder à l'interface web

### Étape 12 · Ouvrir un accès temporaire depuis le PC d'administration

💡 **Le problème** : le PC d'administration est sur le réseau de la box, **côté WAN**. Deux obstacles :
**le routage** (la box ne connaît pas les réseaux 10.10.x cachés derrière pfSense) et **le filtrage**
(pfSense bloque **tout** ce qui arrive par le WAN : c'est son rôle).

🎯 Ouvrir **un seul** accès, **pour un seul PC**, **temporairement**.

**12.1** Dans la console de pfSense, tape `8` (**Shell**) puis :

```sh
pfctl -d
```

💡 `pfctl -d` = « **d**ésactive le filtrage » (*pf disabled*), **juste** le temps de créer la règle.
⚠️ Pendant ce temps, pfSense ne filtre **plus rien** : fais vite.

<img src="captures/25-pfctl-desactive-temporaire.png" width="720">

> 📸 **Ce que tu dois voir** : sous la commande, **`pf disabled`**. (Le numéro d'appareil Netgate est  
> masqué.)

**12.2** Sur le PC d'administration, ouvre `https://192.168.1.211`, accepte l'alerte de certificat
autosigné (comme pour Proxmox : **Paramètres avancés** > **Continuer**).

<img src="captures/26-webgui-connexion.png" width="640">

> 📸 **Ce que tu dois voir** : la page **pfsense — SIGN IN** avec **Username** et **Password**.

**12.3** Connecte-toi avec le compte par défaut `admin` / `pfsense`.
⚠️ Ce couple est **connu de tout le monde** : on le change à l'étape 13.

**12.4** Menu **Firewall** > **Rules**, onglet **WAN**, bouton **Add** (flèche vers le haut).

**12.5** Remplis le formulaire :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Action | **Pass** | Laisser passer |
| Interface | WAN | Le trafic **arrive** par le WAN |
| Address Family | IPv4 | |
| Protocol | **TCP** | HTTPS utilise TCP |
| Source | **Address or Alias** : `192.168.1.98` | **Le seul** PC admin, pas tout le réseau de la box |
| Destination | **This Firewall (self)** | pfSense lui-même |
| Destination Port Range | **HTTPS (443)** de… à… | Seulement l'interface web |
| Log | ✅ | Garder une trace de chaque connexion |
| Description | `TEMP webGUI PC admin .98 - suppr. apres switch` | Le mot **TEMP** rappelle qu'elle doit disparaître |

<img src="captures/27-regle-wan-webgui-formulaire.png" width="720">

> 📸 **Ce que tu dois voir** : **Edit Firewall Rule** avec Action **Pass**, Interface **WAN**, IPv4,  
> **TCP**, Source **192.168.1.98**, Destination **This Firewall (self)**, port **HTTPS (443)**,  
> Log coché et la description.

**12.6** Clique sur **Save**.

<img src="captures/28-regles-wan-liste.png" width="720">

> 📸 **Ce que tu dois voir** : **Firewall / Rules / WAN** avec le bandeau jaune **« The firewall rule  
> configuration has been changed »** et le bouton vert **Apply Changes**. Deux règles : **Block bogon  
> networks** (automatique) et ta règle **192.168.1.98 → This Firewall 443**.

**12.7** Clique sur **Apply Changes**.
💡 **Apply réactive le filtrage**, et l'accès reste ouvert **grâce à la règle**.

<img src="captures/29-dashboard-fw01-pare-feu-actif.png" width="720">

> 📸 **Ce que tu dois voir** : le **Dashboard** (tableau de bord), avec **Name fw01.lab.home.arpa**,  
> **Version 2.9.0-RELEASE**, **User admin@192.168.1.98**, et en bas **Interfaces : WAN 192.168.1.211,  
> LAN 10.10.99.254**. Tu es connecté **alors que le filtrage est actif**.

**12.8** **Vérifie sans supposer** que le filtrage est actif : **Diagnostics** > **Command Prompt**,
tape dans **Execute Shell Command** :

```sh
pfctl -s info | head -1
```

puis **Execute**.

<img src="captures/30-verif-pf-enabled.png" width="720">

> 📸 **Ce que tu dois voir** : **`Status: Enabled`**. ✅ Le pare-feu filtre.

🏢 Cette règle est un **écart** : on l'enlève dès que le PC admin sera branché sur le VLAN 99 (switch,
brique 02). En entreprise, on n'administre **jamais** un pare-feu par son côté Internet.

---

### Étape 13 · L'assistant de configuration

**13.1** Menu **System** > **Setup Wizard**, puis **Next** à chaque écran :

| Écran | Valeur | Pourquoi |
| --- | --- | --- |
| Hostname / Domain | `fw01` / `lab.home.arpa` | Nom du rôle ; `home.arpa` est réservé aux réseaux privés (RFC 8375) |
| Primary / Secondary DNS | `192.168.1.254` / `1.1.1.1` | Deux serveurs : si l'un tombe, l'autre répond |
| Override DNS | ❌ | Le résolveur de pfSense interroge lui-même les serveurs racines |
| Timezone | `Europe/Paris` | Journaux à la bonne heure ; l'AD (Kerberos) refuse plus de 5 min d'écart |
| WAN : Upstream Gateway | `192.168.1.254` | La route par défaut (la sortie vers Internet) |
| **Block RFC1918 Private Networks** | ❌ **décoché** | Le WAN est lui-même dans un réseau **privé** (celui de la box) : sinon le PC admin serait bloqué |
| Block bogon networks | ✅ | Bloque les adresses qui ne doivent jamais exister sur Internet |
| Admin Password | **nouveau mot de passe**, rangé dans le gestionnaire | Le couple `admin` / `pfsense` est **public** |

**13.2** Termine l'assistant (**Reload**, puis **Finish**).

> 📷 **Captures manquantes** : les écrans de l'assistant.

✅ **Vérification** : reconnecte-toi avec le **nouveau** mot de passe ; le Dashboard affiche
`fw01.lab.home.arpa`.

---

## Partie 6 — Créer les VLAN

### Étape 14 · Déclarer les VLAN sur la carte trunk

🎯 Dire à pfSense quels numéros de VLAN existent sur `vtnet1`.

**14.1** Menu **Interfaces** > **Assignments**, onglet **VLANs**, bouton **Add**.

**14.2** Remplis, puis **Save** :

| Champ | Valeur |
| --- | --- |
| Parent Interface | `vtnet1` |
| VLAN Tag | `10` |
| VLAN Priority | vide |
| Description | `SERVEURS` |

**14.3** Recommence pour **20 POSTES**, **30 WIFI_SALARIES**, **40 WIFI_INVITES**.

**14.4** Le VLAN **99** existe déjà (créé à l'installation) : clique sur son crayon ✏️ et mets la
description `ADMINISTRATION`.

<img src="captures/31-liste-vlan.png" width="640">

> 📸 **Ce que tu dois voir** : **Interfaces / VLANs**, 5 lignes sur **vtnet1** : 99 ADMINISTRATION,  
> 10 SERVEURS, 20 POSTES, 30 WIFI_SALARIES, 40 WIFI_INVITES.

---

### Étape 15 · Transformer chaque VLAN en interface

**15.1** Onglet **Interface Assignments**. En bas, dans **Available network ports**, choisis
**VLAN 10 on vtnet1 (SERVEURS)**, puis **Add**.

**15.2** Recommence pour les VLAN 20, 30 et 40. **Save**.

<img src="captures/32-assignation-interfaces-vlan.png" width="720">

> 📸 **Ce que tu dois voir** : « Interface has been added », puis **WAN** (vtnet0), **LAN** (VLAN 99),  
> **OPT1** (VLAN 10), **OPT2** (VLAN 20), **OPT3** (VLAN 30), **OPT4** (VLAN 40).  
> 💡 OPT1…OPT4 sont des noms provisoires : on les renomme juste après.

**15.3** Clique sur **OPT1**, puis remplis :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Enable | ✅ **Enable interface** | Sans ça, l'interface reste éteinte |
| Description | `SERVEURS` | Un nom lisible au lieu d'OPT1 |
| IPv4 Configuration Type | **Static IPv4** | Une passerelle a une adresse fixe |
| IPv6 Configuration Type | None | Pas d'IPv6 dans le lab |
| IPv4 Address | `10.10.10.254` | |
| ⚠️ **Masque** (liste à droite de l'adresse) | **24** | Par défaut, la liste affiche **32** ! Voir étape 16 |
| IPv4 Upstream gateway | **None** | ⭐ Une interface **interne** n'a jamais de passerelle : **c'est pfSense, la passerelle** de ce réseau |
| Block private networks / bogon | ❌ décochés | Ce sont des réseaux internes |

**15.4** Clique sur **Save**, puis sur **Apply Changes**.

<img src="captures/33-opt1-serveurs-config.png" width="720">

> 📸 **Ce que tu dois voir** : **Interfaces / OPT1 (vtnet1.10)** avec Enable coché, Description  
> **SERVEURS**, **Static IPv4**, IPv6 **None**, IPv4 Address **10.10.10.254** / **24**, Upstream  
> gateway **None**.

**15.5** Recommence pour les 3 autres :

| Interface | Description | Adresse |
| --- | --- | --- |
| OPT2 | `POSTES` | `10.10.20.254` / **24** |
| OPT3 | `WIFI_SALARIES` | `10.10.30.254` / **24** |
| OPT4 | `WIFI_INVITES` | `10.10.40.254` / **24** |

<img src="captures/35-opt4-wifi-invites-config.png" width="720">

> 📸 **Ce que tu dois voir (OPT4)** : **WIFI_INVITES**, **10.10.40.254 / 24**, gateway **None**.

---

### Étape 16 · Dépannage : un masque /32 oublié

❌ Pour **POSTES** et **WIFI_SALARIES**, j'avais laissé le masque sur **/32** (la valeur par défaut de la
liste, à droite de l'adresse).

<img src="captures/34-erreur-masque-32-postes.png" width="720">

> 📸 **L'erreur** : **Interfaces / POSTES (vtnet1.20)**, adresse **10.10.20.254** et, juste à droite,  
> **/ 32**. Le bandeau vert « changes have been applied successfully » montre que **pfSense l'a accepté  
> sans rien dire**.

💡 **Conséquence** : `/32` = un réseau d'**une seule adresse**. Aucun poste du VLAN n'aurait pu joindre
sa passerelle, et le serveur DHCP aurait refusé de démarrer.

**16.1** Corrige : remets **24**, **Save**, **Apply Changes** (pour POSTES et WIFI_SALARIES).

**16.2** **Prouve** le résultat : **Diagnostics** > **Command Prompt** :

```sh
ifconfig | grep "inet 10."
```

💡 `ifconfig` liste les cartes ; `grep "inet 10."` ne garde que les lignes avec une adresse en 10.x.

<img src="captures/37-verif-masques-ifconfig.png" width="720">

> 📸 **Ce que tu dois voir** : 5 lignes, **toutes** avec **`netmask 0xffffff00`** :  
> `10.10.10.254`, `10.10.20.254`, `10.10.30.254`, `10.10.40.254`, `10.10.99.254`.  
> 💡 `0xffffff00` = 255.255.255.0 = **/24** (écrit en hexadécimal). Un /32 afficherait `0xffffffff`.

<img src="captures/36-dashboard-6-interfaces.png" width="720">

> 📸 **Ce que tu dois voir sur le Dashboard** : le cadre **Interfaces** avec **6 interfaces** et leur  
> adresse : WAN 192.168.1.211, LAN 10.10.99.254, SERVEURS 10.10.10.254, POSTES 10.10.20.254,  
> WIFI_SALARIES 10.10.30.254, WIFI_INVITES 10.10.40.254.

💡 **Leçon** : on **relit** chaque formulaire, et on **prouve** le résultat par une commande.

✅ **Vérification** : 5 adresses internes en `0xffffff00`.

---

## Partie 7 — DHCP et règles du VLAN Postes

### Étape 17 · Un DHCP temporaire pour les postes

💡 En production, le DHCP des postes sera fait par **Windows Server** (brique 03) : il inscrit les PC
dans le DNS de l'Active Directory. Comme une demande DHCP est un **cri dans la pièce** (*broadcast*)
qui ne sort pas de son VLAN, pfSense fera alors **relais** vers le serveur.

🎯 En attendant, donner des adresses aux postes du VLAN 20 depuis pfSense.

**17.1** Menu **Services** > **DHCP Server**, onglet **POSTES**.

**17.2** Remplis :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Enable | ✅ | |
| Address Pool Range | `10.10.20.100` à `10.10.20.199` | `.1` à `.99` réservées aux adresses fixes (imprimantes, équipements) |
| Default lease time | `7200` (2 h) | Bail court tant que c'est temporaire |

**17.3** Clique sur **Save** (en bas).

<img src="captures/40-dhcp-postes-config.png" width="420">

> 📸 **Ce que tu dois voir** : la page DHCP de **POSTES**, Subnet `10.10.20.0/24`, plage  
> `10.10.20.100` → `10.10.20.199`, Default Lease Time `7200`.

---

### Étape 18 · Les règles du VLAN Postes

💡 **Comment le vigile lit sa liste** :
- sans aucune règle, une interface **bloque tout** (refus par défaut) ;
- les règles sont lues **de haut en bas**, et **la première qui correspond gagne**.

Donc : **les interdictions précises d'abord, l'autorisation large ensuite.**

⚠️ **Une règle se pose sur l'onglet de l'interface d'où VIENT le trafic.** Posée sur l'onglet LAN
avec la source POSTES, elle ne bloquerait **jamais rien**, sans aucun message d'erreur.

**18.1** Menu **Firewall** > **Rules**, onglet **POSTES**.

**18.2** Clique sur **Add** et crée la règle 1, **Save**. Puis la 2, puis la 3 (avec **Add** flèche
vers le bas, pour l'ajouter **en dessous**) :

| # | Action | Protocole | Source | Destination | Port | Log | Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **Block** | any | POSTES subnets | **LAN subnets** (l'administration) | tout | ✅ | `Postes vers admin interdit` |
| 2 | **Block** | TCP | POSTES subnets | **This Firewall (self)** | 443 (HTTPS) | ✅ | `Postes vers webGUI interdit` |
| 3 | **Pass** | any | POSTES subnets | any | tout | ❌ | `Postes vers Internet et reseau` |

| Règle | Pourquoi |
| --- | --- |
| 1 | Un poste ne touche **jamais** aux équipements d'administration |
| 2 | Un salarié ne doit pas ouvrir l'interface du pare-feu par **sa propre passerelle** (`10.10.20.254`) |
| 3 | Le reste (Internet…) : **provisoire**, à affiner plus tard (moindre privilège) |

**18.3** Clique sur **Apply Changes**.

<img src="captures/43-regles-postes.png" width="720">

> 📸 **Ce que tu dois voir** : **Firewall / Rules / POSTES**, dans l'ordre : deux règles avec une  
> **croix rouge** ✖ (Block) vers **LAN subnets** et **This Firewall (self) 443**, puis une règle avec  
> une **coche verte** ✔ (Pass) vers `*`. Le bandeau vert confirme que les changements sont appliqués.

💡 On **journalise ce qui est bloqué**, pas le trafic normal (sinon les journaux débordent).

---

## Partie 8 — La recette (on prouve que la segmentation marche)

### Étape 19 · Une VM de test dans le VLAN Postes

🎯 Se mettre **à la place d'un poste** du VLAN 20 et vérifier ce qu'il peut faire, et surtout ce qu'il
**ne peut pas** faire.

💡 Dans une recette, on teste **ce qui doit marcher** ET **ce qui doit être bloqué**. Un pare-feu qui
laisse tout passer « marche » aussi…

**19.1** Téléverse l'ISO **Alpine Linux** (`alpine-virt-3.24.2-x86_64.iso`) dans **local > Images ISO**
(comme à l'étape 2).

**19.2** **Créer une VM** : ID `900`, nom `test-poste`, ISO Alpine, **pas de disque** (on la démarre en
« live »), 1 cœur, 512 Mio, carte réseau **VirtIO** sur **vmbr1** avec **Étiquette VLAN = 20**.

<img src="captures/38-vm-test-poste-vlan20.png" width="640">

> 📸 **Ce que tu dois voir dans Confirmation** : `cores 1`, `memory 512`, `name test-poste`,  
> **`net0 virtio,bridge=vmbr1,tag=20`**, `ide2 local:iso/alpine-virt-3.24.2-x86_64.iso`, `vmid 900`.  
> 💡 **tag=20** : cette carte est **dans le VLAN 20**, comme un vrai PC branché sur une prise « Postes ».

**19.3** Démarre la VM, ouvre la **Console**, connecte-toi en `root` (pas de mot de passe en live).

---

### Étape 20 · Les tests, un par un

**20.1** Demande une adresse **avant** d'avoir créé le DHCP (étape 17) :

```sh
udhcpc
```

<img src="captures/39-dhcp-echec-sans-serveur.png" width="640">

> 📸 **Ce que j'ai vu** : d'abord des dizaines de `read error: Network is down` : la carte réseau est  
> **éteinte** en mode live. Puis, après `ip link set eth0 up` (allumer la carte), plusieurs  
> **`broadcasting discover`** et **`failed to get a DHCP lease`**.  
> 💡 Échec **attendu** : à ce moment, aucun serveur DHCP ne répondait dans le VLAN 20.

**20.2** Allume la carte (si ce n'est pas fait), puis redemande une adresse **après** l'étape 17 :

```sh
ip link set eth0 up
udhcpc
```

<img src="captures/41-dhcp-bail-obtenu-dora.png" width="640">

> 📸 **Ce que tu dois voir** à la fin : **`broadcasting select for 10.10.20.100, server 10.10.20.254`**  
> puis **`lease of 10.10.20.100 obtained from 10.10.20.254, lease time 7200`**.  
> ✅ Le poste a reçu la **première adresse** de la plage, donnée par pfSense, pour 2 h.

💡 **DORA**, les 4 temps du DHCP : **D**iscover (le poste crie « il y a un serveur DHCP ? »),
**O**ffer (pfSense propose une adresse), **R**equest (le poste l'accepte), **A**ck (pfSense confirme).

**20.3** Teste la passerelle **avant** d'avoir créé les règles (étapes 19 et 20) :

```sh
ping 10.10.20.254
```

<img src="captures/42-ping-bloque-sans-regle.png" width="560">

> 📸 **Ce que j'ai vu** : **`100% packet loss`** vers `10.10.20.254`.  
> 💡 Normal : sans règle, l'interface POSTES **refuse tout** (refus par défaut). Arrête avec **Ctrl + C**.

**20.4** Après l'étape 18, lance la série de tests :

| Test | Commande | Résultat attendu | Ce que ça prouve |
| --- | --- | --- | --- |
| Internet | `ping 1.1.1.1` | ✅ Réponses, 0 % de perte | La règle 3 laisse sortir |
| Internet par nom | `ping google.com` | ✅ Réponses | Le DNS marche aussi |
| Administration | `ping 10.10.99.254` | ✅ **100 % de perte** | Règle 1 : bloqué |
| Interface web du pare-feu | `nc 10.10.20.254 443` | ✅ **Pas de réponse** | Règle 2 : bloqué |

💡 `nc` (*netcat*) essaie d'ouvrir une connexion sur un port. S'il reste bloqué sans rien afficher,
le port est **fermé pour nous**. On arrête avec **Ctrl + C**.

<img src="captures/44-recette-segmentation-postes.png" width="560">

> 📸 **Ce que tu dois voir** :  
> - `ping 1.1.1.1` → 3 réponses, **0% packet loss** ;  
> - `ping google.com` (172.217.22.110) → 3 réponses, **0% packet loss** ;  
> - `ping 10.10.99.254` → **4 packets transmitted, 0 received, 100% packet loss** ;  
> - `nc 10.10.20.254 443` → rien, puis `^C` (arrêt manuel).
>
> (En haut, une première série vers 1.1.1.1 montre 96 % de perte : c'était **avant** l'application  
> des règles.)

✅ **Vérification finale** : Internet ✅, administration ❌ bloquée, interface du pare-feu ❌ bloquée.
**La segmentation fonctionne.**

---

## Annexes

### A. Dépannage — récapitulatif

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| « Cannot set WAN interface IP address » | Le LAN par défaut (192.168.1.1/24) est dans le **même réseau** que le WAN | Configurer le **LAN d'abord** dans un autre réseau |
| Le bouton Reboot fige l'installateur | Bug d'affichage en fin d'installation | Éjecter l'ISO, **Réinitialiser** la VM |
| `ping: UDP connect: Invalid argument` sur un nom | Le nom est résolu en **IPv6**, non configuré | `drill nom A` pour vérifier le DNS, `ping -4` |
| Impossible d'ouvrir l'interface web depuis le PC | Le WAN bloque tout, c'est normal | Règle WAN temporaire (étape 12), à supprimer ensuite |
| Les postes d'un VLAN n'ont pas d'adresse | Masque en **/32**, ou DHCP pas activé sur l'onglet du VLAN | `ifconfig \| grep "inet 10."`, Services > DHCP Server |
| `Network is down` dans la VM de test | Carte éteinte en mode live | `ip link set eth0 up` |
| Une règle « ne fait rien » | Posée sur le **mauvais onglet** (pas celui d'où vient le trafic) | La déplacer sur l'onglet de l'interface source |
| Tout passe alors que ça devrait bloquer | La règle « Pass any » est **au-dessus** des Block | Glisser les Block **en haut**, Save, Apply |

### B. Antisèche — les commandes de la brique

| Commande | Où | À quoi elle sert |
| --- | --- | --- |
| `sha256sum fichier.iso` | Linux / WSL | Empreinte d'un fichier |
| `ping` / `arp -a` | Windows | Tester une adresse / voir qui a répondu sur le réseau local |
| `pfctl -d` | Shell pfSense | **Désactiver** le filtrage (dépannage uniquement !) |
| `pfctl -s info \| head -1` | Shell pfSense | Voir si le filtrage est actif (`Status: Enabled`) |
| `drill nom A` | Shell pfSense | Interroger le DNS (adresse IPv4) |
| `ping -4 -c 3 nom` | Shell pfSense | Ping forcé en IPv4, 3 essais |
| `ifconfig \| grep "inet 10."` | Shell pfSense | Vérifier les adresses et masques internes |
| `ip link set eth0 up` | Alpine | Allumer la carte réseau |
| `udhcpc` | Alpine | Demander une adresse DHCP |
| `nc adresse port` | Alpine | Tester si un port est ouvert |

### C. Utilisation en entreprise : 3 cas concrets

1. **Un poste infecté** essaie de scanner le réseau d'administration : la règle 1 le bloque, et la
   tentative apparaît dans les journaux.
2. **Un invité** se connecte au Wi-Fi : il a Internet, mais ne voit ni les serveurs ni les postes.
3. **Un nouveau salarié** branche son PC dans le VLAN Postes : il reçoit une adresse et hérite des
   règles du VLAN, sans rien configurer sur le poste.

### D. Questions d'entretien (avec la réponse)

- **Pourquoi des VLAN ?** Pour segmenter : chaque groupe de machines a son réseau, et le pare-feu
  contrôle ce qui passe de l'un à l'autre.
- **Qu'est-ce qu'un trunk ?** Un lien qui transporte plusieurs VLAN étiquetés (802.1Q). Avec un routeur
  qui route entre eux sur un seul lien : « router on a stick ».
- **Dans quel ordre sont lues les règles ?** De haut en bas, la première qui correspond gagne ; tout ce
  qui n'est pas autorisé est interdit.
- **Combien d'adresses utilisables dans un /24 ?** 254 : `.0` est le réseau, `.255` le broadcast.
- **Pourquoi le DHCP a-t-il besoin d'un relais entre VLAN ?** La demande est un broadcast, qui reste dans
  son VLAN ; le relais la transmet au serveur.
- **Comment dépanner un « ça ne passe pas » ?** Deux questions : le chemin existe-t-il (routage) ?
  Quelqu'un bloque-t-il (filtrage) ? Et on teste du plus proche au plus loin.
- **Pourquoi une adresse fixe pour un pare-feu ?** Règles, VPN et documentation s'appuient dessus.
- **Que veut dire un masque 0xffffff00 ?** 255.255.255.0, soit /24.

### E. Écarts entre le lab et l'entreprise

| Dans le lab | En entreprise | Pourquoi l'écart, et le risque |
| --- | --- | --- |
| Pare-feu en **VM** sur le même serveur que tout le reste | Boîtier dédié, souvent en paire haute disponibilité (CARP) | Si Proxmox tombe ou est compromis, le pare-feu tombe avec |
| Règles « → tout » (`any`) au départ | Une règle par besoin (moindre privilège) | Serveurs corrigé à la brique 03 ; Postes en cours (règle GLPI ajoutée à la brique 05) |
| Règle WAN temporaire vers l'interface web | Administration depuis le VLAN d'administration seulement | Pas de switch au départ. À supprimer après la brique 02 |
| `pfctl -d` utilisé pour créer la première règle | Accès console ou réseau d'administration dès le départ | Quelques minutes sans filtrage, côté réseau de la box seulement |
| DHCP temporaire sur pfSense | DHCP Windows (intégré à l'AD) + relais | Remplacé à la brique 03 |
| Blocage RFC1918 décoché sur le WAN | Coché : le WAN est sur Internet | Le WAN est dans le réseau de la box (double NAT de lab) |
| Pas de sauvegarde de configuration au départ | Sauvegarde avant chaque modification | Faite à partir du 11 oct. ([procédure pare-feu](../docs/procedure-pare-feu.md)) ; les fichiers XML ne sont **jamais** publiés (ils contiennent des secrets) |
| Journaux uniquement en local | Envoi vers un serveur central (syslog, SIEM) | Prévu avec Wazuh (brique 11) |
| Fuseau réglé sans redémarrer | Redémarrage planifié après les réglages système | Journaux en UTC jusqu'au redémarrage du 12 oct. |
| Domaine `lab.home.arpa` | `ad.entreprise.fr` | Windows classe les zones `.arpa` en inversées (briques 03 et 05) |

### F. Points en suspens

- Règles des VLAN Wi-Fi (30, 40), avec des groupes d'interfaces : avec la borne Wi-Fi.
- Supprimer la règle WAN temporaire une fois l'accès par le VLAN 99 vérifié depuis ADM-001.
- Activer l'accélération AES-NI (System > Advanced) et un SSH sécurisé.
- Remplacer petit à petit la règle provisoire « Postes → tout » par des règles précises
  ([matrice des flux](../docs/matrice-des-flux.md)).

### G. Captures manquantes (à compléter lors d'une prochaine installation)

| Étape | Écran à photographier |
| --- | --- |
| 1.2 | Boutique Netgate : choix AMD64 / ISO |
| 1.3 | Résultat de `gzip -t`, `gunzip`, `sha256sum` |
| 3.3 | Fenêtre « Créer : Linux Bridge » remplie |
| 10.3 | Choix ZFS, GPT, disque `da0`, version CE 2.9.0 |
| 13 | Les écrans de l'assistant de configuration |
| 14.2 | Fenêtre d'ajout d'un VLAN |
| 18.2 | Formulaire d'une règle Block de l'onglet POSTES |

### H. Lexique

| Mot | Sens |
| --- | --- |
| **Broadcast** | Un message envoyé à **tout le monde** dans un réseau (il ne sort pas du VLAN) |
| **DORA** | Discover, Offer, Request, Ack : les 4 temps du DHCP |
| **FreeBSD** | Le système (cousin de Linux) sur lequel tourne pfSense |
| **Netmask** | Le masque : quelle partie de l'adresse désigne le réseau |
| **pf** | *Packet Filter* : le moteur de filtrage de pfSense |
| **RFC1918** | Les plages d'adresses privées : 10.x, 172.16-31.x, 192.168.x |
| **Bogon** | Adresse qui ne devrait jamais apparaître sur Internet (non attribuée) |
| **Tag VLAN** | L'étiquette (numéro de VLAN) ajoutée à un paquet sur un trunk |
| **vtnet** | Le nom des cartes réseau VirtIO dans FreeBSD |
| **WAN / LAN** | Côté Internet / côté réseau interne |
