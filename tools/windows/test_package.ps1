param(
    [Parameter(Mandatory)][string]$Directory,
    [Parameter(Mandatory)][string]$Msi,
    [Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$Architecture,
    [Parameter(Mandatory)][string]$Reports
)
$ErrorActionPreference = 'Stop'
$Directory = (Resolve-Path $Directory).Path
$Msi = (Resolve-Path $Msi).Path
New-Item -ItemType Directory -Force $Reports | Out-Null
$Reports = (Resolve-Path $Reports).Path
$expectedOS = if ($Architecture -eq 'arm64') { 'Arm64' } else { 'X64' }
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne $expectedOS) {
    throw "The package must be tested on a native $Architecture runner."
}
$com = New-Object -ComObject WindowsInstaller.Installer
$database = $com.OpenDatabase($Msi, 0)
$summary = $database.SummaryInformation(0)
$template = $summary.Property(7)
$expectedTemplate = if ($Architecture -eq 'arm64') { 'Arm64' } else { 'x64' }
if ($template.Split(';')[0] -ne $expectedTemplate) { throw "Wrong MSI platform: $template" }
$view = $database.OpenView('SELECT `File` FROM `File`')
$view.Execute()
$count = 0
while ($null -ne $view.Fetch()) { $count++ }
$payload = @(Get-ChildItem $Directory -Recurse -File)
if ($count -ne $payload.Count) { throw "Incomplete MSI payload: $count records vs $($payload.Count) files." }
$view.Close()
[Runtime.InteropServices.Marshal]::FinalReleaseComObject($database) | Out-Null
[Runtime.InteropServices.Marshal]::FinalReleaseComObject($com) | Out-Null

$id = [Guid]::NewGuid().ToString('N')
$install = Join-Path $env:TEMP "TramSim-installed-$Architecture-$id"
$empty = Join-Path $env:TEMP "TramSim-no-source-$id"
New-Item -ItemType Directory $empty | Out-Null
function Test-Launch([string]$Exe, [string]$Name) {
    $log = Join-Path $Reports "$Name.log"
    # No --main-pack, --path, project source or unsigned launcher. Same adjacent
    # PCK discovery used by a normal double-click; only rendering/audio are dummy.
    $process = Start-Process -FilePath $Exe -WorkingDirectory $empty -PassThru -ArgumentList @(
        '--headless', '--audio-driver', 'Dummy', '--quit-after', '20',
        '--log-file', "`"$log`"", '--', '--windows-package-smoke'
    )
    if (-not $process.WaitForExit(120000)) {
        $process.Kill($true); throw "$Name startup timeout; see $log"
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "$Name exit code $($process.ExitCode); see $log" }
    $text = Get-Content $log -Raw
    if ($text -notmatch 'WINDOWS_PACKAGE_SMOKE\|ready\|') { throw "$Name did not load the actual game menu." }
    if ($text -match '(?m)SCRIPT ERROR|Parse Error|^ERROR:') { throw "$Name startup errors; see $log" }
}
function Run-Msi([string]$Action, [string]$Name) {
    $log = Join-Path $Reports "$Name-msi.log"
    $arguments = @($Action, "`"$Msi`"", '/qn', '/norestart', '/l*v', "`"$log`"")
    if ($Action -in @('/i','/fvomus')) { $arguments += "INSTALLDIR=`"$install`"" }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $process = Start-Process msiexec.exe -Wait -PassThru -ArgumentList $arguments
        if ($process.ExitCode -ne 1618) { break }
        Start-Sleep -Seconds 5
    }
    if ($process.ExitCode -notin @(0,3010)) { throw "MSI $Name failed: $($process.ExitCode); see $log" }
}
Test-Launch (Join-Path $Directory 'TramSimFrance.exe') 'portable'
$installed = $false
try {
    Run-Msi '/i' 'install'; $installed = $true
    foreach ($file in $payload) {
        $relative = [IO.Path]::GetRelativePath($Directory, $file.FullName)
        $target = Join-Path $install $relative
        if (-not (Test-Path $target)) { throw "Installed payload missing: $relative" }
        if ((Get-FileHash $target).Hash -ne (Get-FileHash $file.FullName).Hash) { throw "Installed file changed: $relative" }
    }
    $exe = Join-Path $install 'TramSimFrance.exe'
    if ((Get-AuthenticodeSignature $exe).Status -ne 'Valid') { throw 'Installed runtime signature is invalid.' }
    Test-Launch $exe 'installed'
    # Repair/reinstall is a frequent source of mid-installation MSI failures.
    Run-Msi '/fvomus' 'reinstall'
    Run-Msi '/x' 'uninstall'; $installed = $false
    if (Test-Path $exe) { throw 'MSI uninstall left the installed executable.' }
    @{
        architecture = $Architecture; native_os = $expectedOS; msi_template = $template
        payload_files = $count; portable_boot = 'passed'; installation = 'passed'
        installed_boot = 'passed'; reinstall = 'passed'; uninstall = 'passed'
        signature_after_install = 'Valid'; rendering_test = 'headless; physical GPU not tested'
        smart_app_control_policy_tested = $false
    } | ConvertTo-Json | Set-Content (Join-Path $Reports 'package-validation.json') -Encoding utf8
} finally {
    if ($installed) {
        $cleanup = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @('/x', "`"$Msi`"", '/qn', '/norestart')
    }
    Remove-Item $empty -Force -Recurse
}
