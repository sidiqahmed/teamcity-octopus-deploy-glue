# PWD
$currentScriptPath = Split-Path ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path
$scriptName = Split-Path (Get-Variable MyInvocation -Scope 0).Value.MyCommand.Path -Leaf

$xmlPath = "$currentScriptPath\Samples\web.config"

# Valid
& $currentScriptPath\Test-Xdt.ps1 -xdtSuffix @('release') -xmlPath $xmlPath

# Bad XDT
& $currentScriptPath\Test-Xdt.ps1 -additionalXdtPaths 'bad.config' -xmlPath $xmlPath

# Warnings
& $currentScriptPath\Test-Xdt.ps1 -xdtSuffix @('CauseWarnings') -xmlPath $xmlPath

# Supressed Warnings
& $currentScriptPath\Test-Xdt.ps1 -supressWarnings -xdtSuffix @('CauseWarnings') -xmlPath $xmlPath
