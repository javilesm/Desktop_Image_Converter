#Requires -Version 5.1

<#
.SYNOPSIS
    Convierte imágenes entre formatos usando SixLabors.ImageSharp.

.DESCRIPTION
    Soporta conversión individual y batch. Detecta y descarga dependencias
    NuGet automáticamente. Valida rutas, tamaños y formatos antes de procesar.

.PARAMETER Path
    Ruta a un archivo de imagen o directorio. Si se omite, se solicita interactivamente.

.PARAMETER MaxFileSizeMB
    Tamaño máximo por archivo en MB. Por defecto: 200.

.PARAMETER MaxConcurrent
    Número máximo de archivos a procesar en paralelo (requiere PS 7+). Por defecto: 4.

.EXAMPLE
    .\Convert-Image.ps1 -Path "C:\Fotos"
    .\Convert-Image.ps1 -Path "C:\img.webp" -MaxFileSizeMB 500
#>

[CmdletBinding()]
param(
    [string]$Path,
    [ValidateRange(1, 10240)]
    [int]$MaxFileSizeMB = 200,
    [ValidateRange(1, 16)]
    [int]$MaxConcurrent = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constantes ────────────────────────────────────────────────────────────────

$SUPPORTED_FORMATS = @('jpg', 'jpeg', 'jfif', 'png', 'bmp', 'gif', 'tiff', 'webp')

# Desde ImageSharp 3.x, WebP (y otros formatos) están incluidos en el paquete
# principal. No existe 'SixLabors.ImageSharp.Formats.Webp' como paquete separado.
# Si necesitas anclar a una versión específica, cámbiala aquí; con $null el
# script consulta el índice NuGet y descarga la última estable automáticamente.
$NUGET_PACKAGES = @(
    @{ Name = 'SixLabors.ImageSharp'; Version = $null }
)

$TARGET_FRAMEWORKS = @('net8.0', 'net7.0', 'net6.0', 'netstandard2.1', 'netstandard2.0')

# ── Helpers de UI ─────────────────────────────────────────────────────────────
function Show-Header {
    Clear-Host
    Write-Host " ___________________________________________________________ " -ForegroundColor DarkGray
    Write-Host "|                                                           |" -ForegroundColor DarkGray
    Write-Host "|  " -ForegroundColor DarkGray -NoNewline
    Write-Host " /// @JORGE_AVILES_MX | HECHO EN MEXICO ///      " -ForegroundColor Cyan -NoNewline
    Write-Host " |" -ForegroundColor DarkGray
    Write-Host "|___________________________________________________________|" -ForegroundColor DarkGray
    Write-Host "      _   ___   _____ _    ___ ___ __  __  " -ForegroundColor Green
    Write-Host "     | | /_\ \ / /_ _| |  | __/ __|  \/  | " -ForegroundColor Green
    Write-Host "  _  | |/ _ \ V / | || |__| _|\__ \ |\/| | " -ForegroundColor Green
    Write-Host " | \_/ /_/ \_\_/ |___|____|___|___/_|  |_| " -ForegroundColor Green
    Write-Host "  \___/                                    " -ForegroundColor Green
    Write-Host "  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = " -ForegroundColor DarkGray
    Write-Host "   >>> DESKTOP IMAGE CONVERTER :: NEXT-GEN PIPELINE <<<" -ForegroundColor Yellow
    Write-Host "   >>> ImageSharp Engine | WebP Ready | Batch Optimized <<<" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "   @JORGE_AVILES_MX  |  Hecho en México 🇲🇽" -ForegroundColor DarkGray
    Write-Host "   -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}
# -----------------------------
function Show-Footer {
# -----------------------------
    param([string]$OutputDir)

    Write-Host ""
    Write-Host "   -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "   ✔ Pipeline finalizado correctamente" -ForegroundColor Green

    if ($OutputDir) {
        Write-Host "   📁 Output: $OutputDir" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "   Desarrollado por Jorge Luis Aviles Medina" -ForegroundColor DarkGray
    Write-Host "   GitHub: https://github.com/javilesm/Desktop_Image_Converter" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "   [ SESSION CLOSED ]" -ForegroundColor DarkGray
    Write-Host ""

    Read-Host "Presiona ENTER para salir"
}
function Write-Status {
    param([string]$Message, [string]$Level = 'INFO')
    $colors = @{ INFO = 'Cyan'; OK = 'Green'; WARN = 'Yellow'; ERR = 'Red' }
    $color  = $colors[$Level]
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Read-MenuOption {
    param(
        [string]   $Prompt,
        [string[]] $Options,
        [switch]   $AllowAuto
    )

    Write-Host "`n:: $Prompt ::" -ForegroundColor DarkCyan

    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  [$($i + 1)] $($Options[$i].ToUpper())"
    }
    if ($AllowAuto) { Write-Host "  [A] AUTO (detectar extensión)" }

    while ($true) {
        $raw = (Read-Host '[>] Opción').Trim()

        if ($AllowAuto -and $raw -match '^[aA]$') {
            return 'auto'
        }

        if ($raw -match '^\d+$') {
            $idx = [int]$raw
            if ($idx -ge 1 -and $idx -le $Options.Count) {
                return $Options[$idx - 1]
            }
        }

        Write-Status "Opción inválida. Ingresa un número entre 1 y $($Options.Count)$(if ($AllowAuto) { ' o A' })." 'WARN'
    }
}

# ── Validación de rutas ───────────────────────────────────────────────────────

function Resolve-SafePath {
    <#
    .SYNOPSIS
        Resuelve y valida una ruta. Rechaza path traversal, UNC y caracteres peligrosos.
    #>
    param([string]$RawPath)

    # Quitar comillas, trim
    $cleaned = $RawPath.Trim().Trim('"', "'")

    # Bloquear path traversal
    if ($cleaned -match '\.\.[\\/]' -or $cleaned -match '[\\/]\.\.') {
        throw "Ruta rechazada: contiene path traversal ('..') → '$cleaned'"
    }

    # Bloquear rutas UNC remotas (\\server\share)
    if ($cleaned -match '^\\\\[^\\]+\\') {
        throw "Rutas UNC remotas no están permitidas → '$cleaned'"
    }

    # Bloquear caracteres de control y shell
    if ($cleaned -match '[<>|;&`$]') {
        throw "Ruta contiene caracteres no permitidos → '$cleaned'"
    }

    # Resolver a ruta absoluta canónica
    try {
        $resolved = [System.IO.Path]::GetFullPath($cleaned)
    }
    catch {
        throw "No se pudo resolver la ruta → '$cleaned': $($_.Exception.Message)"
    }

    return $resolved
}

function Get-InputContext {
    param([string]$RawPath)

    if ([string]::IsNullOrWhiteSpace($RawPath)) {
        $RawPath = Read-Host '[>] Ruta origen (archivo o directorio)'
    }

    $safe = Resolve-SafePath $RawPath

    if (Test-Path $safe -PathType Leaf) {
        $file = Get-Item $safe
        $ext  = $file.Extension.TrimStart('.').ToLower()

        if ($ext -notin $SUPPORTED_FORMATS) {
            throw "Extensión '$ext' no es un formato soportado. Formatos válidos: $($SUPPORTED_FORMATS -join ', ')"
        }

        return [PSCustomObject]@{
            Mode        = 'Single'
            File        = $file
            Directory   = $file.DirectoryName
            InputFormat = $ext
        }
    }
    elseif (Test-Path $safe -PathType Container) {
        return [PSCustomObject]@{
            Mode        = 'Batch'
            File        = $null
            Directory   = $safe
            InputFormat = $null
        }
    }
    else {
        throw "La ruta no existe o no es accesible → '$safe'"
    }
}

function Resolve-OutputDirectory {
    param([string]$BaseDir)

    Write-Host "`n:: Directorio de salida ::" -ForegroundColor DarkCyan
    Write-Host "  [1] Mismo directorio de origen"
    Write-Host "  [2] Especificar nueva ruta"

    while ($true) {
        $choice = (Read-Host '[>] Opción').Trim()

        switch ($choice) {
            '1' { return $BaseDir }
            '2' {
                $raw     = Read-Host '[>] Nueva ruta de salida'
                $newPath = Resolve-SafePath $raw

                # Confirmar creación si no existe
                if (-not (Test-Path $newPath)) {
                    $confirm = Read-Host "[?] '$newPath' no existe. ¿Crear? [s/N]"
                    if ($confirm -notmatch '^[sS]$') {
                        Write-Status 'Operación cancelada por el usuario.' 'WARN'
                        continue
                    }
                    New-Item -ItemType Directory -Path $newPath -Force | Out-Null
                    Write-Status "Directorio creado: $newPath" 'OK'
                }
                elseif (-not (Test-Path $newPath -PathType Container)) {
                    Write-Status "La ruta existe pero no es un directorio. Inténtalo de nuevo." 'WARN'
                    continue
                }

                return $newPath
            }
            default {
                Write-Status 'Ingresa 1 o 2.' 'WARN'
            }
        }
    }
}

# ── Selección de archivos ─────────────────────────────────────────────────────

function Get-TargetFiles {
    param(
        [PSCustomObject] $Context,
        [string]         $InputFormat,
        [string]         $OutputFormat,
        [long]           $MaxBytes
    )

    if ($Context.Mode -eq 'Single') {
        $files = @($Context.File)
    }
    elseif ($InputFormat -eq 'auto') {
        $files = @(Get-ChildItem $Context.Directory -File |
            Where-Object { $_.Extension.TrimStart('.').ToLower() -in $SUPPORTED_FORMATS } |
            Where-Object { $_.Extension.TrimStart('.').ToLower() -ne $OutputFormat })
    }
    else {
        $variants = @($InputFormat)
        if ($InputFormat -eq 'jpg')  { $variants += 'jpeg', 'jfif' }
        if ($InputFormat -eq 'jpeg') { $variants += 'jpg',  'jfif' }
        if ($InputFormat -eq 'jfif') { $variants += 'jpg',  'jpeg' }

        $files = @(Get-ChildItem $Context.Directory -File |
            Where-Object { $_.Extension.TrimStart('.').ToLower() -in $variants })
    }

    if ($files.Count -eq 0) {
        Write-Status 'No se encontraron archivos que coincidan con los criterios.' 'WARN'
        return @()
    }

    $oversized = @($files | Where-Object { $_.Length -gt $MaxBytes })
    if ($oversized.Count -gt 0) {
        Write-Status "$($oversized.Count) archivo(s) superan el limite de $([math]::Round($MaxBytes/1MB)) MB y seran omitidos:" 'WARN'
        $oversized | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor Yellow }
    }

    return @($files | Where-Object { $_.Length -le $MaxBytes })
}

# ── Dependencias NuGet ────────────────────────────────────────────────────────

function Get-NuGetPackagePath {
    param([string]$Name, [string]$Version)
    return Join-Path $PSScriptRoot "lib\$Name.$Version"
}

function Resolve-NuGetVersion {
    <#
    .SYNOPSIS
        Consulta el índice NuGet v3 y devuelve la última versión estable del paquete.
    #>
    param([string]$Name)

    $indexUrl = "https://api.nuget.org/v3-flatcontainer/$($Name.ToLower())/index.json"
    Write-Status "Consultando versión más reciente de $Name..."

    try {
        $response = Invoke-RestMethod -Uri $indexUrl -UseBasicParsing
    }
    catch {
        throw "No se pudo consultar el índice NuGet para '$Name': $($_.Exception.Message)"
    }

    # Filtrar solo versiones estables (sin pre-release: sin guión)
    $stable = $response.versions | Where-Object { $_ -notmatch '-' } | Select-Object -Last 1

    if (-not $stable) {
        throw "No se encontró ninguna versión estable de '$Name' en NuGet."
    }

    Write-Status "Versión seleccionada: $Name $stable"
    return $stable
}

function Find-InstalledPackageDir {
    <#
    .SYNOPSIS
        Busca cualquier versión ya instalada del paquete en lib\, sin importar la versión.
    #>
    param([string]$Name)

    $libDir = Join-Path $PSScriptRoot 'lib'
    if (-not (Test-Path $libDir)) { return $null }

    $existing = Get-ChildItem $libDir -Directory -Filter "$Name.*" -ErrorAction SilentlyContinue |
                Select-Object -First 1

    return $existing
}

function Install-NuGetPackage {
    param(
        [string] $Name,
        [string] $Version   # puede ser $null → se resuelve dinámicamente
    )

    $libDir = Join-Path $PSScriptRoot 'lib'

    # ── 1. ¿Ya hay alguna versión instalada? ──────────────────────────────────
    $existingDir = Find-InstalledPackageDir $Name
    if ($existingDir) {
        Write-Status "Ya instalado: $Name ($($existingDir.Name))" 'OK'
        return
    }

    # ── 2. Resolver versión si no está anclada ────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = Resolve-NuGetVersion $Name
    }

    $pkgDir = Get-NuGetPackagePath $Name $Version

    if (-not (Test-Path $libDir)) {
        New-Item -ItemType Directory -Path $libDir | Out-Null
    }

    # ── 3. Descargar .nupkg ───────────────────────────────────────────────────
    $nameLower = $Name.ToLower()
    $url       = "https://api.nuget.org/v3-flatcontainer/$nameLower/$Version/$nameLower.$Version.nupkg"
    $nupkg     = Join-Path $libDir "$Name.$Version.nupkg"

    Write-Status "Descargando $Name $Version..."

    try {
        # Invoke-WebRequest funciona mejor en entornos proxy que WebClient
        Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing
    }
    catch {
        # Limpiar archivo parcial si quedó
        if (Test-Path $nupkg) { Remove-Item $nupkg -Force }
        throw "Error al descargar $Name $Version desde NuGet ($url): $($_.Exception.Message)"
    }

    # ── 4. Extraer ────────────────────────────────────────────────────────────
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $pkgDir)
    }
    catch {
        if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
        throw "Error al extraer $Name $Version $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $nupkg) { Remove-Item $nupkg -Force }
    }

    Write-Status "$Name $Version instalado" 'OK'
}

function Import-ImageSharpAssemblies {
    $loaded = @([System.AppDomain]::CurrentDomain.GetAssemblies() |
                ForEach-Object { $_.GetName().Name })

    $dlls = @(foreach ($pkg in $NUGET_PACKAGES) {
        # Localizar el directorio instalado (cualquier versión)
        $pkgDir = Find-InstalledPackageDir $pkg.Name
        if (-not $pkgDir) {
            Write-Status "Directorio de paquete no encontrado: $($pkg.Name)" 'WARN'
            continue
        }
        foreach ($fx in $TARGET_FRAMEWORKS) {
            $fxDir = Join-Path $pkgDir.FullName "lib\$fx"
            if (Test-Path $fxDir) {
                Get-ChildItem $fxDir -Filter '*.dll' -ErrorAction SilentlyContinue
                break  # Primer framework compatible encontrado
            }
        }
    })

    foreach ($dll in $dlls) {
        $asmName = [System.IO.Path]::GetFileNameWithoutExtension($dll.Name)
        if ($asmName -in $loaded) { continue }

        try {
            Add-Type -Path $dll.FullName -ErrorAction Stop
            Write-Status "Cargado: $($dll.Name)" 'OK'
        }
        catch [System.Reflection.ReflectionTypeLoadException] {
            Write-Status "Assembly omitido (dependencias faltantes): $($dll.Name)" 'WARN'
        }
        catch {
            Write-Status "No se pudo cargar $($dll.Name): $($_.Exception.Message)" 'WARN'
        }
    }
}

function Initialize-Dependencies {
    Write-Status 'Verificando dependencias...'

    foreach ($pkg in $NUGET_PACKAGES) {
        Install-NuGetPackage $pkg.Name $pkg.Version
    }

    Import-ImageSharpAssemblies

    # Verificar que los tipos críticos estén disponibles
    $required = @('SixLabors.ImageSharp.Image', 'SixLabors.ImageSharp.Formats.Jpeg.JpegEncoder')
    foreach ($type in $required) {
        if (-not ([System.Management.Automation.PSTypeName]$type).Type) {
            throw "El tipo '$type' no está disponible después de cargar dependencias. Verifica la instalación."
        }
    }

    Write-Status 'Dependencias listas' 'OK'
}

# ── Encoder ───────────────────────────────────────────────────────────────────

function Get-ImageEncoder {
    <#
    .SYNOPSIS
        Devuelve una instancia del encoder de ImageSharp 3.x para el formato dado.
        En v3 la sobrecarga Save(string, IImageEncoder) fue eliminada; el encoder
        se pasa a Save(Stream, IImageEncoder), por lo que aqui solo construimos
        el objeto — el FileStream lo abre Convert-SingleImage.
    #>
    param([string]$Format)

    # jfif es JPEG con marcador APP0 — mismo encoder
    if ($Format -eq 'jpeg' -or $Format -eq 'jfif') { $Format = 'jpg' }

    $encoderMap = @{
        jpg  = 'SixLabors.ImageSharp.Formats.Jpeg.JpegEncoder'
        png  = 'SixLabors.ImageSharp.Formats.Png.PngEncoder'
        bmp  = 'SixLabors.ImageSharp.Formats.Bmp.BmpEncoder'
        gif  = 'SixLabors.ImageSharp.Formats.Gif.GifEncoder'
        tiff = 'SixLabors.ImageSharp.Formats.Tiff.TiffEncoder'
        webp = 'SixLabors.ImageSharp.Formats.Webp.WebpEncoder'
    }

    if (-not $encoderMap.ContainsKey($Format)) {
        throw "Formato de salida no soportado: '$Format'. Validos: $($encoderMap.Keys -join ', ')"
    }

    $typeName = $encoderMap[$Format]
    $type     = ([System.Management.Automation.PSTypeName]$typeName).Type

    if (-not $type) {
        throw "El encoder para '$Format' no esta disponible (tipo '$typeName' no cargado)."
    }

    return $type::new()
}

# ── Conversion ────────────────────────────────────────────────────────────────

function Convert-SingleImage {
    <#
    .SYNOPSIS
        Convierte un archivo de imagen al formato de salida indicado.
        Usa Save(Stream, IImageEncoder) — unica firma garantizada en ImageSharp 3.x.
    #>
    param(
        [System.IO.FileInfo] $File,
        [string]             $OutputDir,
        [object]             $Encoder,
        [string]             $OutFormat
    )

    $image  = $null
    $stream = $null
    try {
        $outputName = [System.IO.Path]::ChangeExtension($File.Name, ".$OutFormat")
        $outputPath = Join-Path $OutputDir $outputName

        $image  = [SixLabors.ImageSharp.Image]::Load($File.FullName)
        $stream = [System.IO.File]::Open(
            $outputPath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $image.Save($stream, $Encoder)

        return [PSCustomObject]@{
            Source  = $File.Name
            Dest    = $outputName
            SizeMB  = [math]::Round($File.Length / 1MB, 2)
            Status  = 'OK'
            Message = ''
        }
    }
    catch {
        $safeMsg = $_.Exception.Message -replace [regex]::Escape($File.DirectoryName), '[dir]'
        return [PSCustomObject]@{
            Source  = $File.Name
            Dest    = '---'
            SizeMB  = [math]::Round($File.Length / 1MB, 2)
            Status  = 'FAIL'
            Message = $safeMsg
        }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $image)  { $image.Dispose()  }
    }
}

# ── Reporte ───────────────────────────────────────────────────────────────────

function Show-ConversionReport {
    param(
        [object[]] $Results,
        [string]   $OutputDir,
        [string]   $InputFormat,
        [string]   $OutputFormat
    )

    $ok   = @($Results | Where-Object Status -eq 'OK')
    $fail = @($Results | Where-Object Status -eq 'FAIL')

    Write-Host "`n═══ Resultado de conversión ═══" -ForegroundColor Cyan
    Write-Host "  Formato:   $($InputFormat.ToUpper()) → $($OutputFormat.ToUpper())"
    Write-Host "  Destino:   $OutputDir"
    Write-Host "  OK:        $($ok.Count)" -ForegroundColor Green
    if ($fail.Count -gt 0) {
        Write-Host "  FAIL:      $($fail.Count)" -ForegroundColor Red
    }
    Write-Host ''

    $Results | Format-Table -AutoSize -Property Source, Dest, SizeMB, Status

    if ($fail.Count -gt 0) {
        Write-Host '── Errores ──' -ForegroundColor Red
        foreach ($f in $fail) {
            Write-Host "  $($f.Source): $($f.Message)" -ForegroundColor DarkRed
        }
    }
}

# ── Punto de entrada ──────────────────────────────────────────────────────────

function Start-Converter {
    param([string]$InputPath, [int]$MaxFileSizeMBParam, [int]$MaxConcurrentParam)

    Initialize-Dependencies

    $ctx = Get-InputContext $InputPath

    # Formato de entrada
    if ($ctx.Mode -eq 'Batch') {
        $inputFormat = Read-MenuOption 'Formato de entrada' $SUPPORTED_FORMATS -AllowAuto
    }
    else {
        $inputFormat = $ctx.InputFormat
        Write-Status "Formato detectado: $($inputFormat.ToUpper())"
    }

    # Formato de salida (excluir el de entrada de las opciones)
    $outputOptions = $SUPPORTED_FORMATS | Where-Object { $_ -ne $inputFormat -and $_ -notin @('jpeg', 'jfif') }
    $outputFormat  = Read-MenuOption 'Formato de salida' $outputOptions

    # Normalizar variantes JPEG
    if ($inputFormat  -in 'jpeg', 'jfif') { $inputFormat  = 'jpg' }
    if ($outputFormat -in 'jpeg', 'jfif') { $outputFormat = 'jpg' }

    if ($inputFormat -eq $outputFormat) {
        throw "El formato de salida ('$outputFormat') es igual al de entrada. Elige uno diferente."
    }

    $outDir   = Resolve-OutputDirectory $ctx.Directory
    $maxBytes = [long]$MaxFileSizeMBParam * 1MB
    $files    = @(Get-TargetFiles $ctx $inputFormat $outputFormat $maxBytes)

    if ($files.Count -eq 0) {
        Write-Status 'No hay archivos para procesar. Saliendo.' 'WARN'
        return
    }

    Write-Status "Procesando $($files.Count) archivo(s)..."

    $encoder = Get-ImageEncoder $outputFormat
    $results = @()

    foreach ($f in $files) {
        $result   = Convert-SingleImage $f $outDir $encoder $outputFormat
        $results += $result

        $icon = if ($result.Status -eq 'OK') { '✓' } else { '✗' }
        $color = if ($result.Status -eq 'OK') { 'Green' } else { 'Red' }
        Write-Host "  $icon $($result.Source) → $($result.Dest)" -ForegroundColor $color
    }

    Show-ConversionReport $results $outDir $inputFormat $outputFormat
}

# ── Ejecución ──────────────────────────────────────────────────────────────────

try {
    Show-Header 
    Start-Converter -InputPath $Path -MaxFileSizeMBParam $MaxFileSizeMB -MaxConcurrentParam $MaxConcurrent
}
catch {
    Write-Status $_.Exception.Message 'ERR'
    exit 1
}
finally {
        Show-Footer   # 👈 siempre se ejecuta
}
