param(
    [Parameter(Mandatory)][string]$Directory,
    [Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$Architecture,
    [Parameter(Mandatory)][string]$Report
)
$ErrorActionPreference = 'Stop'
$exe = Join-Path $Directory 'TramSimFrance.exe'
$provenance = Get-Content (Join-Path $Directory 'RUNTIME-PROVENANCE.json') -Raw | ConvertFrom-Json
if ((Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $provenance.sha256) {
    throw 'Runtime bytes changed after verification of the official archive.'
}
if ($provenance.architecture -ne $Architecture) { throw 'Incorrect architecture in runtime provenance.' }
$signature = Get-AuthenticodeSignature -FilePath $exe
if ($signature.Status -ne 'Valid') { throw "Runtime Authenticode is not trusted: $($signature.Status)" }
if ($signature.SignerCertificate.Subject -notmatch 'CN=Prehensile Tales B\.V\.') {
    throw "Unexpected upstream runtime publisher: $($signature.SignerCertificate.Subject)"
}
@{
    architecture = $Architecture
    authenticode = $signature.Status.ToString()
    publisher = $signature.SignerCertificate.Subject
    signer_thumbprint = $signature.SignerCertificate.Thumbprint
    timestamped = ($null -ne $signature.TimeStamperCertificate)
    executable_sha256 = $provenance.sha256
    upstream = $provenance.origin
    smart_app_control_policy_tested = $false
} | ConvertTo-Json | Set-Content $Report -Encoding utf8
Write-Output "Trusted official Godot runtime verified ($Architecture)."
