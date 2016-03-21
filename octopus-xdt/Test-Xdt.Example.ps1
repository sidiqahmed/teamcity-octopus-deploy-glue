# PWD
$currentScriptPath = Split-Path ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path
$scriptName = Split-Path (Get-Variable MyInvocation -Scope 0).Value.MyCommand.Path -Leaf

& $currentScriptPath\Test-Xdt.ps1 -xmlPath "$currentScriptPath\Samples\web.config" -xdtSuffix 'release'
