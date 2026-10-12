<#
.SYNOPSIS
    Crée les salariés d'AEROTRANS dans l'Active Directory à partir d'un fichier CSV.

.DESCRIPTION
    Pour chaque ligne du CSV (Prenom;Nom;Service;Fonction) :
      - fabrique l'identifiant prenom.nom (minuscules, sans accents, 20 caractères max) ;
      - crée le compte dans l'OU AEROTRANS/Utilisateurs/<Service> ;
      - l'ajoute au groupe GG_<Service> (OU AEROTRANS/Groupes) ;
      - mot de passe provisoire commun, à changer obligatoirement à la 1re connexion.
    Un compte qui existe déjà est ignoré (le script peut être relancé sans risque).

.PARAMETER CsvPath
    Chemin du fichier CSV (séparateur ; encodage UTF-8).

.PARAMETER Simulation
    Affiche ce qui serait fait, sans rien créer (-WhatIf). À lancer en premier.

.EXAMPLE
    .\Import-AerotransUsers.ps1 -CsvPath D:\aerotrans-salaries.csv -Simulation
    .\Import-AerotransUsers.ps1 -CsvPath D:\aerotrans-salaries.csv

.NOTES
    Lab PME - brique 03. En production : un mot de passe provisoire UNIQUE par salarié,
    remis en main propre, plutôt qu'un mot de passe commun.
    v2 (11 oct. 2026) : un compte créé à moitié est supprimé, et le script s'arrête
    dès qu'un mot de passe est refusé (constaté en lab : mot de passe vide -> 24 comptes
    désactivés sans groupe, puis ignorés à la relance car « déjà présents »).
#>
param(
    [Parameter(Mandatory)] [string] $CsvPath,
    [switch] $Simulation
)

Import-Module ActiveDirectory

$domaine = 'lab.home.arpa'
$base    = 'OU=AEROTRANS,DC=lab,DC=home,DC=arpa'

function ConvertTo-Identifiant([string] $texte) {
    # Enlève les accents (é -> e), les espaces, et passe en minuscules
    $decompose = $texte.Normalize([Text.NormalizationForm]::FormD)
    $sansAccents = -join ($decompose.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark })
    return ($sansAccents -replace '\s', '').ToLower()
}

$salaries = Import-Csv -Path $CsvPath -Delimiter ';' -Encoding UTF8

if (-not $Simulation) {
    $mdp = Read-Host 'Mot de passe provisoire (commun, change a la 1re connexion)' -AsSecureString
}

$crees = 0; $ignores = 0; $erreurs = 0

foreach ($s in $salaries) {
    $login = '{0}.{1}' -f (ConvertTo-Identifiant $s.Prenom), (ConvertTo-Identifiant $s.Nom)
    $ou    = "OU=$($s.Service),OU=Utilisateurs,$base"
    $groupe = "GG_$($s.Service)"

    if ($login.Length -gt 20) {
        Write-Warning "$login : plus de 20 caracteres, ligne ignoree"; $erreurs++; continue
    }
    if (Get-ADUser -Filter "SamAccountName -eq '$login'") {
        Write-Host "[deja present] $login" -ForegroundColor Yellow; $ignores++; continue
    }

    $params = @{
        Name                  = "$($s.Prenom) $($s.Nom)"
        GivenName             = $s.Prenom
        Surname               = $s.Nom
        DisplayName           = "$($s.Prenom) $($s.Nom)"
        SamAccountName        = $login
        UserPrincipalName     = "$login@$domaine"
        Title                 = $s.Fonction
        Department            = $s.Service
        Company               = 'AEROTRANS'
        Path                  = $ou
        Enabled               = $true
        ChangePasswordAtLogon = $true
    }

    try {
        if ($Simulation) {
            New-ADUser @params -WhatIf
            Write-Host "  -> serait ajoute a $groupe" -ForegroundColor DarkGray
        } else {
            New-ADUser @params -AccountPassword $mdp -ErrorAction Stop
            Add-ADGroupMember -Identity $groupe -Members $login -ErrorAction Stop
            Write-Host "[cree] $login -> $ou, groupe $groupe" -ForegroundColor Green
        }
        $crees++
    } catch {
        $message = $_.Exception.Message
        Write-Warning "$login : $message"; $erreurs++
        # Si le compte a été créé à moitié (ex. mot de passe refusé), on le supprime
        # pour ne pas laisser un compte désactivé, sans mot de passe et sans groupe.
        if (-not $Simulation -and (Get-ADUser -Filter "SamAccountName -eq '$login'")) {
            Remove-ADUser -Identity $login -Confirm:$false
            Write-Warning "$login : compte incomplet supprime"
        }
        # Un mot de passe refusé le sera pour tout le monde : inutile de continuer.
        if ($_.Exception -is [Microsoft.ActiveDirectory.Management.ADPasswordComplexityException] -or
            $message -match 'mot de passe|password') {
            Write-Host 'Arret : le mot de passe provisoire ne respecte pas la strategie du domaine. Relancez avec un mot de passe conforme.' -ForegroundColor Red
            break
        }
    }
}

Write-Host ''
Write-Host "Bilan : $crees a creer/crees, $ignores deja presents, $erreurs erreurs" -ForegroundColor Cyan
if ($Simulation) { Write-Host 'Mode simulation : rien n a ete cree.' -ForegroundColor Cyan }
