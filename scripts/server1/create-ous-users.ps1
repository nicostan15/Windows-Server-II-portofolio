Import-Module ActiveDirectory

$DomainDN = (Get-ADDomain).DistinguishedName

# ---------------------------------------------------------------------------
# 1. OU-structuur (minstens 3 OU's vereist, hier 4 top-level OU's voorzien)
# ---------------------------------------------------------------------------
$OUs = @(
    "Beheer",       # OU voor Domain Admin-accounts
    "Medewerkers",  # OU voor gewone Domain User-accounts
    "Servers",      # OU voor computerobjecten van server2/server3 (na domain join)
    "Clients"       # OU voor de computerobjecten van de Windows 11 client
)

foreach ($OuName in $OUs) {
    $OuPath = "OU=$OuName,$DomainDN"
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$OuName'" -SearchBase $DomainDN -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $OuName -Path $DomainDN -ProtectedFromAccidentalDeletion $true
        Write-Host "OU aangemaakt: $OuPath" -ForegroundColor Green
    } else {
        Write-Host "OU bestaat reeds, overslaan: $OuPath" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 2. Gebruikers (minstens 4 vereist: 2x Domain Admin, 2x Domain User)
# ---------------------------------------------------------------------------
$Users = @(
    @{ SamAccountName = "j.doe.adm";  GivenName = "John";  Surname = "Doe";    Role = "DomainAdmin"; OU = "Beheer" }
    @{ SamAccountName = "a.smit.adm"; GivenName = "Anna";  Surname = "Smit";   Role = "DomainAdmin"; OU = "Beheer" }
    @{ SamAccountName = "p.jansen";   GivenName = "Piet";  Surname = "Jansen"; Role = "DomainUser";  OU = "Medewerkers" }
    @{ SamAccountName = "m.peeters";  GivenName = "Marie"; Surname = "Peeters";Role = "DomainUser";  OU = "Medewerkers" }
)

$DefaultPassword = ConvertTo-SecureString "W@chtwoord2026!" -AsPlainText -Force
$DomainSuffix = (Get-ADDomain).DNSRoot

foreach ($U in $Users) {
    $UpnName = "$($U.SamAccountName)@$DomainSuffix"
    $TargetOU = "OU=$($U.OU),$DomainDN"

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($U.SamAccountName)'" -ErrorAction SilentlyContinue)) {
        New-ADUser `
            -Name "$($U.GivenName) $($U.Surname)" `
            -GivenName $U.GivenName `
            -Surname $U.Surname `
            -SamAccountName $U.SamAccountName `
            -UserPrincipalName $UpnName `
            -Path $TargetOU `
            -AccountPassword $DefaultPassword `
            -ChangePasswordAtLogon $true `
            -Enabled $true

        Write-Host "Gebruiker aangemaakt: $($U.SamAccountName) in $TargetOU" -ForegroundColor Green
    } else {
        Write-Host "Gebruiker bestaat reeds, overslaan: $($U.SamAccountName)" -ForegroundColor Yellow
    }

    if ($U.Role -eq "DomainAdmin") {
        if (-not (Get-ADGroupMember -Identity "Domain Admins" | Where-Object { $_.SamAccountName -eq $U.SamAccountName })) {
            Add-ADGroupMember -Identity "Domain Admins" -Members $U.SamAccountName
            Write-Host "$($U.SamAccountName) toegevoegd aan Domain Admins" -ForegroundColor Cyan
        }
    }
}

Write-Host "`nOU- en gebruikersconfiguratie voltooid." -ForegroundColor Green