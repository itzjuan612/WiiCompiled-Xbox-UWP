param(
  [Parameter(Mandatory = $true)][string]$PfxPath,
  [Parameter(Mandatory = $true)][string]$PfxPassword,
  [Parameter(Mandatory = $true)][string]$AppxPath
)
$ErrorActionPreference = 'Continue'
$log = Join-Path $PSScriptRoot 'deploy-result.txt'
"=== WiiCompiled UWP deploy $(Get-Date) ===" | Out-File $log -Encoding utf8
$pw = ConvertTo-SecureString $PfxPassword -Force -AsPlainText
try {
  Import-PfxCertificate -FilePath $PfxPath `
    -CertStoreLocation Cert:\LocalMachine\TrustedPeople -Password $pw -ErrorAction Stop |
    ForEach-Object { "TRUSTEDPEOPLE: $($_.Thumbprint)" | Out-File $log -Append -Encoding utf8 }
} catch { "TP-FAIL: $_" | Out-File $log -Append -Encoding utf8 }
try {
  Import-PfxCertificate -FilePath $PfxPath `
    -CertStoreLocation Cert:\LocalMachine\Root -Password $pw -ErrorAction Stop |
    ForEach-Object { "ROOT: $($_.Thumbprint)" | Out-File $log -Append -Encoding utf8 }
} catch { "ROOT-FAIL: $_" | Out-File $log -Append -Encoding utf8 }
try {
  Add-AppxPackage -Path $AppxPath -ErrorAction Stop
  'DEPLOY-OK' | Out-File $log -Append -Encoding utf8
} catch { "DEPLOY-FAIL: $_" | Out-File $log -Append -Encoding utf8 }
