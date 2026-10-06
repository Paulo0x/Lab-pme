# Journal du lab

| Date | Ce qui a été fait | Détails (noms, IP, versions) |
| --- | --- | --- |
| 3 oct. 2026 | Décision : formatage complet et reconstruction du lab autour du SI d'une PME | Mini PC Minisforum NAB5, i5-12450H, 32 Go DDR4, 2 ports 2,5 Gb/s |
| 4 oct. 2026 | Architecture cible décidée : pfSense + switch niveau 2, 5 VLAN | VLAN 10, 20, 30, 40, 99 en 10.10.X.0/24 |
| 4 oct. 2026 | Switch acheté (Leboncoin) | Cisco WS-C2960C-8PC-L, 40 € |
| 6 oct. 2026 | Début de la brique 00 : Proxmox | — |
| 6 oct. 2026 | Relevé réseau et choix de l'IP fixe de Proxmox | Box Freebox, réseau 192.168.1.0/24, passerelle et DNS 192.168.1.254, DHCP de .2 à .200 ; pve01 = 192.168.1.210 (ping : libre) ; pfSense WAN = 192.168.1.211 ; réserve .212–.220 |
| 6 oct. 2026 | ISO Proxmox VE 9.2-1 téléchargée et vérifiée | proxmox-ve_9.2-1.iso, 1,71 Go, SHA256 4e88fe41…f2c6c conforme |
| 6 oct. 2026 | Clé USB d'installation Proxmox créée | balenaEtcher, flash et vérification réussis |
| 6 oct. 2026 | BIOS : E-cores activés, VT-d vérifié, USB en premier au démarrage | VT-x masqué mais actif (aucune alerte KVM) |
| 6 oct. 2026 | Installation Proxmox : 2 échecs (retour menu, puis plantage vers 25 %), réussite après retour des E-cores à 0 (installateur graphique conservé : E-cores = cause confirmée) | pve01.lab.home.arpa, 192.168.1.210/24, ext4, nvme0n1 Kingston 512 Go, nic0 MAC 58:47:ca:xx:xx:xx (masquée). E-cores à retester sous charge |
| 6 oct. 2026 | Première connexion web, dépôts Enterprise désactivés, No-Subscription ajouté, mise à jour complète | Proxmox VE 9.2.2 → paquets à jour, nouveau noyau 7.0.14-20-pve (redémarrage requis) |
| 6 oct. 2026 | Redémarrage, NVMe remis en premier dans le BIOS, vérification du résumé | Noyau 7.0.14-20-pve, pve-manager 9.2.21, 8 threads, 31,09 Gio RAM, root 93,93 Gio, swap 8 Gio, EFI |
| 6 oct. 2026 | Sécurisation des accès : groupe admin-infra (Administrator sur /), compte paulo@pve, 2FA TOTP + codes de récupération sur paulo@pve et root@pam | Oubli d'ajout au groupe détecté au test et corrigé. **Brique 00 terminée** |
