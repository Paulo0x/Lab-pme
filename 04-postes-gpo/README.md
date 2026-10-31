# Brique 04 — Postes de travail Windows 11, GPO et LAPS

> **Tuto pas à pas pour quelqu'un qui débute complètement.**  
> Chaque action a son numéro. Chaque capture est placée **juste sous l'action qu'elle montre**, avec  
> une légende qui dit **ce que tu dois voir** et **quoi faire si ce n'est pas pareil**.  
> Les étapes sont faites à l'interface graphique ; les commandes PowerShell équivalentes sont en  
> annexe B. Les vraies erreurs faites pendant le lab sont gardées, avec leur correction.

---

## 🧾 Fiche de la brique

| | |
| --- | --- |
| **Objectif** | Installer un **poste de travail** Windows 11, le **joindre au domaine**, **prouver** que les GPO s'appliquent, l'**administrer à distance**, puis le **durcir** (LAPS, comptes locaux, délégation) |
| **Durée** | Environ **10 h** (en 3 ou 4 séances) |
| **Niveau** | Débutant, après la [brique 03](../03-active-directory/) |
| **Résultat** | `PC-001` (Windows 11 Entreprise 25H2) dans le domaine, rangé dans `Postes-fixes` ; 4 GPO en place ; RSOP à distance depuis SRV-AD01 ; MachineAccountQuota à 0 ; délégation de la jonction ; Windows LAPS chiffré |
| **Brique précédente** | [03 · Active Directory](../03-active-directory/) — **brique suivante** : [05 · GLPI](../05-glpi/) |

### Ce qu'il faut avant de commencer

| Élément | Détail |
| --- | --- |
| SRV-AD01 | Domaine `lab.home.arpa`, DNS, DHCP + relais pfSense sur le VLAN 20 (brique 03) |
| ISO **Windows 11 Entreprise Évaluation** (français) | 90 jours gratuits : centre d'évaluation Microsoft (`https://www.microsoft.com/evalcenter`). ⚠️ **Pas** l'ISO grand public |
| ISO virtio-win | Déjà dans Proxmox (brique 03) |
| Ressources libres | 2 cœurs, 4 Go de RAM, 64 Go de disque |
| Un compte salarié | `nathalie.girard` (Comptabilité), créé par le script de la brique 03 |

### Les GPO en place à la fin de la brique

| GPO | Liée à | Rôle |
| --- | --- | --- |
| `C_Securite_Verrouillage_Inactivite` | Ordinateurs | Verrouille la session après 600 s (créée en brique 03, **testée ici**) |
| `C_Securite_PareFeu_Administration` | Ordinateurs | Ouvre WMI dans le pare-feu Windows, **depuis SRV-AD01 seulement**, profil Domaine |
| `C_Config_Alimentation` | **Postes-fixes** | Écran éteint après 15 min, jamais de veille sur secteur |
| `C_Securite_LAPS` | Ordinateurs | Mot de passe du compte local de secours, unique, chiffré, changé tous les 30 jours |

### Ce que tu sauras faire à la fin

- Installer Windows 11 dans Proxmox et **réparer une licence** d'évaluation non activée.
- **Joindre un PC au domaine** proprement (nom, DNS, bonne OU).
- **Prouver** qu'une GPO s'applique (registre, chronomètre, rapport RSOP).
- Dépanner un « **serveur RPC indisponible** » à travers **deux pare-feu**.
- **Durcir** l'annuaire et le poste : MachineAccountQuota, comptes locaux, délégation AGDLP.
- Déployer **Windows LAPS** avec une extension du schéma en « **juste à temps** ».

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

**Sur quelle machine ?** Chaque action précise **PC-001** (le poste) ou **SRV-AD01** (le serveur).

---

## 🗂️ Sommaire

- [Partie 0 — Comprendre avant de commencer](#partie-0--comprendre-avant-de-commencer)
- [Partie 1 — Créer et installer le poste](#partie-1--créer-et-installer-le-poste) (étapes 1 à 5)
- [Partie 2 — Joindre le poste au domaine](#partie-2--joindre-le-poste-au-domaine) (étapes 6 à 10)
- [Partie 3 — Tester les GPO](#partie-3--tester-les-gpo) (étapes 11 à 13)
- [Partie 4 — Administrer le poste à distance](#partie-4--administrer-le-poste-à-distance) (étapes 14 à 18)
- [Partie 5 — Durcir l'annuaire et le poste](#partie-5--durcir-lannuaire-et-le-poste) (étapes 19 à 21)
- [Partie 6 — LAPS](#partie-6--laps--un-mot-de-passe-admin-local-unique-par-poste) (étapes 22 à 27)
- [Annexes](#annexes) : sécurité, PowerShell, dépannage, écarts, entreprise, entretien, lexique

---

## Partie 0 — Comprendre avant de commencer

### 0.1 Le besoin

AEROTRANS veut des postes de travail :

- **intégrés au domaine** : un salarié se connecte avec **son** compte, sur n'importe quel PC ;
- qui **appliquent tout seuls** les règles de l'entreprise (verrouillage, alimentation) ;
- que l'informatique peut **administrer à distance**, sans se déplacer ;
- **durcis** : un pirate qui prend la main sur un PC ne doit pas pouvoir **rebondir** sur les autres.

### 0.2 Les mots à connaître

| Mot | Sens | Image |
| --- | --- | --- |
| **Joindre au domaine** | Inscrire le PC dans l'AD : il fait confiance au domaine et applique ses règles | **Embaucher** le PC dans l'entreprise |
| **GPO** | Un paquet de réglages appliqué automatiquement à une OU | Une **note de service** |
| **RSOP** | Le rapport « quelles GPO s'appliquent vraiment sur ce PC, et laquelle gagne » | Le **bilan** des notes de service reçues |
| **RPC / WMI** | Les mécanismes qui permettent d'interroger un PC **à distance** | Le **téléphone** de l'administration |
| **LAPS** | Un mot de passe admin local **différent sur chaque PC**, changé tout seul | Une **serrure différente** par bureau, au lieu d'un passe-partout |
| **Mouvement latéral** | Un pirate qui passe d'un PC à l'autre avec le même mot de passe | Le cambrioleur qui a le **passe-partout** |

### 0.3 Les choix

| Besoin | Choix | Alternatives | Pourquoi |
| --- | --- | --- | --- |
| Système des postes | **Windows 11 Entreprise** (évaluation 90 j) | Windows 11 Pro | Édition des grandes entreprises, celle qu'on gère en ESN. La Pro suffit en PME |
| Réglages des postes | **GPO** | Intune (cloud) | Les postes sont joints à l'AD local. Intune : brique 08 |
| Mot de passe admin local | **Windows LAPS** (intégré) | Ancien LAPS (abandonné), mot de passe identique partout | Unique par PC, changé tout seul, chiffré dans l'AD |
| Compte géré par LAPS | **Gestion automatique** (`secours.local`) | `Administrateur` intégré réactivé | Possible car tous les postes sont en Windows 11 24H2 ou plus (étape 26) |

### 0.4 Le schéma

```
          VLAN 10 Serveurs                         VLAN 20 Postes
          10.10.10.0/24                            10.10.20.0/24
   SRV-AD01 10.10.10.10                        PC-001 10.10.20.101 (DHCP)
   AD DS · DNS · DHCP · GPO · LAPS             Windows 11 Entreprise 25H2
          |                                          |
          +-------------- pfSense (fw01) ------------+
            relais DHCP · refus par défaut · règle :
            SRV-AD01 → Postes en RPC/WMI uniquement
```

Adresses : [plan d'adressage](../docs/plan-adressage.md) · Flux : [matrice des flux](../docs/matrice-des-flux.md) ·
Noms : [conventions](../docs/conventions.md).

---

## Partie 1 — Créer et installer le poste

### Étape 1 · La bonne ISO, vérifiée

🎯 Avoir l'installateur de **Windows 11 Entreprise**, vérifié.

**1.1** Proxmox > **local (pve01)** > **Images ISO** > **Téléverser** : choisis l'ISO, **Algorithme de
hachage = SHA-256**, colle l'empreinte publiée par Microsoft.

<img src="captures/01a-upload-iso-win11-sha256.png" width="520">

> 📸 **Ce que tu vois** : **Téléverser**, fichier `Windows11_Client_x64_fr-fr_26300_9457.iso`  
> (8,44 Gio), **SHA-256**, somme de contrôle collée.  
> ❌ **Erreur du lab** : c'est l'ISO **grand public** (Famille/Pro). Elle ne permet pas d'avoir  
> l'édition Entreprise. Je l'ai remplacée (1.3).

**1.2** Clique sur **Téléverser** et attends.

<img src="captures/01b-upload-iso-win11-en-cours.png" width="520">

> 📸 **Ce que tu vois** : la barre de progression (33 %).

<img src="captures/01-upload-iso-win11-checksum-ok.png" width="720">

> 📸 **Ce que tu dois voir** : **checksum verified** puis **TASK OK**.

**1.3** Téléverse la bonne ISO, **Windows 11 Entreprise Évaluation** (`…CLIENTENTERPRISEEVAL…`), de la
même façon, puis supprime l'ISO grand public (sélectionne-la > **Supprimer**).

<img src="captures/02-iso-win11-entreprise-eval.png" width="720">

> 📸 **Ce que tu dois voir** : la tâche **TASK OK** pour `26200.6584…CLIENTENTERPRISEEVAL…fr-fr.iso`.

<img src="captures/02b-iso-entreprise-sha256-ok-grand-public-supprimee.png" width="720">

> 📸 **Ce que tu dois voir** : dans **Images ISO**, l'ISO **Entreprise** (6,61 Gio) ; plus d'ISO grand  
> public utilisée.

---

### Étape 2 · Créer la VM 300 · PC-001

**2.1** **Créer une VM**, case **Avancé** cochée, et remplis :

| Onglet | Réglage | Valeur | Pourquoi |
| --- | --- | --- | --- |
| Général | ID / Nom | `300` / `PC-001` | 3xx = postes ; convention `PC-NNN` |
| Système d'exploitation | ISO / type | Windows 11 Entreprise / **Microsoft Windows 11/2022/2025** ; ✅ lecteur pour les pilotes VirtIO | |
| Système | Machine / BIOS | **q35**, **OVMF (UEFI)** + disque EFI, ✅ clefs de préinscription, ✅ **TPM 2.0** | Exigences de Windows 11 (démarrage sécurisé, puce TPM) |
| Disques | Taille | `64` Gio, SCSI, ✅ **Abandonner (discard)**, ✅ **SSD**, ✅ IO thread | Discard : l'espace libéré par Windows est rendu à Proxmox |
| Processeur | | `2` cœurs, **host** | |
| Mémoire | | `4096` | Le minimum de Windows 11 |
| Réseau | | **VirtIO**, `vmbr1`, **Étiquette de VLAN 20** | Directement dans le VLAN Postes |

**2.2** **Relis l'onglet Confirmation** avant **Terminer**.

<img src="captures/03-creation-vm-pc001-confirmation.png" width="560">

> 📸 **Ce que tu dois voir** : `efidisk0 …pre-enrolled-keys=1`, `ide0 virtio-win.iso`, `ide2` l'ISO  
> Entreprise, `machine q35`, `memory 4096`, `name PC-001`, **`net0 virtio,bridge=vmbr1,tag=20`**,  
> `ostype win11`, **`scsi0 local-lvm:64,ssd=on,iothread=on,discard=on`**, `tpmstate0 …version=v2.0`,  
> `vmid 300`.  
> 💡 `discard=on` a été ajouté **en relisant** ce récapitulatif.

---

### Étape 3 · Installer Windows 11

**3.1** Démarre la VM > **Console**. Comme pour le serveur (brique 03) : **aucun disque visible** →
**Charger un pilote** > virtio-win > **`vioscsi\w11\amd64`** > **Installer**. Choisis le disque de
64 Go, puis l'édition **Windows 11 Entreprise Évaluation**.

> 📷 **Captures manquantes** : le chargement du pilote et le choix du disque (identiques à la brique 03,  
> avec `w11` au lieu de `2k25`).

**3.2** Configuration de Windows (OOBE) : pays **France** > **Oui**, clavier **Français** > **Oui**.

<img src="captures/04-oobe-pays-region.png" width="640">

> 📸 **Ce que tu dois voir** : **Est-ce le bon pays ou la bonne région ?** avec **France** sélectionné.

**3.3** ❌ **Pas de réseau** : la carte VirtIO n'a pas encore de pilote.

<img src="captures/05-oobe-reseau-sans-pilote.png" width="560">

> 📸 **Ce que tu vois** : **Il est temps de vous connecter à un réseau**, sans aucun réseau listé, avec  
> **Installer le pilote** et, en bas, **Je n'ai pas Internet**.

Clique sur **Je n'ai pas Internet** > **Continuer avec une configuration limitée**.

**3.4** Windows crée un **compte local** : nomme-le `tech.install` (mot de passe au coffre).

<img src="captures/06-oobe-compte-local.png" width="560">

> 📸 **Ce que tu vois** : **Qui utilisera cet appareil ?** et le champ **Entrez votre nom**.  
> 💡 Ce compte **temporaire** sert uniquement à l'installation. On le **désactivera** à l'étape 20.

**3.5** Sur le bureau : Explorateur > lecteur **virtio-win** > double-clic sur
**virtio-win-guest-tools** > installer : tous les pilotes (réseau compris) + l'agent QEMU.

> 📷 **Capture manquante** : l'installation de virtio-win-guest-tools.

---

### Étape 4 · Dépannage : « La licence Windows a expiré »

❌ **Symptôme** : dès la première connexion, un message en bas à droite du bureau.

<img src="captures/07-bureau-licence-expiree.png" width="640">

> 📸 **Ce que tu vois** : en bas à droite « Version d'évaluation de Windows 11 Entreprise. **La licence  
> Windows a expiré** ». Session `tech.install`.

**4.1** Clic droit sur **Démarrer** > **Terminal (administrateur)**, puis :

```
slmgr /dlv
```

<img src="captures/08-slmgr-dlv-eval-non-activee.png" width="560">

> 📸 **Ce que tu vois** : **Nom : Windows(R), EnterpriseEval edition**, description **TIMEBASED_EVAL  
> channel**, **Statut de la licence : notification**, **Raison : 0xC004F009 (la période de grâce a  
> expiré)**.  
> 💡 L'évaluation **n'a jamais été activée** : elle a été installée **hors ligne** (étape 3.3).

**4.2** Maintenant que le réseau marche, active :

```
slmgr /ato
```

<img src="captures/09-slmgr-ato-produit-active.png" width="560">

> 📸 **Ce que tu dois voir** : **Activation de Windows(R), EnterpriseEval edition … Le produit a été  
> activé.**

**4.3** Vérifie la date de fin :

```
slmgr /xpr
```

<img src="captures/10-slmgr-xpr-expiration-janvier-2027.png" width="560">

> 📸 **Ce que tu dois voir** : **L'activation avec date d'expiration expirera le 11/01/2027** (90 jours  
> à partir de l'activation).

| Commande | Sens |
| --- | --- |
| `slmgr /dlv` | Afficher le **détail** de la licence |
| `slmgr /ato` | **Activer** en ligne |
| `slmgr /xpr` | Afficher la date d'**expiration** |

🏢 En entreprise : licences en volume, **activées automatiquement** par l'AD (*Active Directory Based
Activation*) ou un serveur KMS. Personne ne tape `slmgr` poste par poste.

---

### Étape 5 · Vérifier l'adresse IP

**5.1** Sur PC-001 : `ipconfig /all`

<img src="captures/11-ipconfig-all-bail-dhcp-vlan20.png" width="560">

> 📸 **Ce que tu dois voir** : **Adresse IPv4 10.10.20.101**, masque 255.255.255.0, **passerelle  
> 10.10.20.254**, **Serveur DHCP 10.10.10.10**, **Serveurs DNS 10.10.10.10**, suffixe  
> **lab.home.arpa**, bail de **8 jours** (obtenu le 13, expire le 21).  
> 💡 Le **relais DHCP** de pfSense marche dans les deux sens : la demande du poste est arrivée au  
> serveur Windows, et la réponse est revenue. Le nom est encore `DESKTOP-…` : on le change à l'étape 6.

---

## Partie 2 — Joindre le poste au domaine

### Étape 6 · Renommer le PC **avant** de le joindre

💡 Le compte de l'ordinateur est créé dans l'AD **avec le nom du moment**. Renommer après la jonction
crée des incohérences (DNS, identifiants Kerberos).

**6.1** **Windows + R** > `sysdm.cpl` > **Entrée** > onglet **Nom de l'ordinateur** > **Modifier**.

**6.2** Nom de l'ordinateur : `PC-001` > **OK** > redémarre.

<img src="captures/12-sysdm-renommer-pc-001.png" width="420">

> 📸 **Ce que tu dois voir** : **Modification du nom ou du domaine de l'ordinateur**, Nom  
> **PC-001**, encore **Groupe de travail : WORKGROUP**.

**6.3** Vérifie : `hostname`

<img src="captures/13-hostname-pc-001.png" width="560">

> 📸 **Ce que tu dois voir** : **PC-001**.

---

### Étape 7 · Vérifier que le PC trouve le contrôleur de domaine

**7.1** Sur PC-001 :

```powershell
Resolve-DnsName -Type SRV _ldap._tcp.dc._msdcs.lab.home.arpa
```

<img src="captures/14-dns-srv-ldap-dc-ok.png" width="640">

> 📸 **Ce que tu dois voir** : **SRV** → **srv-ad01.lab.home.arpa**, port **389**, et son adresse  
> **10.10.10.10**.  
> 💡 C'est **grâce à cet enregistrement** qu'un PC trouve le DC. S'il ne répond pas, la jonction  
> échouera : on vérifie **avant**.

---

### Étape 8 · Joindre le domaine

**8.1** `sysdm.cpl` > **Modifier** > **Membre d'un : Domaine** : `lab.home.arpa` > **OK**.

<img src="captures/15-sysdm-jonction-domaine-lab-home-arpa.png" width="420">

> 📸 **Ce que tu dois voir** : Nom **PC-001**, ⦿ **Domaine : lab.home.arpa**.

**8.2** Windows demande un compte **autorisé à joindre** : `adm.paulo.rosa@lab.home.arpa` + son mot
de passe > **OK**.

<img src="captures/16a-jonction-identifiants-adm.png" width="560">

> 📸 **Ce que tu dois voir** : **Sécurité Windows**, Nom d'utilisateur **adm.paulo.rosa@lab.home.arpa**,  
> mot de passe masqué.

<img src="captures/16-bienvenue-domaine-lab-home-arpa.png" width="560">

> 📸 **Ce que tu dois voir** : **Bienvenue dans le domaine lab.home.arpa.** > **OK**, puis  
> redémarre.

<img src="captures/17-ecran-connexion-apres-jonction.png" width="560">

> 📸 **Ce que tu vois** au redémarrage : `tech.install` et surtout **Autre utilisateur** : on peut  
> maintenant se connecter avec un compte **du domaine**.

---

### Étape 9 · Ranger le PC dans la bonne OU

**9.1** Sur SRV-AD01 : **Utilisateurs et ordinateurs AD** > `AEROTRANS` > **Ordinateurs**.

<img src="captures/18-aduc-pc001-dans-ordinateurs.png" width="560">

> 📸 **Ce que tu dois voir** : **PC-001** (Ordinateur) dans **Ordinateurs**, et **pas** dans  
> `Computers` : c'est grâce à `redircmp` (brique 03).

**9.2** Clic droit sur **PC-001** > **Déplacer** > **Postes-fixes** > **OK**.

<img src="captures/19-aduc-pc001-dans-postes-fixes.png" width="560">

> 📸 **Ce que tu dois voir** : **PC-001** dans **Ordinateurs > Postes-fixes**.  
> 💡 Les GPO dépendent de l'OU : la GPO d'alimentation (étape 13) ne vise que `Postes-fixes`.

**9.3** Vérifie que la GPO de verrouillage s'appliquera : **Gestion des stratégies de groupe** >
`AEROTRANS` > **Ordinateurs** > `C_Securite_Verrouillage_Inactivite`.

<img src="captures/20-gpmc-gpo-verrouillage-liee-ordinateurs.png" width="560">

> 📸 **Ce que tu dois voir** : onglet **Étendue**, liaison **Ordinateurs**, **Lien activé : Oui**,  
> filtrage **Utilisateurs authentifiés** (qui inclut les ordinateurs). Postes-fixes en **hérite**.

---

### Étape 10 · La première connexion d'une salariée

**10.1** Sur PC-001 : **Autre utilisateur** > `nathalie.girard` > son mot de passe provisoire.

<img src="captures/21-premiere-connexion-mdp-a-changer.png" width="420">

> 📸 **Ce que tu dois voir** : **Le mot de passe de l'utilisateur doit être modifié avant la première  
> connexion.** > **OK** (réglé par le script d'import, brique 03).

**10.2** Tape un nouveau mot de passe (12 caractères minimum, complexe) deux fois.

<img src="captures/22-mdp-change.png" width="420">

> 📸 **Ce que tu dois voir** : **Votre mot de passe a été changé.** > **OK**.

**10.3** Ouvre PowerShell (en simple utilisatrice) et vérifie :

```powershell
whoami
gpresult /r /scope user
whoami /groups | findstr /i "admin"
```

<img src="captures/23-whoami-nathalie-girard.png" width="560">

> 📸 **Ce que tu dois voir** : `whoami` → **lab\nathalie.girard** : connectée avec son compte **du  
> domaine**.

<img src="captures/24-gpresult-user-nathalie.png" width="460">

> 📸 **Ce que tu dois voir** : `CN=Nathalie Girard,OU=Comptabilite,OU=Utilisateurs,OU=AEROTRANS…`,  
> stratégie appliquée depuis **SRV-AD01.lab.home.arpa**, **Objets Stratégie de groupe appliqués :  
> N/A**, et dans les groupes **GG_Comptabilite**.  
> 💡 Aucune GPO **utilisateur** : normal, nos GPO n'ont que des paramètres **ordinateur**.

<img src="captures/25-whoami-groups-pas-admin.png" width="560">

> 📸 **Ce que tu dois voir** : `whoami /groups | findstr /i "admin"` ne renvoie **rien** ✅ :  
> Nathalie n'est **pas admin** (moindre privilège).

---

## Partie 3 — Tester les GPO

### Étape 11 · Preuve n° 1 : la valeur dans le registre

💡 Une GPO écrit ses réglages dans le **registre** du PC. Si la valeur est là, la GPO est arrivée.

**11.1** Sur PC-001 (session de Nathalie), dans PowerShell :

```powershell
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name InactivityTimeoutSecs
```

<img src="captures/27b-registre-inactivitytimeoutsecs-600.png" width="640">

> 📸 **Ce que tu dois voir** : **inactivitytimeoutsecs : 600** ✅ (lisible en simple utilisatrice).  
> 💡 Équivalent à la souris : `regedit` > `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`.

---

### Étape 12 · Preuve n° 2 : le chronomètre

🎯 Vérifier que la session se verrouille **au bout de 10 minutes**, pas avant, pas après.

**12.1** Note l'heure, ne touche plus à rien.

<img src="captures/27c-chrono-depart-21h45.png" width="560">

> 📸 **Ce que tu vois** : le bureau de Nathalie, horloge à **21:45**.

<img src="captures/27a-session-nathalie-verrouillee.png" width="560">

> 📸 **❌ Ce que j'ai eu** : l'écran de verrouillage **Nathalie Girard**… **avant** les 10 minutes.

**12.2** Cherche pourquoi : **Paramètres** > **Système** > **Marche/Arrêt** > **Délai d'expiration de
l'écran**.

<img src="captures/27d-alimentation-ecran-5-min.png" width="560">

> 📸 **Ce que tu vois** : **Sur secteur, Désactiver l'écran après : 5 minutes (nos recommandations)**.  
> 💡 **Cause** : Windows 11 **éteint l'écran après 5 minutes** par défaut, et l'extinction de l'écran  
> **verrouille aussi** la session. **Le premier mécanisme qui se déclenche gagne.**

**12.3** ✅ **Méthode** : **neutraliser l'un pour tester l'autre**. Passe l'écran à **15 minutes**,
puis relance le chrono.

<img src="captures/27e-chrono-depart-21h58.png" width="560">

> 📸 **Départ** : **21:58**.

<img src="captures/27f-verrouillage-gpo-22h08-pile-10-min.png" width="560">

> 📸 **Ce que tu dois voir** : l'écran de verrouillage à **22:08** pile ✅ = 10 minutes = la GPO.

💡 **Correction durable** : la GPO d'alimentation (étape 13) règle l'écran à 15 min sur tous les postes
fixes.

---

### Étape 13 · La GPO d'alimentation des postes fixes

💡 **Pourquoi seulement les postes fixes ?** Un **PC fixe** qui se met en veille rate les mises à jour de
nuit, les sauvegardes et l'administration à distance → **jamais de veille**. Un **portable** sur
batterie **doit** se mettre en veille (batterie, chauffe dans le sac) → il ne reçoit pas cette GPO.
C'est tout l'intérêt d'avoir deux sous-OU.

**13.1** Sur SRV-AD01 : **Gestion des stratégies de groupe** > clic droit sur l'OU **Postes-fixes** >
**Créer un objet GPO dans ce domaine, et le lier ici** > `C_Config_Alimentation` > **OK**.

💡 « Config » et non « Securite » : c'est du confort et du fonctionnement (voir conventions).

<img src="captures/46-gpo-alimentation-liee-postes-fixes.png" width="640">

> 📸 **Ce que tu dois voir** : **C_Config_Alimentation**, liaison **Postes-fixes**  
> (`lab.home.arpa/AEROTRANS/Ordinateurs/Postes-fixes`), lien activé.

**13.2** Clic droit sur la GPO > **Modifier** > Configuration ordinateur > Stratégies > Modèles
d'administration > Système > **Gestion de l'alimentation** > **Paramètres de l'affichage et de la
vidéo** > **Désactiver l'affichage (sur secteur)** > **Activé**, **900** secondes > **OK**.

<img src="captures/47a-gpo-alimentation-ecran-secteur-900s.png" width="560">

> 📸 **Ce que tu dois voir** : ⦿ **Activé**, **Désactiver l'affichage (secondes) : 900**.  
> 💡 15 min : **plus** que les 10 min du verrouillage. C'est donc la GPO de verrouillage qui décide.

**13.3** **Paramètres de la veille** > **Spécifier le délai de veille du système (sur secteur)** >
**Activé**, **0** > **OK**.

<img src="captures/47b-gpo-alimentation-veille-secteur-0-jamais.png" width="560">

> 📸 **Ce que tu dois voir** : ⦿ **Activé**, **Délai de mise en veille du système (secondes) : 0** =  
> jamais.

❌ **Pièges dans la liste** : « délai de veille **prolongée** » (c'est l'hibernation) et « délai de veille
**si l'ordinateur n'est pas utilisé** » (après un réveil automatique) ne sont **pas** les bons.

**13.4** Sur PC-001 : `gpupdate /force`, puis **Paramètres** > **Système** > **Marche/Arrêt**.

<img src="captures/48a-pc-001-ecran-15-min-grise.png" width="560">

> 📸 **Ce que tu dois voir** : **Désactiver l'écran après : 15 minutes**, **grisé** ✅ : Nathalie ne  
> peut pas le changer. La ligne « veille » n'apparaît pas (voir 13.5).

**13.5** Pourquoi pas de ligne « veille » ? Dans l'invite de commandes :

```
powercfg /a
```

<img src="captures/48b-powercfg-a-vm-sans-veille.png" width="560">

> 📸 **Ce que tu vois** : **Les états de veille suivants ne sont pas disponibles** (S1, S2, S3,  
> veille prolongée…) : « **L'hyperviseur ne prend pas en charge cet état** ». La VM ne gère aucune  
> veille, donc Windows cache l'option.

**13.6** Vérifie quand même la valeur appliquée :

```
powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
```

<img src="captures/48c-powercfg-standbyidle-secteur-0.png" width="640">

> 📸 **Ce que tu dois voir** : **Index actuel du paramètre de courant alternatif : 0x00000000** (sur  
> secteur = jamais ✅) ; **courant continu : 0x00000258** (= 600 s sur batterie, non touché).

---

## Partie 4 — Administrer le poste à distance

### Étape 14 · Le besoin, et l'erreur « serveur RPC indisponible »

🎯 Depuis SRV-AD01, lancer **Résultats de stratégie de groupe** (RSOP) sur PC-001 : savoir quelles
GPO s'appliquent, **sans se déplacer**.

**14.1** **Gestion des stratégies de groupe** > clic droit sur **Résultats de stratégie de groupe** >
**Assistant Résultats de stratégie de groupe** > **Suivant** > ⦿ **Un autre ordinateur** :
`LAB\PC-001` > **Suivant**.

<img src="captures/26a-assistant-rsop-pc001.png" width="560">

> 📸 **Ce que tu vois** : **Sélection des ordinateurs**, ⦿ **Un autre ordinateur : LAB\PC-001**.

<img src="captures/26b-rsop-erreur-rpc-indisponible.png" width="560">

> 📸 **❌ Ce que tu vois** : **Échec de la connexion à LAB\PC-001 … Vérifiez que le service WMI est  
> activé … Le serveur RPC n'est pas disponible.**

---

### Étape 15 · Diagnostic : il y a deux pare-feu sur le chemin

**15.1** Sur SRV-AD01, teste le port de RPC :

```powershell
Test-NetConnection 10.10.20.101 -Port 135
```

<img src="captures/28-test-netconnection-135-false.png" width="560">

> 📸 **Ce que tu vois** : **TCP connect to (10.10.20.101 : 135) failed**, **Ping … TimedOut**,  
> **TcpTestSucceeded : False**.

**15.2** Dans pfSense : **Status** > **System Logs** > **Firewall**.

<img src="captures/29a-pfsense-logs-avant-filtre.png" width="640">

> 📸 **Ce que tu vois** : beaucoup de lignes ; clique sur l'en-tête **Source** pour trier.

<img src="captures/29-pfsense-deny-serveurs-vers-pc001-135.png" width="640">

> 📸 **Ce que tu dois voir** : ✖ **SERVEURS · Default deny rule IPv4** depuis **10.10.10.10** vers  
> **10.10.20.101:135** (TCP:S).  
> → **pfSense bloque** : le VLAN Serveurs est au moindre privilège depuis la brique 03.

💡 **Comment marche RPC** : comme un **standard téléphonique**. On appelle d'abord le **port 135**, qui
répond « rappelle WMI sur tel **port dynamique** » (entre 49152 et 65535). Il faut donc ouvrir **les
deux**.

---

### Étape 16 · Premier pare-feu : pfSense

🎯 Autoriser **seulement SRV-AD01** à joindre les postes en RPC/WMI.

💡 Méthode : [procédure pare-feu](../docs/procedure-pare-feu.md) : besoin écrit dans la matrice des
flux (ligne 7), **sauvegarde de la configuration**, photo des règles avant.

**16.1** **Diagnostics** > **Backup & Restore** > **Download configuration as XML**.

<img src="captures/30-pfsense-backup-avant-regle-serveurs-postes.png" width="640">

> 📸 **Ce que tu vois** : **Backup Configuration**, Backup area **All**, bouton **Download configuration  
> as XML**.  
> ⚠️ Ce fichier contient des secrets : il ne se publie **jamais** (il est exclu de GitHub).

**16.2** Photographie les règles **avant** : **Firewall** > **Rules** > **SERVEURS**.

<img src="captures/31-pfsense-regles-serveurs-avant.png" width="640">

> 📸 **Ce que tu vois** : les 6 règles de la brique 03 (2 Block, DNS, NTP, web Internet, ping).

**16.3** **Firewall** > **Aliases** > onglet **Ports** > **Add** :

| Champ | Valeur |
| --- | --- |
| Name | `PORTS_RPC_WMI` |
| Description | `RPC 135 + ports dynamiques (admin a distance des postes)` |
| Type | Port(s) |
| Port 1 | `135` — `RPC endpoint mapper` |
| Port 2 | `49152:65535` — `RPC dynamiques` |

**Save** > **Apply Changes**.

<img src="captures/32-pfsense-alias-ports-rpc-wmi.png" width="640">

> 📸 **Ce que tu dois voir** : **PORTS_RPC_WMI**, ports **135** et **49152:65535**.  
> 💡 Dans pfSense, une plage s'écrit avec **deux-points** (`49152:65535`), pas avec un tiret.

**16.4** **Rules** > **SERVEURS** > **Add** (flèche vers le bas, **en fin de liste**) :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Action | Pass | |
| Protocol | TCP | |
| Source | **Address or Alias** : `10.10.10.10` | **Moindre privilège** : un autre serveur du VLAN (le futur GLPI) ne peut pas s'en servir |
| Destination | **POSTES subnets** | |
| Destination port | (other) `PORTS_RPC_WMI` | |
| Description | `Autorise SRV-AD01 vers POSTES RPC/WMI (admin a distance)` | 57 caractères maximum, sans accents |

<img src="captures/33a-pfsense-regle-destination-any-a-corriger.png" width="640">

> 📸 **❌ Mon 1er essai** : la **Destination** est restée sur **Any**.  
> La règle aurait « marché », mais elle ouvrait RPC vers **tous** les réseaux, Internet compris.  
> 👉 **Une règle trop large fonctionne aussi** : c'est pour ça qu'on teste **ce qui doit être bloqué**.

<img src="captures/33b-pfsense-regle-srv-ad01-vers-postes-rpc.png" width="640">

> 📸 **Ce que tu dois voir (corrigé)** : Source **10.10.10.10**, Destination **POSTES subnets**, port  
> **PORTS_RPC_WMI**.

**16.5** **Save** > **Apply Changes**.

<img src="captures/34-pfsense-regles-serveurs-apres.png" width="640">

> 📸 **Ce que tu dois voir** : une 7e règle en bas : **10.10.10.10 → POSTES subnets, PORTS_RPC_WMI**,  
> « Autorise SRV-AD01 vers POSTES RPC/WMI ».

**16.6** Reteste depuis SRV-AD01 :

```powershell
Test-NetConnection 10.10.20.101 -Port 135
Test-NetConnection PC-001 -Port 135
```

<img src="captures/35-test-netconnection-135-ip-false-nom-true.png" width="560">

> 📸 **Ce que tu vois** : 1er test par l'IP → encore **False** ; 2e test par le nom → **True**.  
> ❌ pfSense était en train de **recharger les règles** (bandeau *reloading in the background*) :  
> quelques secondes d'attente suffisent.

<img src="captures/36-test-netconnection-135-ip-true.png" width="560">

> 📸 **Ce que tu dois voir** : par l'IP aussi, **TcpTestSucceeded : True** ✅.

💡 Le **ping**, lui, échoue toujours alors que pfSense l'autorise : c'est le **pare-feu Windows** du
poste qui refuse de répondre. Preuve qu'il y a bien **un deuxième pare-feu**.

**16.7** Refais une sauvegarde de pfSense (16.1) : configuration modifiée = nouvelle sauvegarde.

---

### Étape 17 · Deuxième pare-feu : Windows, par GPO

**17.1** Relance l'assistant RSOP (14.1).

<img src="captures/37-rsop-erreur-rpc-pare-feu-windows.png" width="560">

> 📸 **❌ Toujours** : « Le serveur RPC n'est pas disponible ». Le port 135 répond, mais le **pare-feu  
> Windows** de PC-001 refuse le **port dynamique** de WMI.

🏢 **En entreprise, on ne règle jamais le pare-feu poste par poste** : une GPO s'applique à tous les PC,
y compris les futurs.

**17.2** GPMC > clic droit sur l'OU **Ordinateurs** > **Créer un objet GPO dans ce domaine, et le lier
ici** > `C_Securite_PareFeu_Administration` > **OK**.

<img src="captures/38-gpo-pare-feu-admin-creee-liee-ordinateurs.png" width="560">

> 📸 **Ce que tu dois voir** : sous **Ordinateurs**, **C_Securite_PareFeu_Admini…** à côté de la GPO de  
> verrouillage.

**17.3** Clic droit sur la GPO > **Modifier** > Configuration ordinateur > Stratégies > Paramètres
Windows > Paramètres de sécurité > **Pare-feu Windows Defender avec fonctions avancées de sécurité** >
déplie > **Règles de trafic entrant** > clic droit > **Nouvelle règle**.

**17.4** ⦿ **Prédéfinie** > dans la liste, choisis **Infrastructure de gestion Windows (WMI)** >
**Suivant**.

💡 C'est le nom **français** de WMI : il est rangé à la lettre **I**, pas à W.

<img src="captures/39-gpo-regles-predefinies-wmi.png" width="560">

> 📸 **Ce que tu dois voir** : **Règles prédéfinies**, les 3 règles **Windows Management  
> Instrumentation (DCOM-In)**, **(WMI-In)**, **(ASync-In)**, toutes cochées.

**17.5** **Suivant** > ⦿ **Autoriser la connexion** > **Terminer**.

<img src="captures/40-gpo-3-regles-wmi-creees.png" width="640">

> 📸 **Ce que tu vois** : les 3 règles dans **Règles de trafic entrant**, profil **Tout** pour  
> l'instant (on restreint juste après).

| Règle | Rôle |
| --- | --- |
| WMI (DCOM-In) | Le « standard » sur le port 135 |
| WMI (WMI-In) | Le service WMI, sur le port dynamique |
| WMI (ASync-In) | Les réponses envoyées plus tard (asynchrones) |

**17.6** **Sur chacune des 3 règles** (double-clic) :
- onglet **Étendue** > **Adresse IP distante** > ⦿ **Ces adresses IP** > **Ajouter** > `10.10.10.10` >
  **OK** ;
- onglet **Avancé** > **Profils** : ✅ **Domaine** uniquement (❌ Privé, ❌ Public) > **OK**.

<img src="captures/41a-regle-dcom-in-etendue-10.10.10.10.png" width="460">

> 📸 **DCOM-In, Étendue** : Adresse IP distante ⦿ **Ces adresses IP : 10.10.10.10**.

<img src="captures/41b-regle-dcom-in-avance-domaine.png" width="460">

> 📸 **DCOM-In, Avancé** : profil **Domaine** ✅, Privé ❌, Public ❌.

<img src="captures/41c-regle-wmi-in-etendue-10.10.10.10.png" width="460">

> 📸 **WMI-In, Étendue** : **10.10.10.10**.

<img src="captures/41d-regle-wmi-in-avance-domaine.png" width="460">

> 📸 **WMI-In, Avancé** : **Domaine** seulement.

<img src="captures/41e-regle-async-in-etendue-ajout-ip.png" width="460">

> 📸 **ASync-In, Étendue** : la petite fenêtre **Adresse IP** > ⦿ **Cette adresse IP ou ce  
> sous-réseau : 10.10.10.10**.

<img src="captures/41f-regle-async-in-avance-domaine.png" width="460">

> 📸 **ASync-In, Avancé** : **Domaine** seulement.

<img src="captures/42-gpo-3-regles-wmi-profil-domaine.png" width="640">

> 📸 **Ce que tu dois voir** : les 3 règles WMI, profil **Domaine**, Activée **Oui**, Action  
> **Autoriser**.

💡 **Profil Domaine** : la règle ne s'ouvre qu'**au bureau** (quand le PC voit le domaine), jamais sur
le Wi-Fi d'un hôtel (profil Public). Et la même restriction « SRV-AD01 seulement » existe **sur le
réseau** (pfSense) **et sur le poste** : c'est la **défense en profondeur**.

**17.7** Sur PC-001 : `gpupdate /force` (pas besoin de redémarrer : les règles de pare-feu s'appliquent
tout de suite).

<img src="captures/43-gpupdate-ok-gpresult-computer-acces-refuse.png" width="560">

> 📸 **Ce que tu dois voir** : « La mise à jour de la stratégie d'ordinateur s'est terminée sans  
> erreur ». Puis `gpresult /r /scope computer` → **Erreur : Accès refusé**.  
> 💡 Normal : une utilisatrice ne voit pas les réglages de l'ordinateur. On vérifie **depuis le  
> serveur** (étape 18).

---

### Étape 18 · Le résultat : le rapport RSOP

**18.1** Sur SRV-AD01, relance l'assistant RSOP sur `LAB\PC-001` > **Suivant**.

<img src="captures/44a-rsop-selection-utilisateur-nathalie-ok.png" width="560">

> 📸 **Ce que tu dois voir** : **Sélection de l'utilisateur**, avec **LAB\nathalie.girard** dans la  
> liste ✅. Cette liste vient de **WMI** : la connexion marche !

**18.2** **Suivant** jusqu'à **Terminer**.

<img src="captures/44b-rsop-rapport-cree-ie-esc-bloque-affichage.png" width="560">

> 📸 **Ce que tu vois** : un message **Internet Explorer** : « Le contenu de cette application … est  
> bloqué par la Configuration de sécurité renforcée d'Internet Explorer ».  
> ❌ Ce n'est **pas** une erreur réseau : le rapport est une page web, et Windows Server bloque les  
> pages web (un serveur ne sert pas à naviguer). Clique sur **Fermer**, **sans** ajouter le site aux  
> sites de confiance.

**18.3** Lis le rapport **nathalie.girard sur PC-001** (onglet **Détails**).

<img src="captures/45a-rsop-rapport-pc-001-general.png" width="640">

> 📸 **Ce que tu dois voir** : **Nom de l'ordinateur LAB\PC-001**, domaine `lab.home.arpa`, **Unité  
> d'organisation `lab.home.arpa/AEROTRANS/Ordinateurs/Postes-fixes`**, et l'état des composants  
> **Opération réussie**.

<img src="captures/45b-rsop-verrouillage-600s-gpo-gagnante.png" width="640">

> 📸 **Ce que tu dois voir** : **Ouverture de session interactive : limite d'inactivité de  
> l'ordinateur = 600 secondes**, **OSG gagnant : C_Securite_Verrouillage_Inactivite** ✅.

<img src="captures/45c-rsop-pare-feu-osg-c-securite-parefeu-admin.png" width="640">

> 📸 **Ce que tu dois voir** : **Pare-feu Windows avec sécurité avancée** : OSG gagnant  
> **C_Securite_PareFeu_Administration**.

<img src="captures/45d-rsop-regle-dcom-in-10.10.10.10-domaine.png" width="640">

> 📸 **DCOM-In** : port local **135**, **Étendue distante 10.10.10.10**, **Profil Domaine** ✅.

<img src="captures/45e-rsop-regle-async-in-10.10.10.10-domaine.png" width="640">

> 📸 **ASync-In** : programme `unsecapp.exe`, étendue **10.10.10.10**, profil **Domaine** ✅.

<img src="captures/45f-rsop-regle-wmi-in-10.10.10.10-domaine.png" width="640">

> 📸 **WMI-In** : service `winmgmt`, étendue **10.10.10.10**, profil **Domaine** ✅.

✅ **Vérification** : l'administration à distance marche, et elle est limitée à SRV-AD01.

---

## Partie 5 — Durcir l'annuaire et le poste

### Étape 19 · `ms-DS-MachineAccountQuota` à 0

💡 Par défaut, **n'importe quel utilisateur du domaine peut joindre 10 ordinateurs**. Risques : un PC
personnel non géré dans le domaine, et surtout un **faux compte ordinateur** créé par un pirate, point
de départ de plusieurs attaques d'élévation de privilèges.

**19.1** Sur SRV-AD01 : **Windows + R** > `adsiedit.msc` > clic droit sur **Modification ADSI** >
**Connexion** > **Contexte d'attribution de noms par défaut** > **OK**.

**19.2** Déplie, clic droit sur **DC=lab,DC=home,DC=arpa** > **Propriétés** > onglet **Éditeur
d'attributs** > descends jusqu'à **ms-DS-MachineAccountQuota**.

<img src="captures/49-adsiedit-machineaccountquota-10-avant.png" width="640">

> 📸 **Ce que tu vois (avant)** : **ms-DS-MachineAccountQuota = 10**.  
> ⚠️ ADSI Edit montre **tous** les attributs bruts de l'annuaire, **sans garde-fou** : on ne touche qu'à  
> ce qui est prévu.

**19.3** **Modifier** > `0` > **OK** > **Appliquer**.

<img src="captures/50-adsiedit-machineaccountquota-0-apres.png" width="560">

> 📸 **Ce que tu dois voir (après)** : **ms-DS-MachineAccountQuota = 0**.

**19.4** Vérifie en PowerShell :

```powershell
Get-ADObject (Get-ADDomain).DistinguishedName -Properties ms-DS-MachineAccountQuota
```

<img src="captures/51-powershell-machineaccountquota-0-guid-floute.png" width="560">

> 📸 **Ce que tu dois voir** : **ms-DS-MachineAccountQuota : 0** ✅ (l'identifiant ObjectGUID est  
> masqué).  
> 💡 Rien n'est cassé : PC-001 est déjà joint, et les admins du domaine gardent le droit de joindre.  
> Les autres auront une **délégation** (étape 21).

---

### Étape 20 · Désactiver le compte local d'installation

💡 `tech.install` (étape 3) est un **administrateur local**, avec un mot de passe qui n'expire jamais,
et plus utilisé : **une porte dérobée idéale**.

**20.1** Depuis la session de Nathalie, ouvre **Gestion de l'ordinateur** > **Utilisateurs et groupes
locaux** > **Utilisateurs** > double-clic sur `tech.install` > coche **Le compte est désactivé** >
**Appliquer**.

<img src="captures/52a-tech-install-desactivation-acces-refuse-nathalie.png" width="560">

> 📸 **❌ Ce que tu vois** : **L'erreur suivante s'est produite … pour l'utilisateur tech.install :  
> Accès refusé.**  
> 💡 Normal (moindre privilège) : Nathalie n'est pas admin, la console est en lecture seule.

**20.2** **Démarrer** > tape `Gestion de l'ordinateur` > clic droit > **Exécuter en tant
qu'administrateur** > dans la fenêtre UAC, saisis un compte **admin du domaine**.

**20.3** **Utilisateurs** > double-clic sur `tech.install` > ✅ **Le compte est désactivé** > **OK**.

<img src="captures/52b-tech-install-desactive-en-admin.png" width="560">

> 📸 **Ce que tu dois voir** : **Propriétés de tech.install**, ✅ **Le compte est désactivé**.  
> 💡 **Désactivé plutôt que supprimé** : retour arrière en un clic si besoin.

<img src="captures/53-utilisateurs-locaux-tous-desactives.png" width="560">

> 📸 **Ce que tu dois voir** : Administrateur, DefaultAccount, Invité, **tech.install**,  
> WDAGUtilityAccount : tous avec une **petite flèche vers le bas** sur l'icône = **désactivés** ✅.

---

### Étape 21 · Déléguer la jonction des PC, sans être admin du domaine

🎯 Le technicien qui installe les PC n'a pas à détenir **les clés du domaine**. On lui donne **juste** le
droit de joindre des PC dans l'OU Ordinateurs.

💡 **Méthode AGDLP** : on ne donne jamais un droit à une personne, mais à un groupe :

```
paulo.rosa (compte du quotidien, non admin)
   ∈ GG_Informatique (groupe global, existant)
      ∈ DL_OU-Ordinateurs_JoindrePC (groupe domaine local, nouveau, avec description)
         → reçoit la délégation sur l'OU Ordinateurs
```

Un 2e technicien arrive ? On l'ajoute à `GG_Informatique`, **sans retoucher aux permissions**.

**21.1** OU **Groupes** > clic droit > **Nouveau** > **Groupe** :
- nom `DL_OU-Ordinateurs_JoindrePC` ;
- étendue **Domaine local** ;
- type **Sécurité**.

<img src="captures/54a-groupe-dl-ou-ordinateurs-joindrepc-creation.png" width="560">

> 📸 **Ce que tu dois voir** : **Nouvel objet - Groupe**, Créer dans **lab.home.arpa/AEROTRANS/Groupes**,  
> nom **DL_OU-Ordinateurs_JoindrePC**, ⦿ **Domaine local**, ⦿ **Sécurité**.

**21.2** Double-clic sur le groupe > onglet **Membres** > **Ajouter** > `GG_Informatique` >
**Vérifier les noms** > **OK**.

<img src="captures/54b-groupe-dl-ajout-gg-informatique.png" width="560">

> 📸 **Ce que tu vois** : la fenêtre de sélection avec **GG_Informatique**.

<img src="captures/54c-groupe-dl-membres-gg-informatique.png" width="560">

> 📸 **Ce que tu dois voir** : membre **GG_Informatique** (`lab.home.arpa/AEROTRANS/Groupes`).

**21.3** Onglet **Général** > description : `Droit de joindre des PC au domaine dans l'OU Ordinateurs
(delegation)` > **OK**.

<img src="captures/54d-groupe-dl-description-ok.png" width="640">

> 📸 **Ce que tu dois voir** : le groupe **DL_OU-Ordinateurs_JoindrePC** avec sa description, au milieu  
> des GG_.

**21.4** Clic droit sur l'OU **Ordinateurs** > **Délégation de contrôle** > **Suivant** > **Ajouter**
`DL_OU-Ordinateurs_JoindrePC` > **Suivant** > ⦿ **Créer une tâche personnalisée à déléguer** >
**Suivant**.

**21.5** ⦿ **Seulement des objets suivants dans le dossier** > ✅ **Objets Ordinateur**, et en bas
✅ **Créer les objets sélectionnés dans ce dossier**, ✅ **Supprimer les objets sélectionnés dans ce
dossier** > **Suivant**.

<img src="captures/55-delegation-objets-ordinateur-creer-supprimer.png" width="560">

> 📸 **Ce que tu dois voir** : **Type d'objet Active Directory**, ✅ **Objets Ordinateur**, ✅ Créer,  
> ✅ Supprimer.

**21.6** Autorisations : coche **Générales** et **Spécifiques aux propriétés** (pour toutes les voir),
puis coche **exactement** :

| Autorisation | Pourquoi |
| --- | --- |
| Écriture validée vers le nom d'hôte DNS | Enregistrer `PC-xxx.lab.home.arpa` ; « validée » = l'AD vérifie la cohérence |
| Écriture validée vers le nom de principal du service | Les étiquettes Kerberos (SPN) du PC, vérifiées elles aussi |
| Réinitialiser le mot de passe | Un compte ordinateur a son propre mot de passe, défini à la jonction |
| Lire et écrire Restrictions de compte | Activer le compte et régler son type |

<img src="captures/56a-delegation-ecritures-validees-dns-spn.png" width="560">

> 📸 **Ce que tu dois voir** : ✅ **Écriture validée vers le nom d'hôte DNS**, ✅ **Écriture validée  
> vers le nom de principal du service**.

<img src="captures/56b-delegation-reinit-mdp-restrictions-compte.png" width="560">

> 📸 **Ce que tu dois voir** (plus bas dans la liste) : ✅ **Réinitialiser le mot de passe**,  
> ✅ **Lire et écrire Restrictions de compte**.

❌ **Pas de « Contrôle total »**, que proposent beaucoup de tutos : il permettrait de modifier les
droits et de prendre la main sur les comptes ordinateur **existants** de l'OU.

**21.7** **Suivant** > relis le résumé > **Terminer**.

<img src="captures/57a-delegation-resume-1.png" width="560">

> 📸 **Ce que tu vois** : **Fin de l'Assistant Délégation de contrôle**, dossier  
> `lab.home.arpa/AEROTRANS/Ordinateurs`, groupe `DL_OU-Ordinateurs_JoindrePC`.

<img src="captures/57b-delegation-resume-2-autorisations.png" width="560">

> 📸 **Ce que tu vois** (en descendant) : les 4 autorisations, pour le type d'objet **Ordinateur**.

**21.8** **Vérifie** : menu **Affichage** > ✅ **Fonctionnalités avancées**. Clic droit sur l'OU
**Ordinateurs** > **Propriétés** > onglet **Sécurité** > **Avancé**.

<img src="captures/57c-ou-ordinateurs-securite-avancee-ace-dl.png" width="640">

> 📸 **Ce que tu dois voir** : **5 entrées DL_OU-Ordinateurs_JoindrePC** (Réinitialiser le mot de  
> passe, Écriture validée DNS, Écriture validée SPN, Restrictions de compte, Créer/supprimer des objets  
> Ordinateur).  
> 💡 On y voit aussi « **Tout le monde – Refuser** » (la **protection contre la suppression  
> accidentelle**) et « **Opérateurs de compte** », un groupe intégré qui peut lui aussi créer des  
> ordinateurs et doit rester **vide**.

Test réel (joindre un PC avec `paulo.rosa`) : à faire avec le portable PO-001.

---

## Partie 6 — LAPS : un mot de passe admin local unique par poste

> 💡 **Le problème** : si le compte administrateur local a le **même mot de passe sur tous les PC**, le  
> pirate qui le récupère sur un poste (avec Mimikatz par exemple) se connecte à **tous** les autres.  
> C'est le **mouvement latéral**, au cœur de la plupart des attaques par rançongiciel.
>
> **Windows LAPS** : chaque PC génère un mot de passe **unique et aléatoire**, le **change tout seul**,  
> et le range **chiffré** dans son objet AD, lisible seulement par les personnes autorisées.

### Étape 22 · Un instantané avant de toucher au schéma

💡 Le **schéma**, c'est la **structure** de tout l'annuaire (quels types d'objets et quels champs
existent). L'étendre est **irréversible**.

**22.1** Proxmox > **200 (SRV-AD01)** > **Instantanés** > **Créer un instantané** :
nom `avant-laps-schema`, ✅ **Inclure la RAM**, description `Avant extension du schéma pour Windows
LAPS` > **Créer un instantané**.

<img src="captures/58-proxmox-snapshot-srv-ad01-avant-laps-schema.png" width="640">

> 📸 **Ce que tu dois voir** : l'instantané **avant-laps-schema** (RAM : Oui) sous `avant_promotion`,  
> et la tâche **TASK OK**.

🏢 On ne restaure pas un instantané de DC quand il y en a plusieurs (*USN rollback*, brique 03). En
entreprise : sauvegarde de l'état système, test dans un lab, fenêtre de maintenance. Avec un seul DC,
l'instantané est sans risque.

---

### Étape 23 · Étendre le schéma, en « juste à temps »

💡 Seul le groupe **Administrateurs du schéma** peut modifier le schéma. Il ne contient que le compte
`Administrateur` intégré, et **ça doit rester ainsi le reste du temps**.

**23.1** Sur SRV-AD01 (connecté en `adm.paulo.rosa`), PowerShell en administrateur :

```powershell
whoami /groups | findstr /i "schéma"
whoami
```

<img src="captures/59a-whoami-findstr-schema-vide.png" width="460">

> 📸 **Ce que tu vois** : `findstr` ne renvoie **rien**.  
> ❌ Mais `findstr` gère mal les **accents** : ce « rien » ne prouve pas grand-chose. On vérifie à  
> l'interface (23.2).

<img src="captures/59b-whoami-adm-paulo-rosa.png" width="460">

> 📸 **Ce que tu vois** : `whoami` → **lab\adm.paulo.rosa**.

**23.2** **Utilisateurs et ordinateurs AD** > **Users** > double-clic sur **Administrateurs du
schéma** > onglet **Membres**.

<img src="captures/59c-administrateurs-du-schema-avant.png" width="560">

> 📸 **Ce que tu dois voir (avant)** : un seul membre, **Administrateur**.

**23.3** **Ajout temporaire** : **Ajouter** > `adm.paulo.rosa` > **OK** > **OK**.

<img src="captures/59d-administrateurs-du-schema-ajout-temporaire-adm.png" width="560">

> 📸 **Ce que tu vois** : **Administrateur** et **Paulo Rosa (admin)**.

**23.4** **Déconnecte-toi puis reconnecte-toi** en `adm.paulo.rosa`.

💡 Les groupes sont chargés dans le **jeton** de sécurité à l'ouverture de session : sans reconnexion,
le nouveau droit n'est pas pris en compte.

**23.5** Vérifie (avec `Select-String`, qui gère bien les accents) :

```powershell
whoami /groups | Select-String "sch"
```

<img src="captures/60a-whoami-groups-administrateurs-du-schema-sid-floute.png" width="640">

> 📸 **Ce que tu dois voir** : **LAB\Administrateurs du schéma … Groupe obligatoire, Activé par  
> défaut, Groupe activé** (le SID est masqué).

**23.6** Étends le schéma (PowerShell **en administrateur**) :

```powershell
Update-LapsADSchema -Verbose
```

💡 Il n'y a pas d'interface graphique pour cette étape. `-Verbose` = affiche le détail de ce qui est
fait.

<img src="captures/60b-update-lapsadschema-ok.png" width="640">

> 📸 **Ce que tu dois voir** : des lignes **COMMENTAIRES** « Successfully added new schema attribute  
> 'CN=ms-LAPS-…' », « Successfully added new extended right 'ms-LAPS-Encrypted-Password-Attributes' »,  
> « The 'computer' classSchema is missing … msLAPS-… » puis « Successfully modified mayContain », et à  
> la fin **ProcessRecord completed** / **EndProcessing completed**.  
> ✅ 7 attributs `msLAPS-*` ajoutés aux objets ordinateur.

**23.7** **Retrait immédiat** : **Administrateurs du schéma** > **Membres** > sélectionne **Paulo Rosa
(admin)** > **Supprimer** > **OK**.

<img src="captures/61-administrateurs-du-schema-adm-retire.png" width="560">

> 📸 **Ce que tu dois voir** : de nouveau **un seul** membre, **Administrateur** ✅.

💡 C'est le **Just-In-Time** : le droit est donné **pour l'opération**, puis retiré.
🏢 En SOC, l'ajout d'un membre dans un groupe sensible (Admins du domaine, Administrateurs du schéma, de
l'entreprise) déclenche une **alerte** (événement **4728** sur le DC).

---

### Étape 24 · Les postes peuvent écrire leur propre mot de passe

**24.1** PowerShell en administrateur :

```powershell
Set-LapsADComputerSelfPermission -Identity "OU=Ordinateurs,OU=AEROTRANS,DC=lab,DC=home,DC=arpa"
```

<img src="captures/62-set-lapsadcomputerselfpermission-ou-ordinateurs.png" width="640">

> 📸 **Ce que tu dois voir** : **Name Ordinateurs**, **DistinguishedName  
> OU=Ordinateurs,OU=AEROTRANS,DC=lab,DC=home,DC=arpa**.  
> ✅ Chaque PC de l'OU (et des sous-OU) peut écrire **son propre** mot de passe dans l'AD, et seulement  
> le sien.

---

### Étape 25 · La GPO C_Securite_LAPS

**25.1** GPMC > clic droit sur l'OU **Ordinateurs** > **Créer un objet GPO dans ce domaine, et le lier
ici** > `C_Securite_LAPS` > clic droit > **Modifier**.

**25.2** Configuration ordinateur > Stratégies > Modèles d'administration > Système > **LAPS**.

**25.3** **Configurer le répertoire de sauvegarde de mot de passe** > **Activé** > Répertoire :
**Active Directory** > **OK**.

<img src="captures/63a-gpo-laps-repertoire-sauvegarde-active-directory.png" width="560">

> 📸 **Ce que tu dois voir** : ⦿ **Activé**, liste **Répertoire de sauvegarde** ouverte avec  
> **Active Directory** (et non Azure Active Directory).  
> 💡 « Azure Active Directory » (= Entra ID) sert aux PC joints au cloud. **Par défaut : désactivé,  
> LAPS ne fait rien.**

<img src="captures/63b-gpo-laps-liste-parametres.png" width="560">

> 📸 **Ce que tu vois** : la liste des 10 paramètres LAPS, encore presque tous « Non configuré ».

**25.4** **Paramètres du mot de passe** > **Activé** :

| Option | Valeur |
| --- | --- |
| Complexité | **Lettres majuscules + lettres minuscules + chiffres + spéciaux** |
| Longueur | **20** |
| Âge du mot de passe (jours) | **30** |

<img src="captures/64-gpo-laps-parametres-mot-de-passe-20-30j.png" width="560">

> 📸 **Ce que tu dois voir** : ⦿ **Activé**, complexité maximale, **20** caractères, **30** jours.  
> 💡 La « longueur de phrase secrète » ne sert qu'avec une complexité de type phrase.

**25.5** **Activer le chiffrement du mot de passe** > **Activé** > **OK**.

💡 Possible à partir du niveau fonctionnel 2016 (ici 2025). Déchiffrement par défaut : Admins du domaine.

<img src="captures/65-gpo-laps-3-parametres-actives.png" width="560">

> 📸 **Ce que tu dois voir** : **Activer le chiffrement du mot de passe : Activé**, **Configurer le  
> répertoire de sauvegarde : Activé**, **Paramètres du mot de passe : Activé**.

💡 Liée à **Ordinateurs** (pas seulement Postes-fixes) : les **portables** en ont encore plus besoin
(ils sortent, se perdent, se volent).

---

### Étape 26 · Quel compte confier à LAPS ? (erreur corrigée)

💡 LAPS sert surtout quand le PC a **perdu la relation d'approbation** avec le domaine (portable resté
des mois au placard, restauration ancienne) : plus aucun compte du domaine ne marche, seul un **compte
local** permet d'entrer. Or le compte `Administrateur` intégré est **désactivé** par Windows : s'il le
reste, LAPS range un mot de passe **inutilisable**.

| Méthode | Principe | Quand |
| --- | --- | --- |
| Classique | Réactiver l'`Administrateur` intégré par GPO (« Comptes : statut du compte Administrateur ») et le confier à LAPS | Parc mélangé (Windows 10, anciens serveurs) : la plus répandue aujourd'hui |
| **Gestion automatique** (retenue) | LAPS **crée et gère** son propre compte (`secours.local`) ; l'`Administrateur` intégré reste désactivé | Tous les postes en Windows 11 **24H2 ou plus** |

**26.1** ❌ **Erreur du lab** : j'avais d'abord configuré la méthode classique « par prudence », **sans
vérifier** la version de Windows.

<img src="captures/66-gpo-laps-etat-compte-administrateur-active.png" width="640">

> 📸 **Ce que j'avais fait** : dans la GPO, Paramètres de sécurité > Options de sécurité > **Comptes :  
> statut du compte Administrateur** > ✅ Définir > ⦿ **Activé**.

**26.2** Vérifie la version sur PC-001 : **Windows + R** > `winver`.

<img src="captures/67-winver-pc-001-25h2.png" width="560">

> 📸 **Ce que tu dois voir** : **Windows 11 … Version 25H2 (build 26200.9711)** ✅ → 24H2 ou plus :  
> gestion automatique possible.

**26.3** Remets le réglage classique à **Non défini** (décoche **Définir ce paramètre de stratégie**).

<img src="captures/68-gpo-laps-statut-administrateur-non-defini.png" width="640">

> 📸 **Ce que tu dois voir** : **Comptes : statut du compte Administrateur → Non défini**.  
> 👉 **On vérifie la version avant de choisir.**

**26.4** Dans **LAPS** > **Configurer la gestion automatique des comptes** > **Activé** :

| Option | Valeur |
| --- | --- |
| Spécifiez le compte cible à gérer | **Gérer un compte d'administrateur personnalisé** |
| Nom du compte automatique | `secours.local` |
| Activer le compte géré | ✅ |
| Choisir au hasard le nom du compte géré | ❌ |

<img src="captures/69-gpo-laps-gestion-auto-compte-secours-local.png" width="640">

> 📸 **Ce que tu dois voir** : ⦿ **Activé**, **Gérer un compte d'administrateur personnalisé**,  
> nom **secours.local**, ✅ **Activer le compte géré**, ❌ nom au hasard.

💡 **Le nom `secours.local`** : pas de « admin », rien qui ressemble aux comptes du domaine
`adm.prenom.nom`. Sans nom, Windows utilise `WLapsAdmin`, connu de tous. L'option « nom aléatoire »
(qui change à chaque rotation) est plus sûre mais plus lourde au quotidien : non activée pour l'instant.

---

### Étape 27 · Tester LAPS

**27.1** Sur PC-001 : `gpupdate /force`, attends une minute.

**27.2** Sur PC-001, **Gestion de l'ordinateur** (en administrateur, comme en 20.2) > **Utilisateurs**.

<img src="captures/70-pc-001-compte-secours-local-cree.png" width="560">

> 📸 **Ce que tu dois voir** : un nouveau compte **secours.local**, actif, description « Ce compte est  
> actuellement géré… » ; Administrateur et tech.install toujours désactivés ✅.

**27.3** Sur SRV-AD01 : **Utilisateurs et ordinateurs AD** > **Postes-fixes** > double-clic sur
**PC-001** > onglet **LAPS**.

<img src="captures/71-aduc-pc-001-onglet-laps-masque.png" width="560">

> 📸 **Ce que tu dois voir** : **Expiration actuelle : vendredi 20 novembre 2026 18:35** (30 jours),  
> **Nom du compte : secours.local**, mot de passe **masqué** (points), boutons **Copier le mot de  
> passe**, **Afficher le mot de passe**, **Expirer maintenant**.  
> ⚠️ On ne clique **pas** sur « Afficher le mot de passe » pour une capture.

**27.4** En PowerShell, **en administrateur** (obligatoire sur un DC) :

```powershell
Get-LapsADPassword -Identity PC-001
```

<img src="captures/72a-get-lapsadpassword-erreurs-aad-et-non-eleve.png" width="640">

> 📸 **❌ Mes 2 erreurs** :  
> 1. `Get-LapsAADPassword` (avec **AAD**) : c'est la commande pour **Entra ID**, elle ne connaît pas  
>    `-Identity` ;  
> 2. `Get-LapsADPassword` dans un PowerShell **non élevé** : **This cmdlet requires elevation when  
>    invoked on a domain controller**.

<img src="captures/72b-get-lapsadpassword-chiffre-success.png" width="640">

> 📸 **Ce que tu dois voir** (PowerShell en administrateur) :
>
> | Champ | Valeur | Sens |
> | --- | --- | --- |
> | Account | secours.local | Le compte géré |
> | Password | `System.Security.SecureString` | Jamais affiché en clair sans `-AsPlainText` |
> | ExpirationTimestamp | 20/11/2026 | Prochain changement |
> | Source | **EncryptedPassword** | Stocké **chiffré** ✅ |
> | DecryptionStatus | Success | On a le droit de le déchiffrer |
> | AuthorizedDecryptor | LAB\Admins du domaine | Qui peut le lire |

---

## Annexes

### A. Récapitulatif sécurité

| Mesure | Contre quoi |
| --- | --- |
| Verrouillage à 10 min | Poste laissé ouvert à la pause |
| RPC/WMI ouvert **seulement** depuis SRV-AD01, sur pfSense **et** sur le poste, profil Domaine | Un poste ou un serveur compromis qui sonde les autres |
| MachineAccountQuota = 0 + délégation au moindre privilège | Faux comptes ordinateur, PC non gérés |
| Comptes locaux désactivés (tech.install, Administrateur) | Comptes oubliés aux mots de passe éternels |
| LAPS chiffré, compte de secours au nom non standard | Mouvement latéral avec un mot de passe local partagé |
| Administrateurs du schéma vide (Just-In-Time) | Modification de la structure de l'annuaire |

### B. Équivalents PowerShell

Les commandes **testées** dans le lab sont marquées ✅. Les autres sont l'équivalent des clics, données
pour référence : à valider dans un lab avant usage.

```powershell
# --- Poste : licence, nom, DNS, jonction ---
slmgr /dlv ; slmgr /ato ; slmgr /xpr                                   # ✅
Rename-Computer -NewName PC-001 -Restart
Resolve-DnsName -Type SRV _ldap._tcp.dc._msdcs.lab.home.arpa           # ✅
Add-Computer -DomainName lab.home.arpa -Credential LAB\adm.paulo.rosa -Restart

# --- Serveur : ranger le PC dans la bonne OU ---
$base = "OU=AEROTRANS,DC=lab,DC=home,DC=arpa"
Move-ADObject -Identity "CN=PC-001,OU=Ordinateurs,$base" -TargetPath "OU=Postes-fixes,OU=Ordinateurs,$base"

# --- Preuve de la GPO de verrouillage ---
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name InactivityTimeoutSecs   # ✅

# --- Tests réseau ---
Test-NetConnection PC-001 -Port 135                                    # ✅

# --- GPO pare-feu Windows : règles WMI prédéfinies, restreintes à SRV-AD01 et au profil Domaine ---
New-GPO -Name C_Securite_PareFeu_Administration | New-GPLink -Target "OU=Ordinateurs,$base"
$store = "lab.home.arpa\C_Securite_PareFeu_Administration"
Copy-NetFirewallRule -DisplayGroup "Infrastructure de gestion Windows (WMI)" -Direction Inbound -NewPolicyStore $store
Set-NetFirewallRule -PolicyStore $store -DisplayGroup "Infrastructure de gestion Windows (WMI)" `
  -RemoteAddress 10.10.10.10 -Profile Domain -Enabled True

# --- Poste : appliquer et vérifier ---
gpupdate /force                                                        # ✅
powercfg /a                                                            # ✅
powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE                       # ✅

# --- GPO alimentation (valeurs de registre des paramètres d'alimentation, GUID publics de Microsoft) ---
New-GPO -Name C_Config_Alimentation | New-GPLink -Target "OU=Postes-fixes,OU=Ordinateurs,$base"
# Écran (sur secteur) : 900 s
Set-GPRegistryValue -Name C_Config_Alimentation -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\3C0BC021-C8A8-4E07-A973-6B14CBCB2B7E" -ValueName ACSettingIndex -Type DWord -Value 900
# Veille (sur secteur) : 0 = jamais
Set-GPRegistryValue -Name C_Config_Alimentation -Key "HKLM\Software\Policies\Microsoft\Power\PowerSettings\29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA" -ValueName ACSettingIndex -Type DWord -Value 0

# --- Durcissement AD ---
Get-ADObject (Get-ADDomain).DistinguishedName -Properties ms-DS-MachineAccountQuota   # ✅
Set-ADDomain -Identity lab.home.arpa -Replace @{"ms-DS-MachineAccountQuota"="0"}

# --- Poste : compte local d'installation ---
Disable-LocalUser -Name tech.install

# --- Délégation de la jonction : le groupe (les autorisations fines : assistant graphique,
#     un script dsacls / Set-Acl sera écrit dans la brique 09) ---
New-ADGroup -Name DL_OU-Ordinateurs_JoindrePC -GroupScope DomainLocal -GroupCategory Security `
  -Path "OU=Groupes,$base" -Description "Droit de joindre des PC au domaine dans l'OU Ordinateurs (delegation)"
Add-ADGroupMember DL_OU-Ordinateurs_JoindrePC -Members GG_Informatique

# --- LAPS ---
whoami /groups | Select-String "sch"                                   # ✅
Update-LapsADSchema -Verbose                                           # ✅ (membre temporaire des Administrateurs du schéma)
Set-LapsADComputerSelfPermission -Identity "OU=Ordinateurs,$base"      # ✅
Get-LapsADPassword -Identity PC-001                                    # ✅ (PowerShell élevé)
Set-LapsADPasswordExpirationTime -Identity PC-001                      # forcer un changement au prochain cycle
Invoke-LapsPolicyProcessing                                            # sur le poste : appliquer LAPS tout de suite
```

### C. Dépannages rencontrés

| Symptôme | Cause | Solution |
| --- | --- | --- |
| Aucun disque à l'installation | Pilote VirtIO SCSI absent | `vioscsi\w11\amd64` |
| Pas de réseau pendant l'OOBE | Pilote NetKVM absent | Compte local temporaire, puis virtio-win-guest-tools |
| « La licence Windows a expiré » | Évaluation installée hors ligne, jamais activée (`0xC004F009`) | `slmgr /ato` une fois le réseau en place |
| Session verrouillée avant 10 min | Extinction de l'écran à 5 min (défaut de Windows 11) | Neutraliser pour tester, puis GPO d'alimentation |
| RSOP : « serveur RPC indisponible » (1) | pfSense, refus par défaut SERVEURS → POSTES | Alias + règle depuis SRV-AD01 seulement |
| `Test-NetConnection` False juste après la règle | Règles pfSense encore en rechargement | Relancer le test |
| RSOP : « serveur RPC indisponible » (2) | Pare-feu Windows du poste, WMI fermé | GPO, règles WMI prédéfinies limitées à 10.10.10.10 / Domaine |
| « Windows Management Instrumentation » introuvable | Nom français : « Infrastructure de gestion Windows (WMI) » | Chercher à la lettre I |
| Rapport RSOP bloqué par Internet Explorer | Sécurité renforcée d'IE sur le serveur | Fermer, sans ajouter aux sites de confiance |
| `gpresult /scope computer` : Accès refusé | Utilisatrice non administratrice | Normal ; vérifier depuis le serveur (RSOP) |
| Option « veille » absente des Paramètres | La VM ne gère aucun état de veille | `powercfg /a`, `powercfg /q` |
| tech.install : Accès refusé | Console ouverte sans élévation | Exécuter en tant qu'administrateur |
| `findstr "schéma"` ne trouve rien | `findstr` gère mal les accents | `Select-String`, ou vérification graphique |
| `Get-LapsAADPassword` : paramètre Identity inconnu | Commande pour Entra ID | `Get-LapsADPassword` (sans le 2e A) |
| `Get-LapsADPassword` : *requires elevation* | PowerShell non élevé sur un DC | Exécuter en tant qu'administrateur |

### D. Écarts entre le lab et l'entreprise

| Dans le lab | En entreprise | Pourquoi l'écart |
| --- | --- | --- |
| Activation `slmgr` à la main | Activation par l'AD ou KMS, licences en volume | Évaluation du lab |
| PC installé à la main | Déploiement automatisé (image, MDT, Autopilot) | Brique 14 |
| Instantané avant l'extension du schéma | Sauvegarde de l'état système + test en lab + fenêtre de maintenance | Un seul DC |
| Un seul poste | Des dizaines : d'où les GPO plutôt que les réglages locaux | Lab |
| Option « veille » invisible | Visible et grisée sur un vrai PC fixe | Matériel virtuel |
| Mots de passe LAPS lisibles par les Admins du domaine | Groupe dédié de lecteurs LAPS (support N2), lecture auditée | À faire |
| Délégation non encore testée par une vraie jonction | Testée en recette avant la mise en service | Pas de 2e poste (PO-001 prévu) |
| Administration depuis la console Proxmox | Bureau à distance depuis le VLAN d'administration (ADM-001) | Prévu (RDP vers PC-001) |

### E. Utilisation en entreprise : 3 cas concrets

1. **Un portable revient après 6 mois au placard** : « la relation d'approbation a échoué ». Le
   technicien lit le mot de passe LAPS de ce PC dans l'AD, se connecte avec `secours.local`, rejoint de
   nouveau le domaine. Le mot de passe sera changé automatiquement ensuite.
2. **Un poste est infecté** : le pirate récupère le mot de passe local… qui ne marche sur **aucun autre
   PC**. Il ne peut pas non plus interroger les autres postes par WMI : seul SRV-AD01 y a droit.
3. **Un salarié dit que son PC ne se verrouille pas** : depuis le serveur, RSOP sur son poste montre en
   une minute quelle GPO s'applique, et laquelle gagne.

### F. Questions d'entretien (avec la réponse)

- **Pourquoi renommer un PC avant de le joindre au domaine ?** Le compte ordinateur est créé avec le nom
  du moment ; renommer après crée des incohérences (DNS, SPN).
- **Une GPO ne s'applique pas sur un poste, que vérifies-tu ?** Le poste est-il dans la bonne OU, la GPO
  liée au bon endroit, partie ordinateur ou utilisateur, filtrage de sécurité ; puis `gpupdate /force`,
  `gpresult /r` ou RSOP depuis le serveur.
- **RSOP à distance échoue avec « serveur RPC indisponible » : ta démarche ?** Tester le port 135
  (`Test-NetConnection`), lire les journaux du pare-feu réseau, puis le pare-feu Windows du poste
  (ports dynamiques de WMI). Un pare-feu à la fois, un test entre chaque étape.
- **Pourquoi deux pare-feu ?** Défense en profondeur : si l'un est mal réglé ou contourné, l'autre protège.
- **Qu'est-ce que ms-DS-MachineAccountQuota ?** Le nombre de PC qu'un utilisateur standard peut joindre
  (10 par défaut). On le met à 0 et on délègue.
- **Pourquoi pas « Contrôle total » dans une délégation ?** Il donne aussi le droit de modifier les
  permissions et de prendre le contrôle des objets existants.
- **Qu'est-ce que LAPS, et contre quelle attaque ?** Un mot de passe admin local unique par poste, changé
  automatiquement : il bloque le mouvement latéral (*pass-the-hash* avec un mot de passe partagé).
- **Différence entre l'ancien LAPS et Windows LAPS ?** L'ancien était un logiciel à installer, mot de
  passe en clair dans l'AD ; Windows LAPS est intégré, chiffre le mot de passe, sait gérer Entra ID et
  créer son propre compte.
- **Qui peut modifier le schéma, et comment l'as-tu fait ?** Les Administrateurs du schéma ; ajout
  temporaire, reconnexion (jeton), opération, retrait immédiat (Just-In-Time).
- **Pourquoi un compte admin local s'il y a le domaine ?** Pour entrer quand le poste a perdu le contact
  avec le domaine.

### G. Points en suspens

- Tester la délégation : joindre le portable **PO-001** avec `paulo.rosa` (non admin).
- Vérifier que le groupe **Opérateurs de compte** est vide.
- Groupe dédié aux **lecteurs LAPS** et audit des lectures (brique Wazuh).
- Règles précises du VLAN Postes vers SRV-AD01 (remplacer la règle provisoire « Postes → tout »).
- Option « nom aléatoire » de LAPS à évaluer.
- Script de délégation (dsacls / Set-Acl) dans la brique 09.

### H. Captures manquantes

| Étape | Écran à photographier |
| --- | --- |
| 3.1 | Chargement du pilote `vioscsi\w11\amd64` et choix du disque |
| 3.5 | Installation de virtio-win-guest-tools |
| 21.4 | Premiers écrans de l'assistant Délégation de contrôle (choix du groupe, tâche personnalisée) |

### I. Lexique

| Mot | Sens |
| --- | --- |
| **ADSI Edit** | Éditeur brut de l'annuaire, sans garde-fou |
| **Délégation** | Donner un droit précis sur une OU à un groupe, sans le rendre admin |
| **Jeton (token)** | La liste des groupes d'un utilisateur, chargée à l'ouverture de session |
| **Just-In-Time** | Donner un droit sensible juste le temps d'une opération |
| **LAPS** | *Local Administrator Password Solution* : mot de passe admin local unique et tournant |
| **MachineAccountQuota** | Nombre de PC qu'un utilisateur standard peut joindre au domaine |
| **OOBE** | Les écrans de première configuration de Windows |
| **Profil Domaine** | Profil du pare-feu Windows actif quand le PC voit le domaine |
| **RPC** | Mécanisme d'appel à distance (port 135 puis port dynamique) |
| **RSOP** | Rapport des GPO réellement appliquées sur un PC |
| **Schéma** | La structure de l'annuaire : types d'objets et attributs |
| **WMI** | Interface d'administration à distance de Windows |
