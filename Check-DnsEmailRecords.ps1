param(
    [Parameter(Mandatory = $true)]
    [string[]]$Domains,

    [string[]]$DkimSelectors = @('default', 'selector1', 'selector2', 'google', 'k1'),

    [string]$LogPath = ".\\dns_mail_check_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

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
        $host = "$selector._domainkey.$Domain"
        $txtRecords = Resolve-DnsName -Name $host -Type TXT -ErrorAction SilentlyContinue
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

"DNS Mail Check gestartet: $(Get-Date)" | Out-File -FilePath $LogPath -Encoding UTF8
"Geprüfte DKIM Selectors: $($DkimSelectors -join ', ')" | Out-File -FilePath $LogPath -Append -Encoding UTF8
"" | Out-File -FilePath $LogPath -Append -Encoding UTF8

foreach ($domain in $Domains) {
    $spf = Test-Spf -Domain $domain
    $dmarc = Test-Dmarc -Domain $domain
    $dkim = Test-Dkim -Domain $domain -Selectors $DkimSelectors

    $line = "{0} | SPF: {1} | DKIM: {2} | DMARC: {3}" -f $domain, ($(if ($spf) { 'OK' } else { 'FEHLT' })), ($(if ($dkim) { "OK ($($dkim.Selector))" } else { 'FEHLT' })), ($(if ($dmarc) { 'OK' } else { 'FEHLT' }))

    $line | Tee-Object -FilePath $LogPath -Append
}

"" | Out-File -FilePath $LogPath -Append -Encoding UTF8
"Fertig: $(Get-Date)" | Out-File -FilePath $LogPath -Append -Encoding UTF8
"Log gespeichert unter: $LogPath" | Write-Host
