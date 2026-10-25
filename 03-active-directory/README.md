# Brique 03 — Active Directory, DNS et DHCP sous Windows Server 2025

> **Tuto pas à pas, écrit pour quelqu'un qui débute.** Chaque étape dit **pourquoi** on la fait,
> **où cliquer** ou **quoi taper**, **ce qu'on doit voir**, et **quoi faire si ça ne marche pas**.
> Les étapes sont faites à l'interface graphique ; les commandes PowerShell équivalentes sont en
> annexe B. Les erreurs faites pendant le lab sont laissées volontairement, avec leur correction.
> Les captures sont dans le dossier [`captures/`](captures/).

## Comment lire ce tuto

| Repère | Sens |
| --- | --- |
| 🎯 | **Le but** de l'étape |
| 🖱️ | Ce qu'on fait **à la souris** (menus, boutons, cases) |
| ⌨️ | Ce qu'on **tape**, avec l'explication |
| ✅ | Ce qu'on **doit voir** si tout va bien |
| ❌ | **Si ça ne marche pas** (souvent : l'erreur qu'on a vraiment eue) |
| 🏢 | **En entreprise**, quand on ferait autrement |
| 💡 | Une explication pour bien comprendre |

---

## Résumé pour les pressés

- **SRV-AD01** (Windows Server 2025, 10.10.10.10, VLAN 10) : contrôleur de domaine de la forêt
  **`lab.home.arpa`** (NetBIOS `LAB`), DNS intégré (5 zones inversées, mises à jour sécurisées,
  redirecteur vers pfSense), **DHCP** du VLAN Postes via le **relais** de pfSense.
- **Organisation** : OU `AEROTRANS` protégées, corbeille AD, `redircmp` / `redirusr`, 7 groupes
  `GG_Service`, **24 salariés importés par script** depuis un CSV (simulation d'abord).
- **Sécurité** : compte admin nominatif `adm.paulo.rosa` (Protected Users, non délégable),
  `Administrateur` gardé en secours, politique de mot de passe (12 caractères) + **PSO-Admins**
  (15 caractères), heure synchronisée sur pfSense (Kerberos), **pare-feu du VLAN Serveurs au moindre
  privilège**, première GPO (verrouillage après 10 min).
- **Santé** : `dcdiag` 28 tests réussis.

---

## Partie 0 — Comprendre avant de commencer

### 0.1 Le besoin du client

AEROTRANS (25 salariés) veut :

- **un compte par personne**, géré à **un seul endroit**, avec des règles de mot de passe ;
- des **droits par service** (la compta ne voit pas les dossiers RH) ;
- des **postes qui appliquent tout seuls** les règles de sécurité ;
- des **adresses IP distribuées automatiquement** aux postes ;
- de la **traçabilité** : savoir qui a fait quoi.

C'est le rôle d'un **annuaire Active Directory** (AD), avec son **DNS** et son **DHCP**.

### 0.2 Les mots à connaître, avec des images

| Mot | Ce que c'est | Image |
| --- | --- | --- |
| **Active Directory (AD)** | L'annuaire de l'entreprise : comptes, groupes, ordinateurs, règles | Le **registre du personnel** + le **règlement intérieur** |
| **Domaine** (`lab.home.arpa`) | L'ensemble géré par l'AD | L'**entreprise** elle-même |
| **Contrôleur de domaine (DC)** | Le serveur qui héberge l'AD et vérifie les mots de passe | L'**accueil** qui vérifie les badges |
| **OU** (unité d'organisation) | Un dossier pour **ranger** les objets et leur appliquer des règles | Les **services** sur l'organigramme |
| **Groupe** | Un ensemble de comptes, pour **donner des droits** | Une **liste de diffusion** : on donne l'accès à la liste, pas à chaque personne |
| **GPO** (stratégie de groupe) | Un paquet de réglages appliqué automatiquement aux PC ou aux utilisateurs d'une OU | Une **note de service** affichée dans un service |
| **DNS** | Traduit les **noms** en **adresses IP** | L'**annuaire téléphonique** |
| **DHCP** | Distribue automatiquement les adresses IP aux PC | Le **guichet** qui attribue les places de parking |
| **Kerberos** | Le système de « tickets » de connexion de l'AD | Un **bracelet** donné à l'entrée, valable quelques heures |

### 0.3 Le choix de l'outil

| Critère | Windows Server 2025 (AD DS) | Samba AD (Linux) | Entra ID seul (cloud) |
| --- | --- | --- | --- |
| Présence en PME et ESN | Standard du marché | Rare | En hausse, souvent en complément |
| GPO complètes | Oui | Partielles | Non (Intune à la place) |
| Postes sans Internet | Oui | Oui | Non |
| Coût | Licence (évaluation 180 j ici) | Gratuit | Abonnement |

**Choix : Windows Server 2025 Standard**, **avec l'interface graphique** pour apprendre.
🏢 En production, l'installation **Core** (sans interface) réduit la surface d'attaque et les mises à jour.

### 0.4 L'architecture

```
                     pfSense (fw01)
     relais DHCP · NTP · résolveur DNS · refus par défaut
        |                                   |
   VLAN 10 Serveurs                    VLAN 20 Postes
   10.10.10.0/24                       10.10.20.0/24
        |                                   |
   SRV-AD01  10.10.10.10               PC (DHCP .100 → .199)
   AD DS · DNS · DHCP                  test-poste (VM 900)
   domaine lab.home.arpa
```

![Schéma d'architecture](../docs/lab-pme-architecture.png)

Adresses : [plan d'adressage](../docs/plan-adressage.md) · Flux : [matrice des flux](../docs/matrice-des-flux.md) ·
Noms : [conventions](../docs/conventions.md).

---

## Partie 1 — La machine virtuelle

### Étape 1 · Les ISO

🖱️ Proxmox > **local (pve01)** > **Images ISO** :

1. **Téléverser** l'ISO **Windows Server 2025 Evaluation (français)**, avec l'empreinte **SHA-256**
   (Proxmox vérifie le fichier à l'arrivée). ✅ `checksum verified`, `TASK OK`.
2. **Télécharger depuis une URL** l'ISO **virtio-win** : les **pilotes** Red Hat pour les disques et
   cartes réseau virtuels de Proxmox (Windows ne les connaît pas d'origine).

![ISO vérifiée](captures/01-upload-iso-winserver-sha256-ok.png)
![virtio-win](captures/02-telechargement-virtio-win.png)

### Étape 2 · Créer la VM 200 · SRV-AD01

🖱️ **Créer une VM** (case **Avancé** cochée) :

| Onglet | Réglage | Valeur | Pourquoi |
| --- | --- | --- | --- |
| Général | ID / Nom | `200` / `SRV-AD01` | 2xx = serveurs ; convention `SRV-ROLENN` |
| | Démarrage auto / ordre | ✅ / `2` | Après le pare-feu (ordre 1) |
| Système d'exploitation | ISO / type | Windows Server 2025 / **Microsoft Windows 11/2022/2025** | Proxmox adapte les réglages |
| | ✅ Ajouter un lecteur pour les pilotes VirtIO | ISO virtio-win | Un 2e lecteur CD avec les pilotes |
| Système | Machine / BIOS | **q35** / **OVMF (UEFI)** + disque EFI ; ✅ **TPM 2.0** | Exigences de Windows Server 2025, démarrage sécurisé |
| | Contrôleur SCSI / agent QEMU | VirtIO SCSI single / ✅ | |
| Disques | Taille / options | `60` Gio, ✅ discard, ✅ IO thread, ✅ **SSD** | « SSD » : Windows optimise pour un SSD (TRIM) |
| Processeur | Cœurs / type | `2`, **host** | |
| Mémoire | Taille / ballooning | `4096`, ❌ | Un DC ne doit pas voir sa mémoire changer en cours de route |
| Réseau | Pont / tag / modèle | `vmbr1`, **`10`**, VirtIO | Directement dans le VLAN Serveurs |

![Général](captures/03-creation-vm-general.png)
![Système d'exploitation](captures/04-creation-vm-systeme-exploitation.png)
![UEFI et TPM](captures/05-creation-vm-systeme-uefi-tpm.png)
![Disque](captures/06-creation-vm-disque.png)
![Processeur](captures/07-creation-vm-processeur.png)
![Mémoire](captures/08-creation-vm-memoire.png)
![Réseau VLAN 10](captures/09-creation-vm-reseau-vlan10.png)
![Confirmation](captures/10-creation-vm-confirmation-1.png)

❌ **Erreurs corrigées en relisant le récapitulatif** : case **SSD** oubliée et **démarrage automatique**
oublié. 👉 **Toujours relire le récapitulatif avant Terminer.** (La case SSD a été corrigée après coup :
Matériel > disque > Éditer.)

![SSD corrigé](captures/17-materiel-vm200-ssd-corrige.png)

---

## Partie 2 — Installer Windows Server

### Étape 3 · L'installation

🖱️ Démarre la VM > **Console** (appuie sur une touche si « Press any key to boot from CD » s'affiche) :

1. Langue **Français**, clavier **Français** > **Suivant** > **Installer Windows Server**.
2. Édition : **Windows Server 2025 Standard Evaluation (expérience de bureau)**.
   💡 « Expérience de bureau » = avec l'interface graphique.

![Langue](captures/12-install-langue.png)
![Édition](captures/13-install-choix-edition.png)

3. ❌ **Aucun disque visible** : normal, Windows ne connaît pas le contrôleur **VirtIO**.
   🖱️ **Charger un pilote** > **Parcourir** > lecteur **virtio-win** > `vioscsi\2k25\amd64` > **OK** >
   **Suivant**. ✅ Le disque de 60 Go apparaît.

![Pilote vioscsi](captures/14-install-pilote-vioscsi.png)
![Disque visible](captures/15-install-disque-60go.png)
![Récapitulatif](captures/16-install-recapitulatif.png)

4. Mot de passe du compte **`Administrateur`** : long (14 caractères), tapé à la main, rangé au coffre.

![Mot de passe (masqué)](captures/18-mot-de-passe-administrateur.png)

5. Connexion (**Ctrl + Alt + Suppr** : dans la console Proxmox, bouton **A** en haut à gauche ou menu
   des touches). Le **Gestionnaire de serveur** s'ouvre.

![Connexion](captures/19-ecran-connexion.png)
![Gestionnaire de serveur](captures/20-gestionnaire-de-serveur.png)

6. Lecteur virtio-win > double-clic sur **virtio-win-guest-tools** > installer : tous les pilotes
   (réseau…) + l'**agent QEMU**.

---

## Partie 3 — Le réseau du serveur

### Étape 4 · Donner une IP fixe

❌ **Constat** : `ipconfig` montre une adresse **169.254.x.x** (« APIPA »). 💡 Windows se donne cette
adresse **tout seul** quand il ne trouve aucun serveur DHCP : il ne peut parler à personne. Normal : il
n'y a pas de DHCP dans le VLAN 10, et **un serveur a de toute façon une IP fixe**.

![APIPA](captures/21-ipconfig-apipa-169-254.png)

🖱️ **Gestionnaire de serveur** > **Serveur local** > clic sur **Ethernet** > clic droit sur la carte >
**Propriétés** > **Protocole Internet version 4 (TCP/IPv4)** > **Propriétés** :

| Champ | Valeur | Pourquoi |
| --- | --- | --- |
| Adresse IP | `10.10.10.10` | Plan d'adressage |
| Masque | `255.255.255.0` | /24 |
| Passerelle | `10.10.10.254` | pfSense |
| DNS préféré | `10.10.10.10` | **Lui-même** : il sera le DNS du domaine (voir étape 6 pour le piège) |

🖱️ **Nom de l'ordinateur** (Serveur local > Nom de l'ordinateur > **Modifier**) : `SRV-AD01` >
redémarrage. 💡 **Renommer avant la promotion** en DC : après, c'est beaucoup plus compliqué.

✅ `ipconfig /all` : `10.10.10.10`, passerelle `10.10.10.254`.

![IP fixe](captures/22-ipconfig-all-ip-fixe-srv-ad01.png)

### Étape 5 · Les premières règles pfSense du VLAN Serveurs

❌ `ping 10.10.10.254` : **100 % de perte**. 💡 Sans règle sur l'interface SERVEURS, pfSense **bloque
tout** (refus par défaut, brique 01).

![Ping bloqué](captures/23-ping-bloque-avant-regles.png)

🖱️ pfSense > **Firewall > Rules** > **SERVEURS** : trois règles **provisoires** (resserrées en partie 9) :

| # | Action | Destination | Pourquoi |
| --- | --- | --- | --- |
| 1 | Block | LAN subnets (administration) | Un serveur compromis ne touche jamais aux équipements |
| 2 | Block | This Firewall, TCP 443 | Pas d'accès à l'interface web du pare-feu |
| 3 | Pass | any | Provisoire : mises à jour |

![Règle 1](captures/24-regle1-block-serveurs-vers-admin.png)
![Règle 2](captures/25-regle2-block-serveurs-vers-webgui.png)
![Règle 3](captures/26-regle3-pass-serveurs-internet.png)
![Appliquées](captures/27-regles-serveurs-appliquees.png)

✅ Le ping passe, et les blocages fonctionnent.

![Ping OK](captures/28-ping-ok-apres-regles.png)
![Blocages OK](captures/29-blocages-admin-et-webgui-ok.png)
![Descriptions](captures/32-regles-serveurs-avec-descriptions.png)

### Étape 6 · Dépannage : « pas d'Internet » alors que le ping marche

❌ `ping 1.1.1.1` répond, mais Windows Update dit « pas d'Internet » et `Resolve-DnsName google.com` échoue.

💡 **Cause** : le DNS préféré est le serveur **lui-même**… mais le rôle DNS **n'est pas encore installé**.
Personne ne répond sur le port 53 (le port du DNS). Le ping par **IP** marche, les **noms** non.

![Diagnostic](captures/30-diagnostic-dns-avant-promotion.png)

✅ **Contournement** le temps des mises à jour : DNS temporaire **`10.10.10.254`** (pfSense), puis retour à
`10.10.10.10` **juste avant** la promotion (étape 8).

![DNS temporaire](captures/31-dns-temporaire-pfsense.png)

### Étape 7 · Mises à jour et instantané

🖱️ **Paramètres** > **Windows Update** > **Rechercher des mises à jour** > installer > redémarrer, jusqu'à
« Vous êtes à jour ». Puis **DNS remis sur 10.10.10.10**.

![À jour](captures/33-windows-update-a-jour.png)
![DNS remis](captures/34-dns-remis-sur-10-10-10-10.png)

🖱️ VM **éteinte**, instantané Proxmox `avant_promotion` (état cohérent, sans RAM).

![Instantané](captures/35-snapshot-avant-promotion.png)

⚠️ 🏢 En production, on ne restaure **jamais** un instantané de contrôleur de domaine : l'annuaire
« reviendrait dans le passé » et se désynchroniserait des autres DC (*USN rollback*). On utilise une vraie
**sauvegarde de l'état système** (brique 07).

---

## Partie 4 — Créer le domaine

### Étape 8 · Installer le rôle AD DS

🖱️ **Gestionnaire de serveur** > **Gérer** > **Ajouter des rôles et fonctionnalités** > Suivant ×3 >
✅ **Services AD DS** > **Ajouter des fonctionnalités** (les outils : console GPMC, Centre
d'administration AD, module PowerShell) > Suivant… > **Installer**.

💡 On ne coche **ni DNS ni DHCP** ici : le DNS est installé par la promotion, le DHCP vient plus tard.

![Fonctionnalités requises](captures/36-ajout-role-adds-fonctionnalites-requises.png)
![AD DS coché](captures/37-role-adds-coche.png)
![Confirmation](captures/38-confirmation-installation-adds.png)
![Installé](captures/39-installation-adds-reussie.png)

### Étape 9 · Promouvoir le serveur en contrôleur de domaine

🖱️ Drapeau jaune ⚠️ en haut du Gestionnaire de serveur > **Promouvoir ce serveur en contrôleur de domaine** :

![Configuration requise](captures/40-gestionnaire-adds-configuration-requise.png)
![Promouvoir](captures/41-promouvoir-ce-serveur.png)

| Écran | Choix | Pourquoi |
| --- | --- | --- |
| Configuration du déploiement | **Ajouter une nouvelle forêt**, domaine racine `lab.home.arpa` | Le tout premier domaine |
| Options du DC | Niveaux fonctionnels **Windows Server 2025** ; ✅ DNS ; ✅ Catalogue global ; mot de passe **DSRM** | Pas d'ancien DC à gérer. Le DSRM est le mot de passe du **mode de restauration** de l'annuaire : **différent** de celui de l'Administrateur, rangé au coffre |
| Options DNS | Avertissement sur la délégation : **normal** | Il n'existe pas de zone parente `home.arpa` à qui déléguer |
| NetBIOS | `LAB` | Ancien format `LAB\compte` |
| Chemins | Par défaut | |
| Examiner les options | Relire, puis **Suivant** | |
| Vérification de la configuration requise | **Installer** | Le serveur redémarre tout seul |

![Nouvelle forêt](captures/42-promotion-nouvelle-foret-lab-home-arpa.png)
![Options](captures/43-promotion-options-dc-dns-gc-dsrm.png)
![NetBIOS](captures/44-promotion-netbios-lab.png)
![Examiner](captures/45-promotion-examiner-options.png)
![Réussie](captures/46-promotion-reussie.png)

✅ Au redémarrage, on se connecte en **`LAB\Administrateur`** : le serveur est contrôleur du domaine.

![Connexion LAB](captures/47-connexion-lab-administrateur.png)

### Étape 10 · Vérifier le domaine

⌨️ PowerShell :

```powershell
Get-ADDomain
Resolve-DnsName _ldap._tcp.dc._msdcs.lab.home.arpa -Type SRV
```
- `Get-ADDomain` : les informations du domaine. ✅ `lab`, `lab.home.arpa`, `LAB`, `Windows2025Domain`.
- `Resolve-DnsName … -Type SRV` : cherche l'enregistrement **SRV** qui permet aux PC de **trouver un DC**
  (« où est le service LDAP du domaine ? »). ✅ `srv-ad01.lab.home.arpa`, port 389.

❌ **Erreur du lab** : `_mcdcs` au lieu de `_msdcs` → introuvable. Une lettre suffit.

![Faute de frappe](captures/48-verif-domaine-et-faute-de-frappe-msdcs.png)
![SRV trouvé](captures/49-verif-srv-ldap-dc-trouvable.png)

### Étape 11 · Le redirecteur DNS (pour Internet)

💡 Le DC connaît `lab.home.arpa`, mais pas `google.com`. On lui dit : « ce que tu ne connais pas,
demande-le à pfSense ».

🖱️ **Outils** > **DNS** > clic droit sur **SRV-AD01** > **Propriétés** > onglet **Redirecteurs** >
**Modifier** > `10.10.10.254` > **OK**.

✅ `Resolve-DnsName google.com` répond.

![Redirecteur](captures/50-redirecteur-dns-pfsense.png)
![Internet OK](captures/51-resolution-internet-ok.png)

---

## Partie 5 — Le DNS en détail

### Étape 12 · Les zones inversées (IP → nom)

💡 Une zone **directe** traduit `srv-ad01` → `10.10.10.10`. Une zone **inversée** fait l'inverse
(`10.10.10.10` → `srv-ad01`) : journaux lisibles, et certains outils l'exigent. Une par VLAN.

🖱️ Console **DNS** > clic droit sur **Zones de recherche inversée** > **Nouvelle zone** :

| Écran | Choix | Pourquoi |
| --- | --- | --- |
| Type | Zone principale, ✅ stocker dans Active Directory | Répliquée avec l'AD, sécurisée |
| Réplication | Tous les serveurs DNS de **ce domaine** | |
| Type de recherche | IPv4 | |
| ID réseau | `10.10.10` | 💡 La zone s'appellera `10.10.10.in-addr.arpa` : les chiffres sont **à l'envers** (le VLAN 20 donne `20.10.10.in-addr.arpa`) |
| Mise à jour dynamique | ⭐ **N'autoriser que les mises à jour dynamiques sécurisées** | Seule une machine **membre du domaine** peut inscrire son nom : un intrus ne peut pas se déclarer `srv-ad01` |

![Console DNS](captures/52-console-dns.png)
![ID réseau](captures/54-zone-inverse-id-reseau.png)
![Mises à jour sécurisées](captures/55-zone-inverse-maj-securisees.png)
![Zone créée](captures/56-zone-inverse-10-10-10-creee.png)

⌨️ Les 4 autres zones (20, 30, 40, 99) en PowerShell, d'un coup :

```powershell
20,30,40,99 | % { Add-DnsServerPrimaryZone -NetworkId "10.10.$_.0/24" -ReplicationScope Domain -DynamicUpdate Secure }
```
- `20,30,40,99 | % { … }` : « pour chaque nombre de la liste, fais… » (`%` = raccourci de `ForEach-Object`,
  `$_` = le nombre en cours) ;
- `Add-DnsServerPrimaryZone` : crée la zone, avec les mêmes options qu'à l'interface.

![Zones PowerShell](captures/57-zones-inverses-powershell.png)

⌨️ **Test** :

```powershell
nslookup 10.10.10.10
ipconfig /registerdns
nslookup 10.10.10.10
```
✅ D'abord « Non-existent domain » (la zone est vide), puis après `ipconfig /registerdns` (« inscris-toi
dans le DNS ») et une minute d'attente : `SRV-AD01.lab.home.arpa`.

![Vide](captures/58-nslookup-inverse-vide.png)
![registerdns](captures/59-ipconfig-registerdns.png)
![OK](captures/60-nslookup-inverse-ok.png)

### Étape 13 · 🪤 Le piège de `home.arpa`

❌ **Constat** : la zone `lab.home.arpa` est rangée dans **Zones de recherche inversée**, et la zone
directe paraît vide.

💡 **Cause** : Windows considère que **toute zone qui finit par `.arpa` est inversée** (parce que les
zones inversées s'appellent `….in-addr.arpa`). PowerShell le confirme : `IsReverseLookupZone = True`.
**La résolution fonctionne** ; seul le **classement** (et certains menus) est faux.

![Zone directe vide à l'affichage](captures/61-zone-directe-vide-affichage.png)
![Toutes dans inversées](captures/62-toutes-zones-dans-inversees.png)
![PowerShell](captures/53-zones-dns-powershell.png)

🏢 En entreprise, on choisit un **sous-domaine d'un nom qu'on possède** : `ad.aerotrans.fr`. Ni `.local`,
ni `home.arpa`. Renommer un domaine existant est trop lourd : on garde pour le lab, et on documente.

### Étape 14 · La santé du contrôleur de domaine

⌨️

```powershell
dcdiag /q
dcdiag | Select-String "ussi|chou"
```
- `dcdiag` : le **bilan de santé** d'un DC (une trentaine de tests) ; `/q` = silencieux : n'affiche **que
  les erreurs**. ✅ Rien ne s'affiche = **aucune erreur**.
- Pour le **prouver** : `Select-String "ussi|chou"` garde les lignes contenant « ré**ussi** » ou
  « é**chou**é ». ✅ **28 tests réussis, 0 échec**.

![dcdiag /q](captures/63-dcdiag-q-aucune-erreur.png)
![Liste](captures/64-dcdiag-liste-tests.png)
![28 réussis](captures/65-dcdiag-28-reussis.png)

❌ Le filtre `"test"` ne suffit pas : en français, le **verdict** est écrit sur la **ligne suivante**.

---

## Partie 6 — L'organisation AEROTRANS dans l'annuaire

### Étape 15 · Les conventions d'abord, puis les OU

🎯 Avant de créer quoi que ce soit, on **écrit les règles de nommage** ([conventions.md](../docs/conventions.md)) :
n'importe quel admin qui arrivera après doit s'y retrouver.

💡 Les « dossiers » `Users` et `Computers` créés par Windows **ne sont pas des OU** : on ne peut pas y
lier de GPO. On crée donc notre propre arborescence.

![Users par défaut](captures/66-aduc-dossier-users.png)

🖱️ **Outils** > **Utilisateurs et ordinateurs Active Directory** > clic droit sur `lab.home.arpa` >
**Nouveau** > **Unité d'organisation** > `AEROTRANS`, ✅ **Protéger le conteneur contre une suppression
accidentelle** > **OK**.

💡 Avec la protection, même un admin du domaine ne peut pas supprimer l'OU sans décocher la case d'abord.

![OU racine](captures/67-ou-racine-aerotrans.png)

⌨️ Les 16 sous-OU en PowerShell (protection activée par défaut) :

```powershell
$base = "OU=AEROTRANS,DC=lab,DC=home,DC=arpa"
"Utilisateurs","Ordinateurs","Serveurs","Groupes","Admins","Comptes-service","Desactives" | % { New-ADOrganizationalUnit -Name $_ -Path $base }
"Direction","Comptabilite","RH","Commercial","Operations","Accueil","Informatique" | % { New-ADOrganizationalUnit -Name $_ -Path "OU=Utilisateurs,$base" }
"Postes-fixes","Portables" | % { New-ADOrganizationalUnit -Name $_ -Path "OU=Ordinateurs,$base" }
```
- `$base = "…"` : une **variable** qui garde l'adresse de l'OU AEROTRANS, pour ne pas la retaper ;
- chaque ligne : « pour chaque nom de la liste, crée une OU à cet endroit ».

![Sous-OU Utilisateurs](captures/68a-sous-ou-utilisateurs.png)
![Sous-OU Ordinateurs](captures/68b-sous-ou-ordinateurs.png)
![Arborescence](captures/69-arborescence-ou-aerotrans.png)

❌ **Erreurs repérées avant d'appuyer sur Entrée** : variable `$base` écrasée (chemin sans AEROTRANS),
un accent, `Operation` sans « s », `Acceuil`, un guillemet non fermé. 👉 **On relit une commande avant
de la lancer**, surtout quand elle crée 16 objets.

### Étape 16 · La corbeille AD et les redirections

🖱️ **Centre d'administration Active Directory** > `lab (local)` > à droite **Activer la corbeille** >
**OK** (Windows prévient : c'est **irréversible**).

💡 Sans corbeille, un compte supprimé par erreur est perdu avec ses groupes. Avec, il **revient tel quel**.

![Corbeille](captures/70-corbeille-ad-activee.png)

⌨️ Les redirections :

```powershell
redircmp "OU=Ordinateurs,OU=AEROTRANS,DC=lab,DC=home,DC=arpa"
redirusr "OU=Utilisateurs,OU=AEROTRANS,DC=lab,DC=home,DC=arpa"
```
💡 Sans `redircmp`, un nouveau PC joint au domaine arrive dans `Computers`, où **aucune GPO ne
s'applique**. Avec, il arrive directement dans notre OU `Ordinateurs`. Idem pour les comptes avec `redirusr`.

✅ « La redirection a réussi ».

![redircmp](captures/77a-redircmp-reussi.png)
![redirusr](captures/77b-redirusr-reussi.png)

---

## Partie 7 — Les comptes d'administration

### Étape 17 · Créer le compte admin nominatif adm.paulo.rosa

💡 **Pourquoi pas `Administrateur` au quotidien ?** Un compte = une personne (traçabilité), et le nom
`Administrateur` est connu de **tous** les attaquants. Et pourquoi **deux** comptes pour un admin ? Si on
clique sur un lien piégé avec un compte admin, **tout le domaine** est compromis.

| Compte | Où | Groupes | Usage |
| --- | --- | --- | --- |
| `Administrateur` | Users | (intégré) | **Secours** uniquement, mot de passe au coffre |
| `adm.paulo.rosa` | AEROTRANS/Admins | Admins du domaine, **Protected Users** | Administration uniquement |
| `paulo.rosa` | Utilisateurs/Informatique | GG_Informatique | Quotidien (mails, Internet), sans droit d'admin |

🖱️ Utilisateurs et ordinateurs AD > `AEROTRANS` > **Admins** > clic droit > **Nouveau** > **Utilisateur** :
prénom `Paulo`, nom `Rosa`, nom complet `Paulo Rosa (admin)`, ouverture de session `adm.paulo.rosa` >
mot de passe (15 caractères minimum), **aucune case cochée** > **Terminer**.

![Création](captures/71-creation-adm-paulo-rosa.png)
![Cases](captures/72-adm-mot-de-passe-cases.png)
![Créé](captures/73-adm-paulo-rosa-cree.png)

🖱️ Double-clic sur le compte :
- onglet **Membre de** > **Ajouter** > `Admins du domaine` et `Protected Users` ;
- onglet **Compte** > ✅ **Le compte est sensible et ne peut pas être délégué**.

| Réglage | Effet |
| --- | --- |
| **Admins du domaine** (et pas `Builtin\Administrateurs`) | Droits sur **tout** le domaine, postes compris. `Builtin\Administrateurs` ne donne des droits que sur les DC |
| **Protected Users** | Pas d'identifiants gardés en mémoire sur les machines, pas de NTLM, ticket Kerberos limité à 4 h |
| **Compte sensible** | Aucun serveur ne peut « emprunter » l'identité de l'admin |

Les groupes **Administrateurs de l'entreprise** et **Administrateurs du schéma** restent **vides**
(moindre privilège : on y entre seulement le temps d'une opération, voir briques 04 et 05).

![Membre de](captures/74-adm-membre-de.png)
![Compte sensible](captures/75-adm-compte-sensible.png)

⌨️ **Test** : déconnexion, connexion en `LAB\adm.paulo.rosa`, puis `whoami /groups`.
✅ `LAB\Admins du domaine` et `LAB\Protected Users`, « Groupe activé ».

![whoami](captures/76-whoami-groupes-adm.png)

🖱️ Le compte du quotidien `paulo.rosa` est créé dans `Utilisateurs/Informatique`, sans aucun droit d'admin.

![paulo.rosa](captures/78-compte-paulo-rosa-informatique.png)

---

## Partie 8 — L'heure du contrôleur de domaine

### Étape 18 · Synchroniser l'heure sur pfSense

💡 **Kerberos refuse toute connexion si l'horloge a plus de 5 minutes d'écart.** Un DC à la mauvaise
heure = plus personne ne se connecte.

⌨️ **Constat** :

```powershell
w32tm /query /source
w32tm /stripchart /computer:10.10.10.254 /samples:5
```
- `w32tm /query /source` : d'où le DC prend son heure. ❌ `Free-running System Clock` = **aucune source**,
  il compte tout seul.
- `/stripchart` : compare l'heure avec pfSense. ✅ pfSense répond ; écart **+21,5 s** en 3 jours
  (≈ 7 s par jour : la limite de 5 min serait atteinte en 6 à 7 semaines).

![Source avant](captures/79-w32tm-source-avant.png)
![Écart](captures/80-stripchart-ecart-21s.png)

⌨️ **Réglage** (source = pfSense, qui est le **seul** à prendre l'heure sur Internet) :

```powershell
w32tm /config /manualpeerlist:"10.10.10.254,0x8" /syncfromflags:manual /reliable:yes /update
Restart-Service w32time
w32tm /resync /rediscover
w32tm /query /status
```
- `/manualpeerlist:"10.10.10.254,0x8"` : la source d'heure (le `0x8` = mode client) ;
- `/syncfromflags:manual` : utiliser cette liste ; `/reliable:yes` : le DC devient la référence pour les PC ;
- `Restart-Service w32time` puis `/resync` : appliquer et se synchroniser maintenant.

✅ Source `10.10.10.254`, **strate 3**, écart 21,5 s → 8 s → 2 s → quelques millisecondes.
💡 La correction est **progressive** (pas de saut d'heure brutal, qui perturberait les journaux) : voulu.

![Config](captures/81-w32tm-config-pfsense.png)
![Convergence](captures/82-w32tm-status-convergence.png)

---

## Partie 9 — Le pare-feu du VLAN Serveurs au moindre privilège

### Étape 19 · Remplacer « Serveurs → tout » par les seuls flux utiles

🎯 Un serveur compromis ne doit pouvoir joindre **que** ce dont il a besoin. Méthode complète :
[procédure pare-feu](../docs/procedure-pare-feu.md) (sauvegarde de la configuration, photo de l'état
initial, alias, nouvelles règles, ancienne règle **désactivée** pour pouvoir revenir en arrière, tests,
journaux, suppression le lendemain).

![Avant](captures/85-regles-serveurs-avant.png)

🖱️ **Firewall > Aliases** :

| Alias | Type | Contenu | Rôle |
| --- | --- | --- | --- |
| `PORTS_WEB` | Port(s) | `80`, `443` | Les ports du web |
| `RESEAUX_PRIVES` | Network(s) | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | Tous les réseaux privés (RFC 1918) |

![PORTS_WEB](captures/83-alias-ports-web.png)
![RESEAUX_PRIVES](captures/84-alias-reseaux-prives.png)

🖱️ **Firewall > Rules > SERVEURS** :

| # | Action | Destination | Port | Pourquoi |
| --- | --- | --- | --- | --- |
| 1 | Block | Réseau d'administration | tout | |
| 2 | Block | pfSense | TCP 443 | Interface web |
| 3 | Pass | pfSense (SERVEURS address) | **TCP/UDP** 53 | Redirecteur DNS. TCP aussi : les grosses réponses DNS passent en TCP |
| 4 | Pass | pfSense | UDP 123 | L'heure (NTP) |
| 5 | Pass | **`! RESEAUX_PRIVES`** (Invert match ✅) | `PORTS_WEB` | Mises à jour, **Internet uniquement** : le `!` (inversion) interdit d'utiliser ces ports vers les autres VLAN |
| 6 | Pass | tout | ICMP echo request | Le ping, pour le dépannage |

![Règle DNS](captures/86-regle-a-dns.png)
![Règle DNS corrigée](captures/86b-regle-a-dns-corrigee.png)
![NTP](captures/87a-regle-b-ntp.png)
![Web Internet](captures/87b-regle-c-web-internet.png)
![Ping](captures/87c-regle-d-ping.png)

❌ **Erreur du lab** : au premier « Apply », l'ancienne règle « any » était encore **au-dessus** : les
nouvelles règles restaient à **0 octet**. 💡 **La première règle qui correspond gagne** : tout passait par
l'ancienne. ✅ Ancienne règle **désactivée** (pas supprimée tout de suite), puis supprimée le lendemain.

![Any encore actif](captures/88a-regles-ajoutees-any-encore-actif.png)
![Any désactivée](captures/120a-regle-any-desactivee-avant-suppression.png)
![Règles finales](captures/120-regles-serveurs-finales.png)

⌨️ **Tests** (sur SRV-AD01) : ce qui doit passer, **et** ce qui doit être bloqué :

| Test | Attendu | Résultat |
| --- | --- | --- |
| `Resolve-DnsName google.fr` | réponse | ✅ |
| `Test-NetConnection www.microsoft.com -Port 443` | `True` | ✅ |
| `ping 1.1.1.1` | réponses | ✅ |
| `Test-NetConnection 1.1.1.1 -Port 53` (DNS en direct, sans pfSense) | `False` | ✅ bloqué |
| `Test-NetConnection 192.168.1.254 -Port 80` (un réseau privé) | `False` | ✅ bloqué |

💡 `Test-NetConnection … -Port …` essaie d'ouvrir une connexion TCP : `TcpTestSucceeded : True` = ça passe.
Un test bloqué prend ~20 s (5 tentatives TCP avant d'abandonner).

![Autorisés](captures/89-tests-flux-autorises.png)
![Bloqués](captures/90-tests-flux-bloques.png)

✅ Les blocages apparaissent dans **Status > System Logs > Firewall** (« Default deny rule »).

![Journal](captures/91-journal-blocages-serveurs.png)

❌ Le journal de pfSense avait **2 h de décalage** : la journalisation avait démarré en UTC, avant le réglage
du fuseau. ✅ Corrigé par un redémarrage de pfSense.

![Fuseau](captures/116-pfsense-timezone.png)
![Heure corrigée](captures/118-journal-heure-corrigee.png)

---

## Partie 10 — Le DHCP Windows et le relais pfSense

### Étape 20 · Installer et autoriser le DHCP

💡 **Pourquoi le DHCP sur Windows plutôt que sur pfSense ?** Le serveur DHCP doit être **autorisé dans
l'AD** (protection contre un faux serveur DHCP branché par quelqu'un), et il **inscrit les postes dans le
DNS** du domaine.

🖱️ **Ajouter des rôles** > ✅ **Serveur DHCP** > Installer. Puis drapeau ⚠️ > **Terminer la configuration
DHCP** > **Valider** (crée les groupes de sécurité et **autorise** le serveur dans l'AD).

![Rôle DHCP](captures/92-role-dhcp-coche.png)
![Installation](captures/93-installation-dhcp.png)
![Post-déploiement](captures/93b-post-deploiement-a-faire.png)
![Terminé](captures/93c-post-deploiement-termine.png)

### Étape 21 · L'étendue du VLAN Postes

🖱️ **Outils** > **DHCP** > `srv-ad01` > **IPv4** > clic droit > **Nouvelle étendue** :

| Écran | Valeur | Pourquoi |
| --- | --- | --- |
| Nom | `POSTES-VLAN20` | |
| Plage | `10.10.20.100` à `10.10.20.199`, masque /24 | `.1` à `.99` gardées pour les adresses fixes |
| Durée du bail | **8 jours** | Un PC de bureau garde son adresse longtemps |
| Routeur | `10.10.20.254` | pfSense, la passerelle du VLAN |
| Serveur DNS | `10.10.10.10` | ⭐ Le DC : sinon les PC ne trouveraient pas le domaine |
| Domaine | `lab.home.arpa` | |
| Activer l'étendue | Oui | |

![Options](captures/94-options-etendue.png)
![Active](captures/94a-etendue-active.png)
![Pool](captures/95-pool-adresses.png)

### Étape 22 · Le relais DHCP sur pfSense

💡 Une demande DHCP est un **cri dans la pièce** (broadcast) : elle ne sort pas de son VLAN. Le serveur est
dans le VLAN 10, les postes dans le VLAN 20. Le **relais** (pfSense) entend le cri et le **transmet** au serveur.

🖱️ pfSense, **dans cet ordre** :
1. **Services > DHCP Server > POSTES** : ❌ décocher **Enable** (le DHCP temporaire de la brique 01) >
   **Save**. Sinon le relais refuse de démarrer.
2. **Services > DHCP Relay** : ✅ Enable, interface **POSTES**, serveur **`10.10.10.10`** > **Save**.

![DHCP pfSense désactivé](captures/96-pfsense-dhcp-poste-desactive.png)
![Relais](captures/97-pfsense-relais-dhcp.png)

⌨️ **Test** depuis la VM de test du VLAN 20 (redémarrée pour partir sans ancien bail) : `udhcpc`

```
udhcpc: broadcasting discover
udhcpc: broadcasting select for 10.10.20.100, server 10.10.10.10
udhcpc: lease of 10.10.20.100 obtained from 10.10.10.10, lease time 691200
```
✅ Le bail vient bien de **10.10.10.10** (Windows), pour 691 200 s = **8 jours**. Il apparaît dans la
console DHCP (**Baux d'adresses**).

❌ **Erreur du lab** : une faute de frappe dans la commande (`udhcp` au lieu de `udhcpc`).

![Faute de frappe](captures/98a-udhcp-faute-de-frappe.png)
![Bail obtenu](captures/98-udhcpc-bail-obtenu.png)
![Baux](captures/99-baux-dhcp.png)

💡 **Observation honnête** : on s'attendait à ce que les nouvelles règles du VLAN Serveurs bloquent la
réponse du serveur. Ça n'a pas été le cas : pfSense crée des **règles automatiques** quand le relais est
actif (trouvées dans `/tmp/rules.debug`, ligne « allow access to DHCP relay »). Le retour reste à
confirmer par une capture de paquets.

![Règles automatiques](captures/119-regles-automatiques-relais.png)

❌ **Effet de bord de `redirusr`** : les groupes « Administrateurs DHCP » et « Utilisateurs DHCP » sont
arrivés dans `AEROTRANS/Utilisateurs`. ✅ Déplacés dans `Groupes`.

![Groupes DHCP mal rangés](captures/103c-groupes-dhcp-dans-utilisateurs.png)
![Déplacés](captures/105-groupes-dhcp-deplaces.png)

---

## Partie 11 — Les groupes et les salariés

### Étape 23 · Les groupes par service

🖱️ OU **Groupes** > clic droit > **Nouveau** > **Groupe**, 7 fois : `GG_Direction`, `GG_Comptabilite`,
`GG_RH`, `GG_Commercial`, `GG_Operations`, `GG_Accueil`, `GG_Informatique` ; étendue **Globale**, type
**Sécurité**, avec une **description**.

💡 **GG** = groupe **global** : il contient des **comptes**. Plus tard, on donnera les droits à des groupes
**domaine local** (`DL_…`) qui contiendront les `GG_` : c'est la méthode **AGDLP** (voir conventions).

![Groupes](captures/100-groupes-gg.png)
![Membres GG_Informatique](captures/100b-gg-informatique-membres.png)

### Étape 24 · Importer 24 salariés depuis un fichier CSV

🎯 Comme en vrai : les RH envoient un **fichier** avec les nouveaux salariés ; on ne crée pas 24 comptes à
la main. Le script [`Import-AerotransUsers.ps1`](scripts/Import-AerotransUsers.ps1) lit
[`aerotrans-salaries.csv`](scripts/aerotrans-salaries.csv) et, pour chaque ligne : identifiant
`prenom.nom` sans accent, la bonne OU, le bon groupe, un mot de passe **provisoire** à changer à la
première connexion. Il est **relançable** sans risque (un compte existant est ignoré).

🖱️ **Apporter les fichiers dans la VM** : pas de copier-coller dans la console Proxmox. On fabrique une
petite **ISO** contenant les fichiers, on la téléverse dans Proxmox et on l'insère dans le lecteur CD de
SRV-AD01 (elle apparaît en `E:`).

![ISO](captures/101a-upload-iso-proxmox.png)
![Insérée](captures/101-iso-insere-vm200.png)
![Lecteur E:](captures/101b-lecteur-e-aerotrans.png)

⌨️ **Simulation d'abord** (rien n'est créé, le script dit ce qu'il **ferait**) :

```powershell
.\Import-AerotransUsers.ps1 -CsvPath .\aerotrans-salaries.csv -Simulation
```
✅ 24 comptes à créer, 0 erreur.

![Simulation](captures/102-script-simulation.png)

❌ **Incident** : 1re exécution réelle avec un mot de passe provisoire **vide** → **24 erreurs**, et 24 comptes
créés **désactivés, sans mot de passe ni groupe**. À la relance, le script les a **ignorés** (« déjà présents »).

![24 erreurs](captures/103a-script-mdp-vide-24-erreurs.png)
![Déjà présents](captures/103b-script-relance-deja-presents.png)
![Comptes cassés](captures/103d-comptes-operations-casses.png)
![Liste](captures/104-liste-comptes-casses.png)

✅ **Correction propre** :

| Étape | Action |
| --- | --- |
| Constat | `Get-ADUser -Filter "Company -eq 'AEROTRANS'"` → 24 comptes, `Enabled = False` |
| Ciblage | **Seuls** les comptes marqués « AEROTRANS » par le script (le compte `paulo.rosa` n'est pas touché) |
| Correction | Suppression (ils passent par la **corbeille AD**), relance avec un mot de passe conforme |
| Contrôle | 24 comptes `Enabled = True`, `GG_Operations` = 14 membres |
| Prévention | **Script v2** : supprime un compte créé à moitié et **s'arrête** au premier mot de passe refusé |

![24 créés](captures/106-script-24-crees.png)
![Activés](captures/107a-comptes-actives.png)
![14 dans Operations](captures/107b-gg-operations-14.png)

💡 **Leçon** : la simulation ne pouvait pas détecter ce problème (elle ne teste pas le mot de passe). Un
script doit **s'arrêter** à la première erreur grave plutôt que de continuer à moitié.

---

## Partie 12 — Les mots de passe et la première GPO

### Étape 25 · La politique de mot de passe du domaine

🖱️ **Gestion des stratégies de groupe** > `lab.home.arpa` > clic droit sur **Default Domain Policy** >
**Modifier** > Configuration ordinateur > Stratégies > Paramètres Windows > Paramètres de sécurité >
**Stratégies de comptes** :

| Paramètre | Valeur | Défaut |
| --- | --- | --- |
| Longueur minimale | **12** | 7 |
| Complexité | Activée | |
| Historique | 24 | |
| Durée de vie | 1 à 365 jours | |
| Verrouillage | 10 essais, 15 min, compteur 15 min | |

💡 C'est **la seule** modification faite dans la Default Domain Policy (les autres réglages vont dans nos
propres GPO). **365 jours** : il n'y a pas de consensus. Les recommandations récentes déconseillent de
forcer le changement d'un mot de passe long (surtout avec double authentification) ; beaucoup de PME
gardent un renouvellement annuel.

![Mots de passe](captures/108-strategie-mot-de-passe.png)
![Verrouillage](captures/109-strategie-verrouillage.png)
![Appliquée](captures/110-politique-mdp-appliquee.png)

### Étape 26 · Une règle plus stricte pour les admins (PSO-Admins)

💡 Une **FGPP** (stratégie de mot de passe affinée) s'applique à un **groupe** et remplace celle du domaine.

🖱️ **Centre d'administration AD** > `lab (local)` > **System** > **Password Settings Container** >
**Nouveau** > **Paramètres de mot de passe** : nom `PSO-Admins`, priorité `10`, longueur **15**, complexité,
historique 24, durée 1 à **180** jours, verrouillage 10 / 15 / 15 min, ✅ protection contre la suppression ;
**S'applique à** : `Admins du domaine`.

![PSO-Admins](captures/112-pso-admins-description.png)
![Cible](captures/112a-pso-admins-cible.png)

⌨️ **Vérification** :

```powershell
Get-ADUserResultantPasswordPolicy adm.paulo.rosa
Get-ADUserResultantPasswordPolicy paulo.rosa
```
✅ `adm.paulo.rosa` → **PSO-Admins** ; `paulo.rosa` → rien (donc la politique du domaine).

![Politique résultante](captures/113-resultant-password-policy.png)

### Étape 27 · La première GPO : verrouiller la session après 10 minutes

🎯 Un PC laissé ouvert à l'accueil se **verrouille tout seul**.

🖱️ **Gestion des stratégies de groupe** > `lab.home.arpa` > **Objets de stratégie de groupe** > clic
droit > **Nouveau** > `C_Securite_Verrouillage_Inactivite`.

💡 On la **crée d'abord sans la lier** (dans « Objets de stratégie de groupe ») : on la configure, **puis**
on la lie. Jamais une GPO à moitié prête appliquée aux PC.

![Créée non liée](captures/115a-gpo-creee-non-liee.png)

🖱️ Clic droit > **Modifier** > Configuration ordinateur > Stratégies > Paramètres Windows > Paramètres de
sécurité > Stratégies locales > **Options de sécurité** > « **Ouverture de session interactive : limite
d'inactivité de l'ordinateur** » > ✅ Définir > **600** secondes.

❌ **Piège évité** : le paramètre voisin « seuil de verrouillage du **compte d'ordinateur** » (en
**tentatives**, pas en secondes) avait été ouvert par erreur. 👉 Vérifier l'**unité** et lire l'onglet
**Expliquer** avant de valider.

![Mauvais paramètre](captures/114a-mauvais-parametre-seuil-compte.png)
![600 s](captures/114-limite-inactivite-600s.png)
![Défini](captures/114b-gpo-parametre-defini.png)

🖱️ Clic droit sur l'OU **AEROTRANS/Ordinateurs** > **Lier un objet de stratégie de groupe existant** >
`C_Securite_Verrouillage_Inactivite`.

💡 Liée à **Ordinateurs** parce que c'est un paramètre de **configuration ordinateur** : il ne s'applique
qu'aux objets **ordinateurs**. Liée à une OU d'utilisateurs, elle ne ferait **rien**, sans aucune erreur.
Elle est **héritée** par Postes-fixes et Portables. Test réel sur un poste Windows 11 : brique 04.

![Lier](captures/115b-lier-gpo.png)
![Liée](captures/115-gpo-liee-ordinateurs.png)

### Étape 28 · Les alertes rouges du Gestionnaire de serveur

❌ Deux alertes rouges « Services » : `spice-agent` (inutile sans affichage SPICE) et `InventorySvc` (qui
s'arrête tout seul après sa tâche) sont en démarrage **automatique**. ✅ Passés en **manuel** : tableau de bord vert.

![Alertes](captures/111a-alertes-services-rouge.png)
![Détail](captures/111b-services-arretes-detail.png)
![spice-agent](captures/111c-spice-agent-manuel.png)
![InventorySvc](captures/111d-inventorysvc-manuel.png)
![Tout vert](captures/111-tableau-de-bord-vert.png)

🖱️ Fin : ISO éjectées du lecteur de la VM.

![ISO éjectées](captures/121-iso-ejectees-vm200.png)

---

## Annexes

### A. Dépannages rencontrés

| Symptôme | Cause | Solution |
| --- | --- | --- |
| Aucun disque à l'installation | Pilote VirtIO SCSI absent | `vioscsi\2k25\amd64` |
| Adresse 169.254.x.x | Pas de DHCP dans le VLAN 10 | IP fixe |
| Ping 100 % perte vers pfSense | Refus par défaut, aucune règle | Règles du VLAN Serveurs |
| Ping OK mais « pas d'Internet » | DNS = lui-même, rôle DNS pas installé | DNS temporaire pfSense |
| SRV introuvable | Faute de frappe `_mcdcs` | `_msdcs` |
| `lab.home.arpa` dans les zones inversées | Windows classe tout `.arpa` en inversé | Sans effet ; en entreprise `ad.entreprise.fr` |
| `dcdiag \| Select-String "test"` sans verdict | Verdict sur la ligne suivante en français | Filtre `"ussi\|chou"` |
| Nouvelles règles à 0 octet | Règle « any » encore au-dessus | Ordre des règles, désactivation |
| 24 comptes désactivés | Mot de passe provisoire vide | Suppression ciblée, relance, script v2 |
| Groupes DHCP dans Utilisateurs | Effet de `redirusr` | Déplacés dans Groupes |
| Journal pfSense décalé de 2 h | Journalisation démarrée en UTC | Redémarrage de pfSense |
| 2 alertes rouges « Services » | Services en automatique qui s'arrêtent seuls | Démarrage manuel |

### B. Équivalents PowerShell

```powershell
# Réseau et nom
Rename-Computer -NewName SRV-AD01 -Restart
New-NetIPAddress -InterfaceAlias Ethernet -IPAddress 10.10.10.10 -PrefixLength 24 -DefaultGateway 10.10.10.254
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 10.10.10.10

# Rôle et promotion (le mot de passe DSRM est demandé, jamais écrit dans le script)
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName lab.home.arpa -DomainNetbiosName LAB `
  -ForestMode Win2025 -DomainMode Win2025 -InstallDns `
  -SafeModeAdministratorPassword (Read-Host "DSRM" -AsSecureString)

# DNS
Add-DnsServerForwarder -IPAddress 10.10.10.254
10,20,30,40,99 | % { Add-DnsServerPrimaryZone -NetworkId "10.10.$_.0/24" -ReplicationScope Domain -DynamicUpdate Secure }

# OU, corbeille, redirections
$base = "OU=AEROTRANS,DC=lab,DC=home,DC=arpa"
New-ADOrganizationalUnit -Name AEROTRANS -Path "DC=lab,DC=home,DC=arpa"
"Utilisateurs","Ordinateurs","Serveurs","Groupes","Admins","Comptes-service","Desactives" | % { New-ADOrganizationalUnit -Name $_ -Path $base }
"Direction","Comptabilite","RH","Commercial","Operations","Accueil","Informatique" | % { New-ADOrganizationalUnit -Name $_ -Path "OU=Utilisateurs,$base" }
"Postes-fixes","Portables" | % { New-ADOrganizationalUnit -Name $_ -Path "OU=Ordinateurs,$base" }
Enable-ADOptionalFeature -Identity "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target lab.home.arpa
redircmp "OU=Ordinateurs,$base"
redirusr "OU=Utilisateurs,$base"

# Compte admin
New-ADUser -Name "Paulo Rosa (admin)" -GivenName Paulo -Surname Rosa -SamAccountName adm.paulo.rosa `
  -UserPrincipalName adm.paulo.rosa@lab.home.arpa -Path "OU=Admins,$base" `
  -AccountPassword (Read-Host -AsSecureString) -Enabled $true -AccountNotDelegated $true
Add-ADGroupMember "Admins du domaine" -Members adm.paulo.rosa
Add-ADGroupMember "Protected Users" -Members adm.paulo.rosa

# Heure
w32tm /config /manualpeerlist:"10.10.10.254,0x8" /syncfromflags:manual /reliable:yes /update
Restart-Service w32time ; w32tm /resync /rediscover

# DHCP
Install-WindowsFeature DHCP -IncludeManagementTools
Add-DhcpServerSecurityGroup
Add-DhcpServerInDC -DnsName srv-ad01.lab.home.arpa -IPAddress 10.10.10.10
Add-DhcpServerv4Scope -Name POSTES-VLAN20 -StartRange 10.10.20.100 -EndRange 10.10.20.199 -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00 -State Active
Set-DhcpServerv4OptionValue -ScopeId 10.10.20.0 -Router 10.10.20.254 -DnsServer 10.10.10.10 -DnsDomain lab.home.arpa

# Groupes et salariés
"Direction","Comptabilite","RH","Commercial","Operations","Accueil","Informatique" | % {
  New-ADGroup -Name "GG_$_" -GroupScope Global -GroupCategory Security -Path "OU=Groupes,$base" -Description "Salariés du service $_" }
.\Import-AerotransUsers.ps1 -CsvPath .\aerotrans-salaries.csv -Simulation
.\Import-AerotransUsers.ps1 -CsvPath .\aerotrans-salaries.csv

# Mots de passe
Set-ADDefaultDomainPasswordPolicy -Identity lab.home.arpa -MinPasswordLength 12 -ComplexityEnabled $true `
  -PasswordHistoryCount 24 -MinPasswordAge 1.00:00:00 -MaxPasswordAge 365.00:00:00 `
  -LockoutThreshold 10 -LockoutDuration 00:15:00 -LockoutObservationWindow 00:15:00
New-ADFineGrainedPasswordPolicy -Name PSO-Admins -Precedence 10 -MinPasswordLength 15 -ComplexityEnabled $true `
  -PasswordHistoryCount 24 -MinPasswordAge 1.00:00:00 -MaxPasswordAge 180.00:00:00 `
  -LockoutThreshold 10 -LockoutDuration 00:15:00 -LockoutObservationWindow 00:15:00 -ProtectedFromAccidentalDeletion $true
Add-ADFineGrainedPasswordPolicySubject PSO-Admins -Subjects "Admins du domaine"

# GPO (le paramètre « limite d'inactivité » = la valeur de registre InactivityTimeoutSecs)
New-GPO -Name C_Securite_Verrouillage_Inactivite
Set-GPRegistryValue -Name C_Securite_Verrouillage_Inactivite -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
  -ValueName InactivityTimeoutSecs -Type DWord -Value 600
New-GPLink -Name C_Securite_Verrouillage_Inactivite -Target "OU=Ordinateurs,$base"
```

### C. Écarts entre le lab et l'entreprise

| Dans le lab | En entreprise | Pourquoi l'écart |
| --- | --- | --- |
| Domaine `lab.home.arpa` | `ad.entreprise.fr` | Choix fait avant de connaître le piège `.arpa` ; renommer un domaine est lourd |
| **Un seul** contrôleur de domaine | **Au moins deux** | Si l'unique DC tombe, plus personne ne se connecte. SRV-AD02 prévu |
| DHCP sur un seul serveur | Basculement (failover) entre deux serveurs | Même raison |
| Instantané avant la promotion | Sauvegarde de l'état système | Un seul DC |
| Administration depuis la console Proxmox | Bureau à distance depuis le VLAN d'administration | Attend le switch (brique 02) |
| Mot de passe provisoire commun | Unique par salarié, remis en main propre | Simplification du lab |
| Interface graphique | Installation Core | Apprentissage |
| Licence d'évaluation | Licence Standard + licences d'accès client (CAL) | Lab |

### D. Utilisation en entreprise : 3 cas concrets

1. **Arrivée d'un salarié** : une ligne dans le CSV, le script crée le compte au bon endroit, dans le bon
   groupe ; le salarié change son mot de passe à sa première connexion.
2. **Départ d'un salarié** : compte désactivé et déplacé dans `Desactives` le jour même ; suppression
   après quelques mois. En cas d'erreur, la corbeille AD le restaure.
3. **Un serveur est compromis** : il ne peut joindre ni le réseau d'administration, ni un DNS extérieur,
   ni les autres VLAN ; ses tentatives apparaissent dans les journaux du pare-feu.

### E. Questions d'entretien (avec la réponse)

- **Différence entre une OU et un groupe ?** L'OU **range** les objets et reçoit les GPO ; le groupe sert à
  **donner des droits**.
- **Pourquoi le DNS du DC pointe-t-il vers lui-même ?** C'est lui qui connaît la zone du domaine et les
  enregistrements SRV qui permettent aux postes de trouver un DC.
- **À quoi sert une zone inversée ?** IP → nom : journaux lisibles, certains outils l'exigent.
- **Pourquoi l'heure est-elle critique dans un domaine ?** Kerberos refuse plus de 5 minutes d'écart.
- **Pourquoi deux comptes par admin ?** Un clic sur un lien piégé avec un compte admin compromet tout le domaine.
- **Que fait Protected Users ?** Pas d'identifiants en mémoire, pas de NTLM, ticket de 4 h.
- **Pourquoi ne pas restaurer un instantané de DC ?** *USN rollback* : l'annuaire se désynchronise des autres DC.
- **Une GPO ne s'applique pas, que vérifies-tu ?** Liée à la bonne OU (ordinateur ou utilisateur selon la
  partie configurée), objet bien dans l'OU (pas dans `Computers`), filtrage de sécurité, puis `gpresult /r`
  et `gpupdate /force`.
- **Qu'est-ce qu'une FGPP ?** Une politique de mot de passe appliquée à un groupe, qui remplace celle du domaine.
- **Pourquoi un relais DHCP ?** La demande DHCP est un broadcast qui ne sort pas de son VLAN.
- **À quoi sert la corbeille AD ?** Restaurer un objet supprimé avec tous ses attributs et groupes.

### F. Points en suspens

- 2e contrôleur de domaine (SRV-AD02) et basculement DHCP.
- Étendues DHCP des VLAN Wi-Fi (30, 40).
- Règles précises du VLAN Postes (ports AD) : en cours (voir [matrice des flux](../docs/matrice-des-flux.md)).
- Confirmer le retour du relais DHCP par une capture de paquets.
- Compte dédié pour les mises à jour DNS du serveur DHCP (`Set-DhcpServerDnsCredential`).
- Mot de passe du compte `Administrateur` dans un gestionnaire de mots de passe.
