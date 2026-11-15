# escape=`
# Copyright 2026 Han Li and contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The Windows E2E image (see docs/e2e.md): servercore with PowerShell 7, vfox
# from its release, and this checkout as the plugin. The Visual C++ runtime is left
# out on purpose: the plugin installs it, and the suite checks that it does.
# tests/e2e/windows starts one container per PHP version and drives each one
# through pwsh exec calls.
ARG BASE_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2025-KB5122871-amd64
FROM ${BASE_IMAGE}

# The archives are pinned by version and sha256; bootstrap-tools.ps1 checks them.
ARG PWSH_VERSION=7.6.6
ARG PWSH_SHA256=02fe458be20493fbdf43f61ea20610b811ee6c738ab1676c61b9cfcd1a33c860
ARG VFOX_VERSION=1.1.0
ARG VFOX_SHA256=1bbec8fffddbb62de0d93030c3f6203c69680662bc65257ca4a5e611cb607d0a

SHELL ["powershell", "-NoProfile", "-Command"]

COPY tests/e2e/windows/bootstrap-tools.ps1 C:\bootstrap-tools.ps1
RUN powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\bootstrap-tools.ps1'

# The checkout as the plugin archive that `vfox add -s` installs. The archive is
# made under PowerShell 7, as the CI workflows make it.
COPY . C:\plugin
RUN ["C:\\Program Files\\PowerShell\\7\\pwsh.exe", "-NoProfile", "-Command", "Compress-Archive -Path 'C:\\plugin\\*' -DestinationPath 'C:\\php-plugin.zip'"]

WORKDIR C:\work

# Long-lived container: the Go test drives every phase through pwsh exec calls,
# so the main process just idles here.
ENTRYPOINT ["C:/Program Files/PowerShell/7/pwsh.exe", "-NoProfile", "-Command"]
CMD ["while ($true) { Start-Sleep 3600 }"]
