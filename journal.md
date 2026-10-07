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
| 6 oct. 2026 | Début de la brique 01 : pfSense. Installateur Netgate récupéré (boutique Netgate, 0 €), décompressé, vérifié | netgate-installer-v1.2-RELEASE-amd64.iso, 1,01 Go, SHA256 f55dc289…aeae96, contrôle à l'upload Proxmox : checksum verified |
| 6 oct. 2026 | Pont vmbr1 créé sur nic1 : sans IP, « VLAN aware » | Futur trunk 802.1Q vers le switch Cisco. Proxmox n'a pas d'adresse côté entreprise |
| 6 oct. 2026 | VM 100 fw01 créée | q35, SeaBIOS, 2 cœurs host, 2 Gio sans ballooning, disque SCSI 16 Gio (discard, SSD, IO thread), net0 virtio vmbr0 (WAN), net1 virtio vmbr1 sans tag (LAN trunk), démarrage auto ordre 1 + 30 s |
| 6 oct. 2026 | Dépannage installateur : « Cannot set WAN interface IP address » | Cause racine : LAN par défaut 192.168.1.1/24 dans le même réseau que le WAN 192.168.1.211/24. Conflit d'IP écarté (ping + ARP). Correction : configurer le LAN avant le WAN |
| 6 oct. 2026 | pfSense CE 2.9.0 installé | ZFS stripe, GPT. WAN vtnet0 192.168.1.211/24, passerelle et DNS 192.168.1.254. LAN vtnet1.99 (VLAN 99 Administration) 10.10.99.254/24, DHCP .100–.199. Bouton Reboot de l'installateur bloqué : réinitialisation depuis Proxmox (installation déjà terminée) |
| 6 oct. 2026 | Recette réseau depuis la console | Box OK (0,7 ms), Internet 1.1.1.1 OK (4,8 ms), DNS OK (drill), ping par nom OK en IPv4. Échec du ping par nom sans -4 : réponse IPv6 alors que pfSense n'a pas d'IPv6 |
| 7 oct. 2026 | Quiz de début de session sur pfSense (5/5). Nouvelle méthode : Paulo propose les valeurs avant correction | — |
| 7 oct. 2026 | Accès à l'interface web depuis le PC admin (côté WAN) | Filtrage coupé temporairement (pfctl -d) depuis la console. Règle WAN temporaire : Pass TCP 192.168.1.98 → This Firewall:443, journalisée, à supprimer après mise en place du switch (accès via VLAN 99) |
| 7 oct. 2026 | Assistant de configuration | Hostname fw01, domaine lab.home.arpa, DNS 192.168.1.254 + 1.1.1.1, fuseau Europe/Paris, passerelle WAN 192.168.1.254, blocage RFC1918 décoché sur le WAN (WAN dans un réseau privé), bogons conservés. Mot de passe admin par défaut changé |
| 7 oct. 2026 | Vérification du filtrage | pfctl -s info : Status Enabled |
| 7 oct. 2026 | VLAN créés et assignés sur vtnet1 | 10 SERVEURS 10.10.10.254/24, 20 POSTES 10.10.20.254/24, 30 WIFI_SALARIES 10.10.30.254/24, 40 WIFI_INVITES 10.10.40.254/24, 99 ADMINISTRATION 10.10.99.254/24. Erreur détectée en relecture : masque /32 sur POSTES et WIFI_SALARIES, corrigé en /24 et vérifié (ifconfig : netmask 0xffffff00) |
| 7 oct. 2026 | Décision : DHCP des postes assuré par Windows Server (brique 03) via relais DHCP pfSense | Le DHCP ne traverse pas les routeurs (broadcast). Équivalent Cisco : ip helper-address |
| 7 oct. 2026 | VM de test 900 test-poste créée | Alpine 3.24.2 virt (live, sans disque), 1 cœur, 512 Mo, vmbr1 tag 20. Oubli du tag repéré au récapitulatif et corrigé. Carte eth0 éteinte au démarrage : ip link set eth0 up |
| 7 oct. 2026 | DHCP temporaire sur pfSense pour le VLAN 20 | Plage 10.10.20.100 à .199 (.1 à .99 réservées aux adresses fixes), bail 2 h. Test : sans serveur, échec (discover sans réponse) ; avec serveur, bail 10.10.20.100 obtenu (DORA). À remplacer par Windows Server + relais (brique 03) |
| 7 oct. 2026 | Règles du VLAN POSTES | 1) Block POSTES → LAN subnets (journalisé) ; 2) Block TCP POSTES → pfSense:443 (journalisé) ; 3) Pass POSTES → any. Erreur évitée : 1re règle créée sur l'interface LAN au lieu de POSTES |
| 7 oct. 2026 | Recette de la segmentation depuis test-poste | Avant règles : 100 % de perte (refus par défaut). Après : ping 1.1.1.1 OK, ping google.com OK (DNS), ping 10.10.99.254 bloqué, nc 10.10.20.254 443 sans réponse (bloqué) |
