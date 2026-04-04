$ErrorActionPreference = "Stop"

$projeto = Split-Path -Parent $MyInvocation.MyCommand.Path
$quarto = "C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe"
$rprofile = Join-Path $projeto ".Rprofile"
$renvProject = $projeto
$renvLib = Join-Path $projeto "renv\library\windows\R-4.4\x86_64-w64-mingw32"

if (-not (Test-Path $quarto)) {
  throw "Quarto nao encontrado em '$quarto'."
}

if (-not (Test-Path $rprofile)) {
  throw ".Rprofile nao encontrado em '$rprofile'."
}

$env:RENV_PROJECT = $renvProject
$env:R_PROFILE_USER = $rprofile
$env:R_LIBS_USER = $renvLib
& $quarto preview "painel/painel.qmd"
