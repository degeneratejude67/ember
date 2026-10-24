# Downloads the newest successful CI build (Ember.ipa and the simulator screenshots)
# into out\<run id>. usage: powershell -File tools\fetch.ps1
param([string]$Repo = "degeneratejude67/ember")
$ErrorActionPreference = "Stop"

$runs = gh run list -R $Repo -w build -b main -s success -L 1 --json databaseId,headSha,createdAt | ConvertFrom-Json
if (-not $runs) { throw "No successful build yet." }
$id = $runs[0].databaseId
$out = Join-Path $PSScriptRoot "..\out\$id"
if (-not (Test-Path $out)) { gh run download $id -R $Repo -D $out }
"Run $id ($($runs[0].headSha.Substring(0,7)), $($runs[0].createdAt))"
Get-ChildItem $out -Recurse -File | Select-Object @{n='File';e={$_.FullName.Replace((Resolve-Path $out).Path + '\', '')}}, Length
