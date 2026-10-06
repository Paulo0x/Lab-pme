# Plan d'adressage

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

| VLAN | Rôle | Réseau | Passerelle (pfSense) |
| --- | --- | --- | --- |
| 10 | Serveurs | 10.10.10.0/24 | 10.10.10.254 |
| 20 | Postes de travail | 10.10.20.0/24 | 10.10.20.254 |
| 30 | Wi-Fi salariés | 10.10.30.0/24 | 10.10.30.254 |
| 40 | Wi-Fi invités | 10.10.40.0/24 | 10.10.40.254 |
| 99 | Administration | 10.10.99.0/24 | 10.10.99.254 |

## Conventions de nommage

| Type | Format | Exemple |
| --- | --- | --- |
| Hyperviseur | pveNN | pve01 |
| Serveur | SRV-RÔLENN | SRV-AD01, SRV-GLPI |
| Poste | PC-USERNN | PC-USER01 |
| Domaine | lab.home.arpa | pve01.lab.home.arpa (RFC 8375, réservé aux réseaux privés) |
