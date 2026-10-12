# Plan d'adressage

Mise à jour : 12 oct. 2026 (fin de la brique 03).

## Réseau de la box (côté « opérateur »)

| Élément | Valeur |
| --- | --- |
| Réseau | 192.168.1.0/24 |
| Passerelle et DNS (box) | 192.168.1.254 |
| Plage DHCP de la box | 192.168.1.2 à 192.168.1.200 |
| Adresses fixes disponibles | 192.168.1.201 à 192.168.1.253 |

| Adresse | Équipement |
| --- | --- |
| 192.168.1.210 | pve01 (administration Proxmox) |
| 192.168.1.211 | pfSense, interface WAN |
| 192.168.1.212 – .220 | Réserve du lab |

## Réseau de l'entreprise (derrière pfSense)

Règle commune : le 3e nombre est le numéro du VLAN, pfSense est la passerelle en `.254`,
les adresses **.1 à .99 sont fixes** (serveurs, imprimantes, bornes), **.100 à .199 sont
distribuées par DHCP**.

| VLAN | Rôle | Réseau | Passerelle | DHCP | Serveur DHCP |
| --- | --- | --- | --- | --- | --- |
| 10 | Serveurs | 10.10.10.0/24 | 10.10.10.254 | aucun (adresses fixes) | — |
| 20 | Postes de travail | 10.10.20.0/24 | 10.10.20.254 | .100 – .199, bail 8 j | SRV-AD01 via le relais pfSense |
| 30 | Wi-Fi salariés | 10.10.30.0/24 | 10.10.30.254 | à créer (brique Wi-Fi) | SRV-AD01 via relais |
| 40 | Wi-Fi invités | 10.10.40.0/24 | 10.10.40.254 | à créer, bail court | à décider |
| 99 | Administration | 10.10.99.0/24 | 10.10.99.254 | .100 – .199 | pfSense |

Options DHCP du VLAN 20 : 003 routeur `10.10.20.254`, 006 DNS `10.10.10.10` (le contrôleur
de domaine, jamais pfSense : sinon les postes ne trouvent pas le domaine), 015 domaine `lab.home.arpa`.

## Adresses fixes attribuées

| Adresse | Nom | Rôle | VM |
| --- | --- | --- | --- |
| 10.10.10.10 | SRV-AD01 | Contrôleur de domaine, DNS, DHCP | 200 |
| 10.10.10.11 | (réservée) | SRV-AD02, 2e contrôleur de domaine | — |
| 10.10.10.20 | (réservée) | SRV-GLPI (brique 05) | — |
| 10.10.10.21 | (réservée) | SRV-ZBX01, Zabbix (brique 06) | — |
| 10.10.10.22 | (réservée) | SRV-BKP01, Veeam (brique 07) | — |
| 10.10.10.254 | fw01 | pfSense, passerelle VLAN 10 | 100 |
| 10.10.20.254 | fw01 | pfSense, passerelle VLAN 20 | 100 |
| 10.10.30.254 | fw01 | pfSense, passerelle VLAN 30 | 100 |
| 10.10.40.254 | fw01 | pfSense, passerelle VLAN 40 | 100 |
| 10.10.99.254 | fw01 | pfSense, passerelle VLAN 99 | 100 |

VM de recette : `test-poste` (VM 900, Alpine), adresse DHCP dans le VLAN 20.

## DNS

| Zone | Type | Rôle |
| --- | --- | --- |
| `lab.home.arpa` | directe, intégrée à l'AD | nom → IP |
| `_msdcs.lab.home.arpa` | directe, intégrée à l'AD | localisation des contrôleurs de domaine |
| `10.10.10.in-addr.arpa` … `99.10.10.in-addr.arpa` | inversées (5), intégrées à l'AD | IP → nom |

Redirecteur : `10.10.10.254` (résolveur de pfSense). Mises à jour dynamiques : sécurisées uniquement.

Nommage des machines et des comptes : [conventions.md](conventions.md).
