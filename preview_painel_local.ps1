$ErrorActionPreference = "Stop"

function Get-RscriptPath {
  $command = Get-Command Rscript -ErrorAction SilentlyContinue
  if ($command -and $command.Source) {
    return $command.Source
  }

  $candidates = @()

  $userR = Join-Path $env:LOCALAPPDATA "Programs\R"
  if (Test-Path $userR) {
    $found = Get-ChildItem $userR -Recurse -Filter Rscript.exe -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($found) {
      return $found.FullName
    }
  }

  $candidates += @(
    "C:\Program Files\R\R-4.4.0\bin\Rscript.exe",
    "C:\Program Files\R\R-4.4.0\bin\x64\Rscript.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "Rscript nao encontrado. Instale o R 4.4.x ou adicione o Rscript ao PATH."
}

$projeto = Split-Path -Parent $MyInvocation.MyCommand.Path
$rscript = Get-RscriptPath

& $rscript (Join-Path $projeto "preview_painel_local.R")
