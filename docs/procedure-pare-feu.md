# Procédure : modifier une règle du pare-feu

> Personne ne retient une configuration de pare-feu par cœur : on suit une procédure.
> Celle-ci a servi le 11 oct. 2026 pour remplacer « Serveurs → tout » par des règles précises.

## Avant

1. **Écrire le besoin** dans la [matrice des flux](matrice-des-flux.md) : source, destination,
   port, raison. Pas de raison = pas de règle.
2. **Sauvegarder la configuration** : Diagnostics → Backup & Restore → Download configuration
   as XML. Fichier daté, rangé hors de Git (il contient des données sensibles).
3. **Photographier l'état actuel** des règles de l'interface concernée.

## Pendant

4. **Créer des alias** pour ce qui se répète (`PORTS_WEB`, `RESEAUX_PRIVES`), avec une description.
5. **Ajouter les nouvelles règles**, chacune avec une description claire. Ordre : les blocages
   d'abord, les autorisations précises ensuite. **La première règle qui correspond gagne.**
6. **Désactiver** l'ancienne règle trop large au lieu de la supprimer : c'est le retour arrière
   en un clic.
7. **Appliquer** (Apply Changes).

## Après

8. **Tester ce qui doit passer** et **ce qui doit être bloqué** (une règle qui laisse tout passer
   « marche » aussi, mais ne protège rien).

   | Test (depuis SRV-AD01) | Attendu |
   | --- | --- |
   | `Resolve-DnsName google.fr` | réponse |
   | `Test-NetConnection www.microsoft.com -Port 443` | True |
   | `Test-NetConnection 1.1.1.1 -Port 53` | False (DNS direct interdit) |
   | `Test-NetConnection 192.168.1.254 -Port 80` | False (réseau privé) |

9. **Lire les journaux** (Status → System Logs → Firewall, filtre sur la source) : les blocages
   attendus doivent y être, et aucun blocage inattendu.
10. **Vérifier les compteurs** (colonne States) : les nouvelles règles doivent servir.
11. Après quelques jours sans blocage gênant : **supprimer** l'ancienne règle désactivée.
12. **Nouvelle sauvegarde** de la configuration, et mise à jour de la documentation.

## En production, en plus

- Demande de changement validée par le responsable, et utilisateurs prévenus.
- Fenêtre de maintenance pour tout ce qui coupe le réseau (redémarrage du pare-feu…).
- Réglages faits à deux quand c'est possible (un qui fait, un qui relit).
