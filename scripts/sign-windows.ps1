#Requires -Version 5.1
<#
.SYNOPSIS
  M9 Stream-J (task 79) — Authenticode code-signing (EV cert), the Windows
  analog of `scripts/sign.sh`'s Developer ID codesign (ADR-M9-004,
  `docs/01-architecture/windows-parity.md` Section 1 row 5).

.DESCRIPTION
  SCRIPT + CONFIG ONLY. NOT executed by this session, ever — real
  Authenticode signing needs the owner's EV (Extended Validation) code-
  signing certificate, which this repo does not hold and CI verification
  cannot fabricate. There is no Windows box, no `signtool.exe`, and no
  PowerShell host with a real cert store on this machine — this file is
  parse-checked only (`pwsh -NoProfile -Command` syntax parse, or
  PSScriptAnalyzer if available), never run against a real binary.

  Signs `signtool sign /tr <RFC3161 timestamp URL> /td sha256 /fd sha256`
  with an EV cert, matching `sign.sh`'s own inside-out-signing discipline
  where it applies (a single MSI has no nested frameworks to sign deepest-
  first the way a `.app` bundle does — WiX v3/v4 MSIs are one file; the
  vendored `cc`/`copilot` CLI resource embedded inside the MSI is verified-
  not-resigned by its own cross-repo signing contract, `scripts/
  verify-vendored-cc.sh`'s pattern — this script never re-signs it).

  RFC3161 timestamping (`/tr` + `/td sha256`) is deliberate, not optional:
  an Authenticode signature with no trusted timestamp expires when the
  signing certificate itself expires, which would silently invalidate
  every already-shipped, already-installed MSI's signature the day the
  cert lapses — the exact "signature must remain verifiable for the
  lifetime of every artifact already in the field" property `sign.sh`'s
  own `--timestamp` codesign flag already secures on macOS.

.NOTES
  ## Reads identity from the environment — never hardcoded (invariant #4)

    CT_SIGN_THUMBPRINT   Required. The SHA-1 thumbprint of the EV code-
                          signing certificate in the signer's certificate
                          store (`Cert:\CurrentUser\My` or
                          `Cert:\LocalMachine\My`) — never a literal in
                          this file or in `tauri.conf.json`.
    CT_SIGNTOOL_PATH      Required. The ABSOLUTE path to `signtool.exe`.
                          Deliberately never resolved via a bare `PATH`
                          lookup (the same "never invoke bare <name>"
                          discipline `platform::windows::forced`'s
                          `dsregcmd_absolute_path` and this crate's own
                          vendored-CLI resolution already apply) — `
                          signtool.exe` ships with the Windows SDK at a
                          build-machine-specific path with no single
                          well-known system location the way
                          `dsregcmd.exe` has, so this script REQUIRES an
                          explicit absolute path rather than guessing one.
    CT_TIMESTAMP_URL      Optional. Defaults to DigiCert's public RFC3161
                          responder (matches `tauri.conf.json`'s own
                          `bundle.windows.timestampUrl`, kept in sync by
                          hand — a future session could add a fitness
                          test cross-checking the two if drift becomes a
                          real risk).

  ## No bypass flags — ever (invariant #4/#5)

  There is no `-SkipVerify`/`-Force`/"insecure" switch anywhere in this
  script. Every failure path below writes an error and exits non-zero;
  nothing here has a code path that proceeds past a missing thumbprint,
  a missing signtool path, or a failed signing/verification call.

.PARAMETER MsiPath
  Path to the built, unsigned MSI to sign (produced by `tauri build`'s WiX
  bundler against `packaging/windows/wix/main.wxs`).

.EXAMPLE
  $env:CT_SIGN_THUMBPRINT = '<the real EV cert thumbprint>'
  $env:CT_SIGNTOOL_PATH   = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe'
  ./scripts/sign-windows.ps1 -MsiPath 'C:\out\CopilotControlTower_0.1.0_x64.msi'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$thumbprint = $env:CT_SIGN_THUMBPRINT
if ([string]::IsNullOrWhiteSpace($thumbprint)) {
    Write-Error "CT_SIGN_THUMBPRINT is not set (EV code-signing certificate thumbprint). Never hardcode it here — export it from a CI secret / the signer's certificate store."
    exit 1
}

$signtool = $env:CT_SIGNTOOL_PATH
if ([string]::IsNullOrWhiteSpace($signtool)) {
    Write-Error "CT_SIGNTOOL_PATH is not set. This script never resolves signtool.exe via a bare PATH lookup — set the full absolute path explicitly."
    exit 1
}
if (-not ([System.IO.Path]::IsPathRooted($signtool))) {
    Write-Error "CT_SIGNTOOL_PATH must be an absolute path; got: $signtool"
    exit 1
}
if (-not (Test-Path -LiteralPath $signtool -PathType Leaf)) {
    Write-Error "signtool.exe not found at CT_SIGNTOOL_PATH: $signtool"
    exit 1
}

$timestampUrl = $env:CT_TIMESTAMP_URL
if ([string]::IsNullOrWhiteSpace($timestampUrl)) {
    # Kept in sync BY HAND with tauri.conf.json's bundle.windows.timestampUrl.
    $timestampUrl = 'http://timestamp.digicert.com'
}

if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) {
    Write-Error "MSI not found at: $MsiPath"
    exit 1
}

Write-Host "signing (Authenticode, EV cert thumbprint $thumbprint) via $signtool ..."

& $signtool sign `
    /sha1 $thumbprint `
    /tr $timestampUrl `
    /td sha256 `
    /fd sha256 `
    $MsiPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "signtool sign failed with exit code $LASTEXITCODE — refusing to continue. No fallback/insecure signing path exists in this script."
    exit $LASTEXITCODE
}

Write-Host "verifying Authenticode signature (verify-not-resign) ..."
& $signtool verify /pa /tw $MsiPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "signtool verify failed after signing with exit code $LASTEXITCODE — the produced artifact is not trustworthy; refusing to declare success."
    exit $LASTEXITCODE
}

Write-Host "signed + verified: $MsiPath"
