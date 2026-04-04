$ErrorActionPreference = "Stop"

$projeto = Split-Path -Parent $MyInvocation.MyCommand.Path
$rscript = "C:\Program Files\R\R-4.4.0\bin\Rscript.exe"

if (-not (Test-Path $rscript)) {
  throw "Rscript nao encontrado em '$rscript'."
}

& $rscript (Join-Path $projeto "preview_painel_local.R")
