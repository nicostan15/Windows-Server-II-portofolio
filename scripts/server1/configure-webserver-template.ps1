#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Geeft Administrator en SERVER3$ Read- en Enroll-rechten
    op de bestaande WebServer-template.

.DESCRIPTION
    Gebruikt expliciete domeincredentials.
    Wijzigt uitsluitend de DACL.
    Behoudt bestaande rechten en de bestaande eigenaar.
#>

param(
    [string]$DomainAdminUser = "WS26-JD\Administrator",

    [Parameter(Mandatory = $true)]
    [string]$DomainAdminPassword
)

$ErrorActionPreference = "Stop"

if ($env:COMPUTERNAME -ine "server1") {
    throw "Dit script is bedoeld voor server1."
}

Import-Module ActiveDirectory

$SecurePassword = ConvertTo-SecureString `
    -String $DomainAdminPassword `
    -AsPlainText `
    -Force

$Credential = [System.Management.Automation.PSCredential]::new(
    $DomainAdminUser,
    $SecurePassword
)

$DirectoryServer = "server1.WS26-JD.hogent"

$ADParameters = @{
    Server      = $DirectoryServer
    Credential  = $Credential
    ErrorAction = "Stop"
}

$Domain = Get-ADDomain @ADParameters

if ($Domain.DNSRoot -ine "WS26-JD.hogent") {
    throw "Onverwacht domein: $($Domain.DNSRoot)"
}

$ConfigurationDN = (
    Get-ADRootDSE @ADParameters
).configurationNamingContext

$TemplateDN =
    "CN=WebServer,CN=Certificate Templates," +
    "CN=Public Key Services,CN=Services,$ConfigurationDN"

$Administrator = Get-ADUser `
    -Identity "$($Domain.DomainSID.Value)-500" `
    @ADParameters

$Server3 = Get-ADComputer `
    -Identity "server3" `
    @ADParameters

$Entry = [System.DirectoryServices.DirectoryEntry]::new(
    "LDAP://$DirectoryServer/$TemplateDN",
    $DomainAdminUser,
    $DomainAdminPassword,
    [System.DirectoryServices.AuthenticationTypes]::Secure
)

try {
    # Alleen de DACL lezen en schrijven.
    $Entry.PSBase.Options.SecurityMasks =
        [System.DirectoryServices.SecurityMasks]::Dacl

    $Entry.PSBase.RefreshCache(@("nTSecurityDescriptor"))

    $Acl = $Entry.PSBase.ObjectSecurity

    $EnrollGuid = [guid]"0e10c968-78fb-11d2-90d4-00c04f79dc55"

    foreach ($Account in @($Administrator, $Server3)) {
        $Sid = [System.Security.Principal.SecurityIdentifier]$Account.SID

        $ReadRule =
            [System.DirectoryServices.ActiveDirectoryAccessRule]::new(
                $Sid,
                [System.DirectoryServices.ActiveDirectoryRights]::GenericRead,
                [System.Security.AccessControl.AccessControlType]::Allow
            )

        $EnrollRule =
            [System.DirectoryServices.ActiveDirectoryAccessRule]::new(
                $Sid,
                [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
                [System.Security.AccessControl.AccessControlType]::Allow,
                $EnrollGuid
            )

        $Acl.AddAccessRule($ReadRule)
        $Acl.AddAccessRule($EnrollRule)
    }

    $Entry.PSBase.ObjectSecurity = $Acl

        # Alleen de eerder toegevoegde brede Enroll-regel opruimen.
    # Andere rechten, waaronder GenericRead, blijven behouden.
    $AuthenticatedUsersSid = "S-1-5-11"

    $BroadEnrollRules = @(
        $Acl.GetAccessRules(
            $true,
            $false,
            [System.Security.Principal.SecurityIdentifier]
        ) |
            Where-Object {
                $_.IdentityReference.Value -eq $AuthenticatedUsersSid -and
                $_.AccessControlType -eq
                    [System.Security.AccessControl.AccessControlType]::Allow -and
                $_.ObjectType -eq $EnrollGuid -and
                $_.ActiveDirectoryRights -eq
                    [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight
            }
    )

    foreach ($Rule in $BroadEnrollRules) {
        $Acl.RemoveAccessRuleSpecific($Rule)
    }

    Write-Output (
        "Brede expliciete Enroll-regels verwijderd voor Authenticated Users: {0}." -f
        $BroadEnrollRules.Count
    )

    $Entry.PSBase.CommitChanges()

    # Opnieuw ophalen na het opslaan.
    $Entry.PSBase.RefreshCache(@("nTSecurityDescriptor"))

        # Controleer de expliciete allow-regels die dit script beheert.
    $StoredRules = @(
        $Entry.PSBase.ObjectSecurity.GetAccessRules(
            $true,
            $false,
            [System.Security.Principal.SecurityIdentifier]
        )
    )

        $RemainingBroadEnroll = @(
        $StoredRules |
            Where-Object {
                $_.IdentityReference.Value -eq $AuthenticatedUsersSid -and
                $_.AccessControlType -eq
                    [System.Security.AccessControl.AccessControlType]::Allow -and
                $_.ObjectType -eq $EnrollGuid -and
                (
                    $_.ActiveDirectoryRights -band
                    [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight
                ) -ne 0
            }
    )

    if ($RemainingBroadEnroll.Count -gt 0) {
        throw "Er staat nog een expliciete Enroll-regel voor Authenticated Users. Controleer de ACL handmatig."
    }

    $AuthenticatedUsersRead = @(
        $StoredRules |
            Where-Object {
                $_.IdentityReference.Value -eq $AuthenticatedUsersSid -and
                $_.AccessControlType -eq
                    [System.Security.AccessControl.AccessControlType]::Allow -and
                $_.ObjectType -eq [guid]::Empty -and
                (
                    $_.ActiveDirectoryRights -band
                    [System.DirectoryServices.ActiveDirectoryRights]::GenericRead
                ) -eq
                    [System.DirectoryServices.ActiveDirectoryRights]::GenericRead
            }
    )

    if ($AuthenticatedUsersRead.Count -eq 0) {
        throw "Het verwachte expliciete Read-recht voor Authenticated Users ontbreekt."
    }

    Write-Output "PASS: expliciet Enroll voor Authenticated Users afwezig; Read behouden."

    $ReadMask = [System.DirectoryServices.ActiveDirectoryRights]::GenericRead
    $EnrollMask = [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight

    foreach ($Account in @($Administrator, $Server3)) {
        $SidValue = $Account.SID.Value

        $AccountAllowRules = @(
            $StoredRules |
                Where-Object {
                    $_.IdentityReference.Value -eq $SidValue -and
                    $_.AccessControlType -eq
                        [System.Security.AccessControl.AccessControlType]::Allow
                }
        )

        $ReadRules = @(
            $AccountAllowRules |
                Where-Object {
                    $_.ObjectType -eq [guid]::Empty -and
                    ($_.ActiveDirectoryRights -band $ReadMask) -eq $ReadMask
                }
        )

        $EnrollRules = @(
            $AccountAllowRules |
                Where-Object {
                    $_.ObjectType -eq $EnrollGuid -and
                    ($_.ActiveDirectoryRights -band $EnrollMask) -eq $EnrollMask
                }
        )

        if ($ReadRules.Count -eq 0) {
            throw "Controle mislukt: expliciet Read-recht ontbreekt voor $($Account.SamAccountName)."
        }

        if ($EnrollRules.Count -eq 0) {
            throw "Controle mislukt: expliciet Enroll-recht ontbreekt voor $($Account.SamAccountName)."
        }

        Write-Output (
            "PASS: expliciete Read- en Enroll-regels opgeslagen voor {0}." -f
            $Account.SamAccountName
        )
    }

    Write-Output "Template-DACL opgeslagen via $DomainAdminUser."
    Write-Output "Controle expliciete Enroll-regels:"

    $Entry.PSBase.ObjectSecurity.GetAccessRules(
        $true,
        $false,
        [System.Security.Principal.SecurityIdentifier]
    ) |
        Where-Object {
            $_.ObjectType -eq $EnrollGuid -and
            $_.IdentityReference.Value -in @(
                $Administrator.SID.Value,
                $Server3.SID.Value
            )
        } |
        Select-Object IdentityReference, ActiveDirectoryRights,
            AccessControlType, ObjectType |
        Format-List |
        Out-String -Width 200 |
        Write-Output
}
finally {
    $Entry.PSBase.Dispose()
}