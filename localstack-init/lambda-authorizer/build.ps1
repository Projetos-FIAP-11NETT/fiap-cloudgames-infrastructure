# PowerShell build script for Lambda Authorizer
param()

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$OUTPUT_DIR = Join-Path $SCRIPT_DIR "build"
$ZIP_FILE = Join-Path $env:TEMP ("fiap-authorizer-{0}.zip" -f (Get-Date -Format "yyyyMMddHHmmss"))
$ROOT_ZIP_FILE = Join-Path (Split-Path -Parent $SCRIPT_DIR) "function.zip"
$PUBLISH_DIR = Join-Path $OUTPUT_DIR "publish"

Write-Host "[build] Cleaning previous build..."
if (Test-Path $OUTPUT_DIR) {
    Remove-Item -Recurse -Force $OUTPUT_DIR
}
New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null

Write-Host "[build] Publishing Lambda function..."
dotnet publish (Join-Path $SCRIPT_DIR "FiapCloudGames.Lambda.Authorizer.csproj") -c Release -o $PUBLISH_DIR --self-contained false
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

Write-Host "[build] Creating deployment package..."

# Remove unnecessary files from publish directory
Write-Host "[build] Cleaning up unnecessary files..."
$DIRS_TO_REMOVE = @("refs", "wwwroot", "Resources")
foreach ($dir in $DIRS_TO_REMOVE) {
    $fullPath = Join-Path $PUBLISH_DIR $dir
    if (Test-Path $fullPath) {
        Remove-Item -Recurse -Force $fullPath
    }
}

# Remove .pdb, .dbg files
Get-ChildItem -Path $PUBLISH_DIR -Recurse -Include "*.pdb", "*.dbg" | Remove-Item -Force

# Create ZIP file directly from publish folder with only essential files
Push-Location $PUBLISH_DIR
try {
    if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
        if (Test-Path $ZIP_FILE) {
            Remove-Item -Force $ZIP_FILE
        }
        Compress-Archive -Path "*" -DestinationPath $ZIP_FILE -Force
    } else {
        Write-Host "[build] Compress-Archive not available, using System.IO.Compression"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($PUBLISH_DIR, $ZIP_FILE, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    }
} finally {
    Pop-Location
}

Copy-Item -Path $ZIP_FILE -Destination $ROOT_ZIP_FILE -Force

Write-Host "[build] Lambda function packaged: $ZIP_FILE"
Get-Item $ZIP_FILE | Select-Object -Property FullName, @{Name="Size"; Expression={"{0:N0} bytes" -f $_.Length}}

exit 0
