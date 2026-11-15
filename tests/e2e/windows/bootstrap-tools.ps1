<#
 Copyright 2026 Han Li and contributors

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
#>

# Provisions the Windows E2E image (tests/e2e/windows/Dockerfile): PowerShell 7,
# vfox from its release, and the Visual C++ runtime that the PHP builds load.
# The versions and the sha256 of the PowerShell and vfox archives come from the
# Dockerfile's ARG lines, which are also the place to move them.

$ErrorActionPreference = 'Stop'

# Downloads a file and fails unless its sha256 is the pinned one.
function Get-Pinned {
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Sha256
    )
    & curl.exe -fsSL --retry 3 --retry-delay 5 --retry-all-errors -o $Path $Url
    if ($LASTEXITCODE -ne 0) { throw "FAIL the download of $Url exited $LASTEXITCODE" }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
    if ($actual -ne $Sha256.ToUpperInvariant()) { throw "FAIL the sha256 of $Url is $actual, want $Sha256" }
}

$pwshVersion = $env:PWSH_VERSION
$pwshHome = 'C:\Program Files\PowerShell\7'
$pwshZip = Join-Path $env:TEMP 'pwsh.zip'
Get-Pinned -Url "https://github.com/PowerShell/PowerShell/releases/download/v${pwshVersion}/PowerShell-${pwshVersion}-win-x64.zip" -Path $pwshZip -Sha256 $env:PWSH_SHA256
New-Item -ItemType Directory -Force -Path $pwshHome | Out-Null
tar.exe -xf $pwshZip -C $pwshHome
if ($LASTEXITCODE -ne 0) { throw 'FAIL the PowerShell extraction exited non-zero' }
Remove-Item $pwshZip
if (-not (Test-Path (Join-Path $pwshHome 'pwsh.exe'))) { throw 'FAIL pwsh.exe is missing after the extraction' }

# vfox goes to a directory of its own, so the exec calls can put it on the PATH.
$vfoxVersion = $env:VFOX_VERSION
$vfoxZip = Join-Path $env:TEMP 'vfox.zip'
$vfoxExtract = Join-Path $env:TEMP 'vfox-extract'
$vfoxBin = 'C:\vfox-bin'
Get-Pinned -Url "https://github.com/version-fox/vfox/releases/download/v${vfoxVersion}/vfox_${vfoxVersion}_windows_x86_64.zip" -Path $vfoxZip -Sha256 $env:VFOX_SHA256
New-Item -ItemType Directory -Force -Path $vfoxExtract, $vfoxBin | Out-Null
tar.exe -xf $vfoxZip -C $vfoxExtract
if ($LASTEXITCODE -ne 0) { throw 'FAIL the vfox extraction exited non-zero' }
$vfoxExe = Get-ChildItem -Path $vfoxExtract -Recurse -Filter vfox.exe | Select-Object -First 1
if (-not $vfoxExe) { throw 'FAIL the vfox release has no vfox.exe' }
Copy-Item -Path $vfoxExe.FullName -Destination (Join-Path $vfoxBin 'vfox.exe') -Force
Remove-Item -Recurse -Force $vfoxExtract, $vfoxZip

# PHP's Windows builds load the Visual C++ runtime, which a Windows container
# does not ship. Microsoft's redirect moves with each update, so this download
# is not pinned; the installer is signed by Microsoft.
$vcRedist = Join-Path $env:TEMP 'vc_redist.x64.exe'
& curl.exe -fsSL --retry 3 --retry-delay 5 --retry-all-errors -o $vcRedist 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
if ($LASTEXITCODE -ne 0) { throw 'FAIL the Visual C++ runtime download' }
$install = Start-Process -FilePath $vcRedist -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
if ($install.ExitCode -notin 0, 3010) { throw "FAIL the Visual C++ runtime installer exited $($install.ExitCode)" }
Remove-Item $vcRedist

$machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
[Environment]::SetEnvironmentVariable('PATH', "$machinePath;$pwshHome;$vfoxBin", 'Machine')
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -PropertyType DWORD -Force | Out-Null

Write-Output 'PASS the Windows E2E image has PowerShell 7, vfox and the Visual C++ runtime'
