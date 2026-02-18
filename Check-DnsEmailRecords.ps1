param(
    [string[]]$Domains,

    [string]$DomainsFile,

    [string[]]$DkimSelectors = @('default', 'selector1', 'selector2', 'google', 'k1'),

    [string]$LogPath
)

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }

if (-not $DomainsFile) {
    $DomainsFile = Join-Path $scriptDir 'domains.txt'
}

if (-not $LogPath) {
    $LogPath = Join-Path $scriptDir ("dns_mail_check_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

function Test-Spf {
    param([string]$Domain)

    $txtRecords = Resolve-DnsName -Name $Domain -Type TXT -ErrorAction SilentlyContinue
    return ($txtRecords | Where-Object { $_.Strings -match 'v=spf1' } | Select-Object -First 1)
}

function Test-Dmarc {
    param([string]$Domain)

    $txtRecords = Resolve-DnsName -Name "_dmarc.$Domain" -Type TXT -ErrorAction SilentlyContinue
    return ($txtRecords | Where-Object { $_.Strings -match 'v=DMARC1' } | Select-Object -First 1)
}

function Test-Dkim {
    param(
        [string]$Domain,
        [string[]]$Selectors
    )

    foreach ($selector in $Selectors) {
        $dkimHost = "$selector._domainkey.$Domain"
        $txtRecords = Resolve-DnsName -Name $dkimHost -Type TXT -ErrorAction SilentlyContinue
        $match = $txtRecords | Where-Object { $_.Strings -match 'v=DKIM1' -or $_.Strings -match 'k=rsa' } | Select-Object -First 1
        if ($match) {
            return [PSCustomObject]@{
                Selector = $selector
                Record   = ($match.Strings -join '')
            }
        }
    }

    return $null
}

if (-not $Domains -and (Test-Path -LiteralPath $DomainsFile)) {
    $Domains = Get-Content -LiteralPath $DomainsFile -ErrorAction SilentlyContinue
}

$validDomains = $Domains |
    ForEach-Object { $_.Trim() } |
    Where-Object {
        $_ -and
        $_ -notmatch '^\d+$' -and
        $_ -match '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    } |
    Select-Object -Unique

"DNS Mail Check gestartet: $(Get-Date)" | Out-File -FilePath $LogPath -Encoding UTF8
"Geprüfte DKIM Selectors: $($DkimSelectors -join ', ')" | Out-File -FilePath $LogPath -Append -Encoding UTF8
"Domains Datei: $DomainsFile" | Out-File -FilePath $LogPath -Append -Encoding UTF8
"" | Out-File -FilePath $LogPath -Append -Encoding UTF8

if (-not $validDomains) {
    "Keine gültigen Domains gefunden. Entweder -Domains angeben oder domains.txt im Skriptordner pflegen." | Tee-Object -FilePath $LogPath -Append
    "Log gespeichert unter: $LogPath" | Write-Host
    exit 1
}

foreach ($domain in $validDomains) {
    $spf = Test-Spf -Domain $domain
    $dmarc = Test-Dmarc -Domain $domain
    $dkim = Test-Dkim -Domain $domain -Selectors $DkimSelectors

    $line = "{0} | SPF: {1} | DKIM: {2} | DMARC: {3}" -f $domain, ($(if ($spf) { 'OK' } else { 'FEHLT' })), ($(if ($dkim) { "OK ($($dkim.Selector))" } else { 'FEHLT' })), ($(if ($dmarc) { 'OK' } else { 'FEHLT' }))
    $line | Tee-Object -FilePath $LogPath -Append
}

"" | Out-File -FilePath $LogPath -Append -Encoding UTF8
"Fertig: $(Get-Date)" | Out-File -FilePath $LogPath -Append -Encoding UTF8
"Log gespeichert unter: $LogPath" | Write-Host
