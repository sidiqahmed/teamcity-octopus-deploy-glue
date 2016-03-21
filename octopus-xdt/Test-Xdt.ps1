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

########################################################
# init
########################################################
# Microsoft.Web.XmlTransform
$checkWebXdt = try{
    [Microsoft.Web.XmlTransform.XmlTransformableDocumentx] -as [type]
} catch{}

$xdtDll = Ensure-NugetFiles -packageId 'Microsoft.Web.Xdt' -packagePath 'lib\*\Microsoft.Web.XmlTransform.dll' -extractPath $currentScriptPath
$xdtDllPath = $xdtDll[0].FullName
write-verbose "Loading DLL $xdtDllPath"
Add-Type -LiteralPath $xdtDllPath
if (!$?) { throw "Unable to load Microsoft.Web.Xdt" }

write-verbose "Loading $currentScriptPath\IXMLTransformLogger.cs"
Add-Type -Path "$currentScriptPath\IXMLTransformLogger.cs"  -ReferencedAssemblies $xdtDllPath


########################################################
# main
########################################################
$xmlLogger = new-object Calamari.Xdt.VerboseTransformLogger -ArgumentList $supressWarnings, $supressLogging
if (!$?) { throw "Cannot create VerboseTransformLogger" }

# ---- Load XML Source ----
$xmlFile = gi $xmlPath
write-verbose "Loading $($xmlFile.FullName)"
$xmlSrc = New-Object Microsoft.Web.XmlTransform.XmlTransformableDocument
$xmlSrc.PreserveWhitespace = $true
$xmlSrc.Load($xmlFile.FullName)
if (!$?) { throw "Cannot load XML source" }

# ---- Gather ----
$xdtFiles = @()
write-verbose "Gathering XDT transform files"

# XDT Suffix
write-verbose "Gathering XDT transforms matching source filename and specified suffix"
$configFiles = Get-ChildItem $xmlFile.Directory -Filter '*.config'
foreach ($configFile in $configFiles) {
    if ( ($configFile.BaseName.Replace($xmlFile.BaseName,'')) -match '(?<suffix>^\.\w+$)' ) {
        $suffix = $matches.suffix
        if ($xdtSuffix -contains $suffix) {
            write-verbose "+ $($configFile.name)"
            $xdtFiles += $configFile
        }
    }
}

read-host
# Additional Files

# ---- Transforms ----
$transforms = @()
foreach ($xdtFile in $xdtFiles) {
    write-verbose "Applying $(xdtFile.Name) --> $($xmlFile.Name)"
    $transforms += New-Object Microsoft.Web.XmlTransform.XmlTransformation($xdtFile,$xmlLogger)
    
}