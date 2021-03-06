<#
    .SYNOPSIS
    Tests XDT Configuratino transforms
    
    .DESCRIPTION
    foo
    
    .LINK
    https://github.com/OctopusDeploy/Calamari/blob/master/source/Calamari/Integration/ConfigurationTransforms/ConfigurationTransformer.cs

    .LINK
    http://learn-powershell.net/2013/02/08/powershell-and-events-object-events/
#>
param(
    # Source XML File to transform (e.g. web.config)
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript( { (Test-Path $_) -and (gi $_).extension -eq '.config' } )]
    [alias('xml')]
    [string]
    $xmlPath,
    # Suffix of files matching <SOURCE_XML>.<SUFFIX>.config in same directory
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [alias('xdt')]
    [string[]]
    $xdtSuffix = @('test','stage','production'),
    # Additional XDT transform paths relative to source .config
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $additionalXdtPaths,
    [switch]$supressWarnings,
    [switch]$supressLogging
)
#Requires -version 3

# PWD
$currentScriptPath = Split-Path ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path
$scriptName = Split-Path (Get-Variable MyInvocation -Scope 0).Value.MyCommand.Path -Leaf

########################################################
# func
########################################################
function Ensure-File {
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $filename,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $downloadUrl,
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path $_ })]
    [string]
    $diskPath = '.'
)
    $diskPath = (Resolve-Path $diskPath).Path
    $fileBinPath = ''
    $fileDiskPath = "$diskPath\$filename"
    write-verbose "Searching for $filename"
    if ((gcm $filename -ea 0)) {
        write-verbose "Using PATH $filename"
        $fileBinPath = (gcm $filename).path
    } elseif (Test-Path $fileDiskPath) {
        write-verbose "Using DISK $diskPath $filename"
        $fileBinPath = $fileDiskPath
    } else {
        write-verbose "Downloading $filename to DISK $diskPath"
        (New-Object System.Net.WebClient).DownloadFile($downloadUrl,$fileDiskPath)
        if (Test-Path $fileDiskPath) {
            $fileBinPath = $fileDiskPath
        }
    }
    if ($fileBinPath -and (Test-Path $fileBinPath)) {
        return (gi $fileBinPath)
    } else {
        throw "Cannot acquire nuget.exe"
    }
}
function Ensure-NugetFiles {
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $packageId,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $packagePath,
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript( {Test-Path $_} )]
    [string]
    $extractPath = '.'
)
    $fileDisk = ''
    $extractPath = (Resolve-Path $extractPath).Path
    $packageExtractedPath = "$extractPath\$($packageId).*\$packagePath"
    write-verbose "Searching for file $packageExtractedPath"
    if (!(Test-Path $packageExtractedPath)) {
        write-verbose "Checking for nuget.exe"
        $nugetBin = Ensure-File -filename 'nuget.exe' -downloadUrl 'http://nuget.org/nuget.exe' -diskPath $extractPath
        write-verbose "Downloading NuGet PackageID $packageId"
        $stdNuget = & $nugetBin.PsPath install $packageId -outputdirectory $extractPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Error with nuget install"
        }
    }
    $files = gi $packageExtractedPath -ea 0
    $filesCount = ($files | Measure).Count
    write-verbose "$filesCount files found in $packageExtractedPath"
    if ($filesCount -eq 0) { throw "Could not acquire files" }
    return $files
}

function Reset-XmlLoggerWarningGlobals {
    $GLOBAL:transformWarning = @()
    $GLOBAL:transformHasWarnings = $false
}

function Setup-XmlLogger {
param(
    [switch]$supressWarnings,
    [switch]$supressLogging
)
    Reset-XmlLoggerWarningGlobals

    write-verbose "Creating VerboseTransformLogger"
    $xmlLogger = new-object Calamari.Xdt.VerboseTransformLogger -ArgumentList $supressWarnings, $supressLogging
    if (!$?) { throw "Cannot create VerboseTransformLogger" }
    
    write-verbose "Registering Warning event handler"
    $eventSub = Register-ObjectEvent -InputObject $xmlLogger -EventName 'Warning' -Action {
        $GLOBAL:transformWarning += $Event.SourceArgs.Message
        $GLOBAL:transformHasWarnings = $true
    }
    if (!$?) { throw "Could not register event handler" }
    
    return new-object psobject -property @{
        eventSub = $eventSub
        xmlLogger = $xmlLogger
    }
}
function Apply-Transform {
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript( { (Test-Path $_) -and (gi $_).extension -eq '.config' } )]
    [string]
    $xmlPath,
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ (Test-Path $_) -and (gi $_).extension -eq '.config' })]
    [Alias('pspath')]
    [string[]]
    $xdtPaths,
    [switch]$supressWarnings,
    [switch]$supressLogging
)
BEGIN {
    write-verbose "Starting transforms on file $xmlPath"
    $xmlLogger = Setup-XmlLogger -supressWarnings:$supressWarnings -supressLogging:$supressLogging
        
    # Source Xml
    $xmlFile = Get-Item $xmlPath
}
PROCESS {
    foreach ($xdtPath in $xdtPaths) {
        $xdtFile = Get-Item $xdtPath
        $transformSuccess = $false
        $wouldFail = $false
        Reset-XmlLoggerWarningGlobals
        
        $ex = $null
        try {
            # Load XML Source
            write-verbose "Loading XML source $($xmlFile.fullname)"
            $xmlTransformDoc = New-Object Microsoft.Web.XmlTransform.XmlTransformableDocument
            $xmlTransformDoc.PreserveWhitespace = $true
            $xmlTransformDoc.Load($xmlFile.FullName)
            
            # Load Transform
            write-verbose "Loading XDT $($xdtFile.FullName)"
            $transform = New-Object Microsoft.Web.XmlTransform.XmlTransformation -ArgumentList $xdtFile.FullName, $true, $xmlLogger.xmlLogger
            
            # Apply
            write-verbose "Applying transform"
            $transformSuccess = $transform.Apply($xmlTransformDoc)
        } catch {
            $ex = $_
        }
        #TODO: Probably a better way to handle this async event
        start-sleep -seconds 1
        while ($xmlLogger.eventSub.JobStateInfo -eq 'running') {}
        
        if (!$supressWarnings -and (!$transformSuccess -or $GLOBAL:transformHasWarnings)) {
            $wouldFail = $true
        }
        new-object psobject -property @{
            resultTransform = $transformSuccess
            resultDoc = $xmlTransformDoc
            wouldFail = $wouldFail
            transformHasWarnings = $GLOBAL:transformHasWarnings
            transformWarning = $GLOBAL:transformWarning
            supressWarnings = $supressWarnings
            exception = $ex
            xmlFile = $xmlFile
            xdtFile = $xdtFile
        }
    }
}
END {
    $subId = ($xmlLogger.eventSub).Id
    write-verbose "Unregistering Event Subscriber $subId"
    Unregister-Event -SubscriptionId $subId
}}
function Find-XmlConfigTransforms {
param(
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript( { (Test-Path $_) -and (gi $_).extension -eq '.config' } )]
    [Alias('pspath')]
    [string]
    $xmlPath,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [alias('suffix')]
    [string[]]
    $xdtSuffix
)
    $xmlFile = gi $xmlPath
    $xdtBaseNameRegex = $xmlFile.BaseName + '\.(?<suffix>\w+$)'
    $xdtDirectory = $xmlFile.Directory
    write-verbose "Gathering XDT files matching basename $xdtBaseNameRegex in $xdtDirectory"
    $configFiles = Get-ChildItem $xdtDirectory -Filter '*.config'
    foreach ($configFile in $configFiles) {
        if ( $configFile.BaseName -match $xdtBaseNameRegex ) {
            $suffix = $matches.suffix
            if ($xdtSuffix -contains $suffix) {
                write-verbose "+ $($configFile.name)"
                $configFile
            } else {
                write-verbose "[ignore] $($configFile.name)"
            }
        }
    }
}
function Check-Type {
param(
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]
    $typeName
)
    $result = try{
        $x -as [type]
    } catch{}
    if ($result) {
        return $true
    }
    return $false
}
########################################################
# init
########################################################
# ---- Microsoft.Web.XmlTransform ----
$checkWebXdt = Check-Type 'Microsoft.Web.XmlTransform.XmlTransformableDocument'
$checkVeroseLogger = Check-Type 'Calamari.Xdt.VerboseTransformLogger'

# Nupkg
$xdtDll = Ensure-NugetFiles -packageId 'Microsoft.Web.Xdt' -packagePath 'lib\*\Microsoft.Web.XmlTransform.dll' -extractPath $currentScriptPath
$xdtDllPath = $xdtDll[0].FullName

# Load assembly
if ($checkWebXdt) {
    write-verbose "Loading DLL $xdtDllPath"
    Add-Type -LiteralPath $xdtDllPath
    if (!$?) { throw "Unable to load Microsoft.Web.Xdt" }
}
# Load IXMLTransform
if (!$checkVeroseLogger) {
    write-verbose "Loading $currentScriptPath\IXMLTransformLogger.cs"
    Add-Type -Path "$currentScriptPath\IXMLTransformLogger.cs"  -ReferencedAssemblies $xdtDllPath
}

########################################################
# main
########################################################
# ---- Gather ----
$xmlFile = Get-Item $xmlPath
$xdtFiles = @()

# XDT Suffix
if ($xdtSuffix) {
    $xdtFiles += $xmlFile | Find-XmlConfigTransforms -xdtSuffix $xdtSuffix
}

# Additional Files
if ($additionalXdtPaths) {
    foreach ($additionalXmlPath in $additionalXdtPaths) {
        $xdtFullpath = "$($xmlFile.Directory)\$additionalXmlPath"
        write-verbose "Adding $xdtFullpath"
        if (Test-Path $xdtFullpath) {
            $xdtFiles += (Get-Item $xdtFullpath)
        } else {
            write-warning "Could not find extra xdt path specified $xdtFullpath"
        }
    }
}

# ---- Transforms ----
$xdtFiles | Apply-Transform -xmlPath ($xmlFile.FullName) -supressWarnings:$supressWarnings -supressLogging:$supressLogging