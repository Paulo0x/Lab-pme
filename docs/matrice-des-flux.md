# Matrice des flux

> **Qui parle à qui, sur quel port, et pourquoi.** C'est le document qu'un auditeur ou un
> nouvel admin demande en premier. Chaque règle du pare-feu doit y figurer, avec sa raison.
> Tout flux absent de ce tableau est **refusé** (refus par défaut de pfSense) et journalisé.

Mise à jour : 12 oct. 2026 (fin de la brique 03).

## 1. Flux en place

### VLAN 10 · Serveurs (interface SERVEURS)

| # | Action | Source | Destination | Protocole / port | Pourquoi | Journal |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Bloquer | Serveurs | Réseau d'administration (VLAN 99) | tout | Un serveur compromis ne doit jamais atteindre les équipements d'administration | oui |
| 2 | Bloquer | Serveurs | pfSense (This Firewall) | TCP 443 | Pas d'accès à l'interface web du pare-feu depuis un serveur | oui |
| 3 | Autoriser | Serveurs | pfSense (SERVEURS address) | TCP/UDP 53 | DNS : le redirecteur du contrôleur de domaine interroge le résolveur de pfSense. TCP pour les réponses trop grosses pour UDP | non |
| 4 | Autoriser | Serveurs | pfSense (SERVEURS address) | UDP 123 | NTP : le DC prend l'heure sur pfSense (Kerberos refuse plus de 5 min d'écart) | non |
| 5 | Autoriser | Serveurs | **Internet uniquement** (`! RESEAUX_PRIVES`) | TCP 80, 443 (`PORTS_WEB`) | Mises à jour Windows et vérification des certificats (CRL/OCSP). L'inversion interdit d'utiliser ces ports vers les autres VLAN | non |
| 6 | Autoriser | Serveurs | tout | ICMP echo request | Ping pour le dépannage (compromis PME, ports fermés malgré tout) | non |
| — | **Refuser** | tout le reste | | | Refus par défaut | oui |

Alias utilisés : `PORTS_WEB` = 80, 443 ; `RESEAUX_PRIVES` = 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 (RFC 1918).

### VLAN 20 · Postes (interface POSTES)

| # | Action | Source | Destination | Protocole / port | Pourquoi | Journal |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Bloquer | Postes | Réseau d'administration (VLAN 99) | tout | Un poste ne touche jamais aux équipements | oui |
| 2 | Bloquer | Postes | pfSense (This Firewall) | TCP 443 | Pas d'accès à l'interface du pare-feu par la passerelle | oui |
| 3 | Autoriser | Postes | tout | tout | **Provisoire** : à remplacer par des règles précises à la brique 04 (voir § 2) | non |
| auto | Autoriser | Postes (0.0.0.0:68) | 255.255.255.255:67 | UDP | Règle **automatique** créée par pfSense quand le relais DHCP est activé | — |

### WAN (réseau de la box)

| # | Action | Source | Destination | Port | Pourquoi |
| --- | --- | --- | --- | --- | --- |
| 1 | Autoriser | PC d'administration 192.168.1.98 | pfSense WAN | TCP 443 | **Temporaire** : accès à l'interface web tant que le VLAN 99 n'est pas joignable (switch, brique 02). À supprimer ensuite |

### Flux internes au pare-feu

| Service | Sens | Détail |
| --- | --- | --- |
| Relais DHCP | Postes → pfSense → SRV-AD01 (10.10.10.10:67) | La demande (broadcast) ne traverse pas les VLAN : le relais la transmet au serveur |
| NTP | pfSense → Internet (pool `2.pfsense.pool.ntp.org`) | Seule machine qui sort vers Internet pour l'heure |
| DNS | pfSense → Internet | Résolveur de pfSense, utilisé par le redirecteur du DC |

## 2. Flux à ouvrir plus tard

| Brique | Source | Destination | Ports | Pourquoi |
| --- | --- | --- | --- | --- |
| 02 | Administration (VLAN 99) | SRV-AD01 | TCP 3389 | Bureau à distance des admins (copier-coller, confort) |
| 02 | Administration (VLAN 99) | pfSense, Proxmox | TCP 443, 8006 | Administration par le bon réseau, puis suppression de la règle WAN temporaire |
| 04 | Postes | SRV-AD01 | DNS 53, Kerberos 88, NTP 123, RPC 135, LDAP 389, SMB 445, Kerberos mdp 464, LDAPS 636, catalogue global 3268-3269, RPC dynamiques 49152-65535 | Ports nécessaires à un poste membre du domaine ; remplaceront la règle 3 « Postes → tout » |
| 04 | Postes | Internet | TCP 80, 443 | Navigation et mises à jour |
| Wi-Fi | Invités (VLAN 40) | Internet uniquement | TCP 80, 443, DNS | Aucun accès au réseau interne |

## 3. Règles de tenue

- Toute nouvelle règle est **ajoutée ici avant** d'être créée dans pfSense, avec sa raison.
- Une règle qui ne sert plus (compteurs à zéro depuis longtemps) est désactivée, puis supprimée.
- Procédure de modification : [procedure-pare-feu.md](procedure-pare-feu.md).
