param([Parameter(Mandatory)][string]$Msi, [Parameter(Mandatory)][string]$Report)
$ErrorActionPreference = 'Stop'
if (-not $env:WINDOWS_SIGNING_PFX_BASE64) {
    @{ status = 'NotSigned'; reason = 'No project code-signing certificate configured.' } |
        ConvertTo-Json | Set-Content $Report -Encoding utf8
    Write-Output 'MSI container is unsigned; the embedded official Godot runtime remains signed.'
    exit 0
}
$path = Join-Path $env:RUNNER_TEMP ('TramSim-signing-' + [Guid]::NewGuid().ToString('N') + '.pfx')
$certificate = $null
try {
    [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($env:WINDOWS_SIGNING_PFX_BASE64))
    $password = ConvertTo-SecureString $env:WINDOWS_SIGNING_PFX_PASSWORD -AsPlainText -Force
    $certificate = Import-PfxCertificate -FilePath $path -Password $password -CertStoreLocation Cert:\CurrentUser\My
    $certificate = @($certificate | Where-Object HasPrivateKey)[0]
    if ($null -eq $certificate) { throw 'Code-signing certificate has no private key.' }
    $signature = Set-AuthenticodeSignature -FilePath $Msi -Certificate $certificate -HashAlgorithm SHA256 `
        -TimestampServer 'http://timestamp.digicert.com'
    if ($signature.Status -ne 'Valid') { throw "MSI signature is not trusted: $($signature.Status)" }
    @{ status = $signature.Status.ToString(); publisher = $signature.SignerCertificate.Subject } |
        ConvertTo-Json | Set-Content $Report -Encoding utf8
} finally {
    Remove-Item $path -ErrorAction SilentlyContinue
    if ($null -ne $certificate) { Remove-Item "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -ErrorAction SilentlyContinue }
}
