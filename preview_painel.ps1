$ErrorActionPreference = "Stop"

function Get-QuartoPath {
  $command = Get-Command quarto -ErrorAction SilentlyContinue
  if ($command -and $command.Source) {
    return $command.Source
  }

  $candidates = @(
    "C:\Program Files\Quarto\bin\quarto.exe",
    "C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "Quarto nao encontrado. Instale o Quarto CLI ou o RStudio com Quarto embutido."
}

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
$quarto = Get-QuartoPath
$rscript = Get-RscriptPath
$rHome = Split-Path -Parent (Split-Path -Parent $rscript)
$rBin = Join-Path $rHome "bin"
$rprofile = Join-Path $projeto ".Rprofile"
$renvProject = $projeto
$renvLib = Join-Path $projeto "renv\library\windows\R-4.4\x86_64-w64-mingw32"

if (-not (Test-Path $rscript)) {
  throw "Rscript nao encontrado em '$rscript'."
}

if (-not (Test-Path $rprofile)) {
  throw ".Rprofile nao encontrado em '$rprofile'."
}

if (-not (Test-Path $renvLib)) {
  throw "Biblioteca local do renv nao encontrada em '$renvLib'."
}

$env:R_HOME = $rHome
$env:RENV_PROJECT = $renvProject
$env:R_PROFILE_USER = $rprofile
$env:R_LIBS_USER = $renvLib
$env:PATH = "$rBin;$env:PATH"
& $quarto preview "painel/painel.qmd"
