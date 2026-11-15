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

# CI only: moves Docker's data root off C:, which on GitHub-hosted Windows
# runners is a network-attached OS disk where every file flush takes
# milliseconds, onto the runner's local D: drive. Extracting image layers and
# whatever the e2e containers write flush file by file, so on C: the servercore
# pull alone took minutes. Go's caches and the temp directory follow. A runner
# without a local D: keeps all of it on C:.

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if (-not $env:GITHUB_ACTIONS) { throw 'FAIL this script moves the Docker data root; it is for CI runners only' }

Get-Volume | Where-Object DriveLetter | Format-Table -AutoSize DriveLetter, FileSystem, Size, SizeRemaining | Out-String | Write-Output

# A D: on the disk C: is on would be no faster.
$dDisk = (Get-Partition -DriveLetter D -ErrorAction SilentlyContinue).DiskNumber
if ($null -eq $dDisk -or $dDisk -eq (Get-Partition -DriveLetter C).DiskNumber) {
    Write-Output 'PASS no local disk here; Docker, Go and the temp directory stay on C:'
    exit 0
}

$drive = 'D:'
$dataRoot = "$drive\docker"
$go = "$drive\go"
$temp = "$drive\temp"
New-Item -ItemType Directory -Force -Path $dataRoot, "$go\mod", "$go\build", $temp | Out-Null
"GOMODCACHE=$go\mod", "GOCACHE=$go\build", "TEMP=$temp", "TMP=$temp" | Add-Content -Path $env:GITHUB_ENV

# The engine windows-latest preinstalls: point its config at the local disk and
# restart it. It holds no images yet, so nothing has to move.
$config = 'C:\ProgramData\docker\config\daemon.json'
$settings = $null
if (Test-Path $config) { $settings = Get-Content $config -Raw | ConvertFrom-Json }
if (-not $settings) { $settings = [pscustomobject]@{} }
$settings | Add-Member -NotePropertyName 'data-root' -NotePropertyValue $dataRoot -Force
Stop-Service docker
New-Item -ItemType Directory -Force -Path (Split-Path $config) | Out-Null
$settings | ConvertTo-Json -Depth 8 | Set-Content -Path $config
Start-Service docker

$PSNativeCommandUseErrorActionPreference = $false
$root = ''
for ($attempt = 1; $attempt -le 60; $attempt++) {
    $root = (& docker info --format '{{.DockerRootDir}}' 2>$null) -join ''
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 2
}
$PSNativeCommandUseErrorActionPreference = $true
if ($root -ne $dataRoot) { throw "FAIL the docker engine keeps its data in '$root', not $dataRoot" }

Write-Output "PASS Docker keeps its data on $dataRoot, Go its caches in $go, and the temp directory is $temp"
