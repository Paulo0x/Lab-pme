# Lab PME : le système d'information d'une PME, construit de zéro

Je suis en reconversion vers l'administration systèmes et réseaux (titre RNCP 6
*Administrateur d'Infrastructures Sécurisées*). Ce dépôt documente la construction
complète de l'informatique d'une **PME fictive de 25 salariés**, sur un mini PC,
comme le ferait un technicien d'ESN chez un client : choix justifiés, installation,
sécurisation, tests de validation et procédures.

**Chaque brique a son tuto complet**, avec captures, dépannage réel et questions d'entretien.

## Avancement

| # | Brique | Technologies | Statut |
| --- | --- | --- | --- |
| 00 | [Hyperviseur](00-proxmox/) | Proxmox VE 9, LVM-thin, RBAC, 2FA TOTP | ✅ Terminé |
| 01 | [Pare-feu et VLAN](01-pfsense/) | pfSense CE 2.9, 5 VLAN, DHCP, règles, recette | ✅ Terminé |
| 02 | Commutation | Cisco Catalyst 2960C (VLAN, trunk, SSH) | 🔜 En cours |
| 03 | Annuaire | Windows Server 2025 : AD, DNS, DHCP | ⏳ À faire |
| 04 | Postes de travail | Windows 11, GPO, LAPS | ⏳ À faire |
| 05 | Support et parc | GLPI | ⏳ À faire |
| 06 | Supervision | Zabbix | ⏳ À faire |
| 07 | Sauvegarde | Veeam | ⏳ À faire |
| 08 | Cloud Microsoft | Microsoft 365, Intune, Entra ID | ⏳ À faire |
| 09 | Automatisation | PowerShell | ⏳ À faire |
| 10 | Automatisation et IA | n8n + Ollama (alertes Zabbix → tickets GLPI) | ⏳ À faire |
| 11 | Sécurité | Wazuh | ⏳ À faire |

**Briques bonus**, ce qu'on croise partout en PME :

| # | Brique | Technologies | Statut |
| --- | --- | --- | --- |
| 12 | Serveur de fichiers | Partages, droits NTFS, quotas, DFS | ⏳ À faire |
| 13 | Impression | Serveur d'impression, déploiement par GPO | ⏳ À faire |
| 14 | Déploiement de postes | Image maître, WDS/MDT ou Autopilot | ⏳ À faire |
| 15 | Téléphonie IP | 3CX ou FreePBX, VLAN voix, QoS, téléphone PoE | ⏳ À faire |
| 16 | Pare-feu Fortinet | FortiGate VM, comparé à pfSense | ⏳ À faire |
| 17 | Contrôle d'accès réseau | 802.1X, NPS (RADIUS), switch Cisco | ⏳ À faire |
| 18 | VPN nomades | WireGuard / OpenVPN sur pfSense | ⏳ À faire |
| 19 | Certificats | PKI Windows (AD CS) | ⏳ À faire |
| 20 | Mises à jour | WSUS | ⏳ À faire |
| 21 | Prise en main à distance | RustDesk auto-hébergé | ⏳ À faire |
| 22 | Mots de passe d'entreprise | Vaultwarden | ⏳ À faire |
| 23 | Onduleur | Arrêt propre sur coupure (NUT) | ⏳ À faire |
| 24 | Linux et automatisation | Debian, SSH, Ansible, Docker | ⏳ À faire |

## Architecture cible

```
Internet
   |
 [Box] 192.168.1.0/24
   |
   +-- Carte 1 du mini PC : administration Proxmox (192.168.1.210)
   |                        + côté WAN de pfSense
 [Mini PC Proxmox] -- pfSense : pare-feu, routage entre VLAN
   |
   +-- Carte 2 : trunk 802.1Q vers le switch Cisco
                 -> postes physiques, borne Wi-Fi
```

| VLAN | Rôle | Réseau |
| --- | --- | --- |
| 10 | Serveurs | 10.10.10.0/24 |
| 20 | Postes de travail | 10.10.20.0/24 |
| 30 | Wi-Fi salariés | 10.10.30.0/24 |
| 40 | Wi-Fi invités (isolé) | 10.10.40.0/24 |
| 99 | Administration (switch, borne) | 10.10.99.0/24 |

Détails : [plan d'adressage](docs/plan-adressage.md).

## Matériel

| Élément | Rôle |
| --- | --- |
| Mini PC Minisforum NAB5 (Core i5-12450H, 32 Go, NVMe 512 Go, 2 × 2,5 Gb/s) | Hyperviseur |
| Cisco Catalyst WS-C2960C-8PC-L (PoE) | Switch de l'entreprise |
| 2 portables | Postes utilisateurs physiques |

## Méthode

Chaque tuto suit la même structure : besoin du client, comparatif des technologies
et choix retenu, installation, configuration avec les raisons de chaque réglage,
recette, cas concrets d'entreprise, dépannage, questions d'entretien.

Le [journal du lab](journal.md) trace chaque étape : quoi, quand, pourquoi.

## Contact

Paulo Rosa · [LinkedIn](https://www.linkedin.com/in/paulo-ais/) · En recherche d'un poste
de technicien systèmes, réseaux ou exploitation en Île-de-France.
