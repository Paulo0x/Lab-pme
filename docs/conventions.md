# Conventions AEROTRANS

> Règles fixées **avant** de créer quoi que ce soit dans l'annuaire, pour que n'importe quel
> admin qui arrive après s'y retrouve. On copie les noms depuis ce document, on ne les tape
> pas de tête.

## 1. L'entreprise fictive

**AEROTRANS** : PME d'assistance aéroportuaire, 25 salariés.

| Service (OU) | Effectif | Rôle |
| --- | --- | --- |
| Direction | 2 | Gérant, directrice adjointe |
| Comptabilite | 2 | Factures, paie, banque |
| RH | 1 | Contrats, plannings, formations |
| Commercial | 3 | Compagnies aériennes, devis |
| Operations | 14 | Chef d'escale, chefs d'équipe, agents de piste et de trafic |
| Accueil | 2 | Standard, accueil des équipages |
| Informatique | 1 | Administrateur systèmes et réseaux |

## 2. Règles générales

- **Pas d'accent ni d'espace** dans les noms techniques (OU, groupes, comptes, GPO) :
  ils cassent souvent les scripts. Les accents restent permis dans les noms affichés
  (« Hélène Dubois »).
- **Toujours une description** (OU, groupe, GPO, règle de pare-feu, alias).
- **Protection contre la suppression accidentelle** sur toutes les OU.

## 3. Arborescence des OU

```
lab.home.arpa
└── AEROTRANS                 OU racine : nos objets, séparés de ceux de Windows
    ├── Utilisateurs          (redirusr : comptes créés sans OU précisée)
    │   ├── Direction
    │   ├── Comptabilite
    │   ├── RH
    │   ├── Commercial
    │   ├── Operations
    │   ├── Accueil
    │   └── Informatique
    ├── Ordinateurs           (redircmp : PC qui rejoignent le domaine)
    │   ├── Postes-fixes
    │   └── Portables         règles propres : BitLocker, VPN
    ├── Serveurs
    ├── Groupes
    ├── Admins                comptes adm.*
    ├── Comptes-service       comptes utilisés par des logiciels (GLPI, Veeam…)
    └── Desactives            comptes des salariés partis, conservés quelques mois
```

Les conteneurs par défaut `Users` et `Computers` ne sont **pas** des OU : on ne peut pas y
lier de GPO. D'où la redirection (`redircmp`, `redirusr`) vers les OU AEROTRANS.

## 4. Nommage

| Objet | Format | Exemple | Remarque |
| --- | --- | --- | --- |
| Compte salarié | `prenom.nom` | `helene.dubois` | minuscules, sans accent, 20 caractères max |
| Homonyme | `prenom.initiale.nom` | `paulo.a.rosa` | initiale du 2e prénom |
| Compte admin | `adm.prenom.nom` | `adm.paulo.rosa` | marqueur en tête : les admins sont regroupés au tri |
| Compte de service | `svc.application` | `svc.glpi` | |
| Groupe global (utilisateurs) | `GG_Service` | `GG_Comptabilite` | contient des comptes |
| Groupe domaine local (droits) | `DL_Ressource_Droit` | `DL_Partage-Compta_RW` | reçoit les permissions (méthode AGDLP) |
| GPO ordinateur | `C_Theme_Objet` | `C_Securite_Verrouillage_Inactivite` | liée à une OU d'ordinateurs |
| GPO utilisateur | `U_Theme_Objet` | `U_Bureau_FondEcran` | liée à une OU d'utilisateurs |
| Stratégie de mot de passe affinée | `PSO-Cible` | `PSO-Admins` | |
| Serveur | `SRV-ROLENN` | `SRV-AD01` | |
| Poste fixe / portable | `PC-NNN` / `PO-NNN` | `PC-001` | |
| Compte local de secours (LAPS) | `secours.local` | `secours.local` | Créé et géré par Windows LAPS sur chaque poste ; l'`Administrateur` intégré reste désactivé |
| GPO de configuration (non sécurité) | `C_Config_Objet` | `C_Config_Alimentation` | |

**AGDLP** : les **A**ccounts vont dans des groupes **G**lobaux, qui vont dans des groupes
**D**omaine **L**ocal, qui reçoivent les **P**ermissions. On ne donne jamais un droit
directement à un compte.

## 5. Comptes et mots de passe

| Règle | Salariés | Admins (PSO-Admins) |
| --- | --- | --- |
| Longueur minimale | 12 | 15 |
| Complexité | oui | oui |
| Historique | 24 | 24 |
| Durée de vie | 1 à 365 jours | 1 à 180 jours |
| Verrouillage | 10 essais, 15 min | 10 essais, 15 min |

- Un salarié reçoit un mot de passe provisoire **unique**, remis en main propre, à changer
  à la première connexion.
- Chaque admin a **deux comptes** : `prenom.nom` pour le quotidien (mails, Internet), sans
  droit d'admin ; `adm.prenom.nom` uniquement pour administrer.
- Comptes admin : groupe **Protected Users** + option « compte sensible, ne peut pas être
  délégué ». Le compte `Administrateur` intégré est un compte **de secours**, hors Protected Users.
- Départ d'un salarié : compte **désactivé** et déplacé dans `Desactives`, supprimé après
  quelques mois.

## 6. Postes de travail (brique 04)

- Comptes locaux : tous désactivés, sauf `secours.local`, géré par LAPS (20 caractères, 30 jours, chiffré, lisible par les Admins du domaine).
- Joindre un PC au domaine : membres de `GG_Informatique` (via `DL_OU-Ordinateurs_JoindrePC`), sans être admin du domaine. `ms-DS-MachineAccountQuota` = 0.
- Groupe **Administrateurs du schéma** : vide en temps normal (seul `Administrateur`), rempli seulement le temps d'une opération.
