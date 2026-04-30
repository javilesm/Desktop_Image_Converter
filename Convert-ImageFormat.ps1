#Requires -Version 5.1
<#
.SYNOPSIS
    Pipeline de conversion grafica con interfaz hacker bilingue y validacion robusta.
.DESCRIPTION
    Arquitectura de grado industrial que implementa:
    1. UI Bilingue (ES/EN) con estetica Terminal Hacker.
    2. Soporte dual (procesamiento por lotes o archivo unico).
    3. Autodeteccion heuristica y extraccion de extensiones.
    4. Limpieza automatica de rutas copiadas de Windows.
    5. Validacion de existencia y permisos de directorios.
    6. Manejo de memoria mediante MemoryStream para evitar bloqueos.
#>

function Convert-ImageFormat {
    [CmdletBinding()]
    param (
        [string]$DirectoryPath,
        [string]$InputFormat,
        [string]$OutputFormat,
        [string]$OutputDirectory
    )

    Add-Type -AssemblyName System.Drawing

    $supportedFormats = @{
        'png'  = [System.Drawing.Imaging.ImageFormat]::Png
        'jpg'  = [System.Drawing.Imaging.ImageFormat]::Jpeg
        'jpeg' = [System.Drawing.Imaging.ImageFormat]::Jpeg
        'bmp'  = [System.Drawing.Imaging.ImageFormat]::Bmp
        'gif'  = [System.Drawing.Imaging.ImageFormat]::Gif
        'tiff' = [System.Drawing.Imaging.ImageFormat]::Tiff
    }

    $menuOptions = @('bmp', 'jpg', 'png', 'gif', 'tiff')

    # --- ENCABEZADO ASCII  ---
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
        Write-Host "        [ DESKTOP IMAGE CONVERTER - BUILD 2026.1 ]" -ForegroundColor Yellow
        Write-Host "  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = `n" -ForegroundColor DarkGray
    }

    try {
        Show-Header

        # --- 1. Ingesta y Saneamiento de Ruta ---
        if ([string]::IsNullOrWhiteSpace($DirectoryPath)) {
            $DirectoryPath = Read-Host "[>] Ruta origen / Source path (Dir/File)"
        }

        $InputPath = $DirectoryPath.Replace('"', '').Replace("'", "").Trim()
        
        $isSingleFile  = $false
        $singleFileObj = $null

        if (Test-Path -Path $InputPath -PathType Leaf) {
            $isSingleFile  = $true
            $singleFileObj = Get-Item -Path $InputPath
            $DirectoryPath = $singleFileObj.DirectoryName
            $InputFormat   = $singleFileObj.Extension.Replace('.', '').ToLower()
            Write-Host "`n[SYS] Archivo unico detectado / Single file detected." -ForegroundColor Cyan
            Write-Host "[SYS] Omitiendo formato de entrada / Skipping input format.`n" -ForegroundColor Cyan
        }
        elseif (Test-Path -Path $InputPath -PathType Container) {
            $DirectoryPath = $InputPath
        }
        else {
            throw "ERROR: Ruta inaccesible / Path inaccessible: '$InputPath'"
        }

        # --- 2. Menu de Formato de Entrada ---
        if (-not $isSingleFile) {
            Write-Host ":: FORMATO DE ENTRADA / INPUT FORMAT ::" -ForegroundColor Yellow
            for ($i = 0; $i -lt $menuOptions.Count; $i++) {
                Write-Host "  [$($i + 1)] $($menuOptions[$i].ToUpper())" -ForegroundColor White
            }
            Write-Host "  [A] Autodetectar / Auto-detect" -ForegroundColor Green
            
            $inSelection = Read-Host "`n[>] Opcion / Option (1-$($menuOptions.Count) or A)"
            if ($inSelection -match '^[aA]$') {
                $InputFormat = 'auto'
            }
            elseif ([int]$inSelection -ge 1 -and [int]$inSelection -le $menuOptions.Count) {
                $InputFormat = $menuOptions[[int]$inSelection - 1]
            }
            else { throw "Seleccion invalida / Invalid selection." }
        }

        # --- 3. Menu de Formato de Salida ---
        Write-Host "`n:: FORMATO DE SALIDA / OUTPUT FORMAT ::" -ForegroundColor Yellow
        for ($i = 0; $i -lt $menuOptions.Count; $i++) {
            Write-Host "  [$($i + 1)] $($menuOptions[$i].ToUpper())" -ForegroundColor White
        }
        
        $outSelection = Read-Host "`n[>] Opcion / Option (1-$($menuOptions.Count))"
        if ([int]$outSelection -ge 1 -and [int]$outSelection -le $menuOptions.Count) {
            $OutputFormat = $menuOptions[[int]$outSelection - 1]
        }
        else { throw "Seleccion invalida / Invalid selection." }

        # --- Normalizacion ---
        if (-not $isSingleFile) { $InputFormat = $InputFormat.Replace('.', '').ToLower().Trim() }
        $OutputFormat = $OutputFormat.Replace('.', '').ToLower().Trim()

        if ($InputFormat -eq $OutputFormat) {
            throw "ERROR: Formato salida = entrada / Output equals input (.$OutputFormat)."
        }
        if (-not $supportedFormats.ContainsKey($OutputFormat)) {
            throw "ERROR: Formato no soportado / Unsupported format."
        }

        # --- 4. Menu de Directorio de Salida ---
        Write-Host "`n:: DESTINO / DESTINATION ::" -ForegroundColor Yellow
        Write-Host "  [1] Mismo directorio / Same directory" -ForegroundColor White
        Write-Host "  [2] Nueva ruta / New path" -ForegroundColor White
        
        $outDirChoice = Read-Host "`n[>] Opcion / Option (1-2)"

        if ($outDirChoice -eq '2') {
            $OutputDirectory = Read-Host "[>] Ingresa nueva ruta / Enter new path"
            
            if (-not (Test-Path -Path $OutputDirectory -PathType Container)) {
                Write-Host "[!] Ruta inexistente / Path does not exist." -ForegroundColor Yellow
                $createDir = Read-Host "[?] Crear directorio / Create directory? (S/Y/N)"
                
                if ($createDir -match '^[sSyY]$') {
                    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
                    Write-Host "[OK] Infraestructura creada / Infrastructure created." -ForegroundColor Green
                }
                else {
                    throw "Operacion abortada / Operation aborted."
                }
            }
        }
        else {
            $OutputDirectory = $DirectoryPath
        }

        # --- 5. Escaneo de Archivos ---
        $targetFiles = @()
        
        if ($isSingleFile) {
            $targetFiles = @($singleFileObj)
        }
        elseif ($InputFormat -eq 'auto') {
            Write-Host "`n[SYS] Escaneo heuristico / Heuristic scan in progress..." -ForegroundColor Cyan
            $targetFiles = Get-ChildItem -Path $DirectoryPath -File | Where-Object {
                $ext = $_.Extension.Replace('.', '').ToLower()
                $supportedFormats.ContainsKey($ext) -and ($ext -ne $OutputFormat)
            }
        }
        else {
            $targetFiles = Get-ChildItem -Path $DirectoryPath -Filter "*.$InputFormat" -File | Where-Object {
                $_.Extension.Replace('.', '').ToLower() -ne $OutputFormat
            }
        }

        if ($targetFiles.Count -eq 0) {
            Write-Warning "Cero archivos candidatos / Zero candidate files found."
            return
        }

        # --- 6. Pipeline de Procesamiento ---
        $targetEncoding   = $supportedFormats[$OutputFormat]
        $reportCollection = [System.Collections.Generic.List[PSCustomObject]]::new()
        $counter          = 1

        Write-Host "`n[SYS] Inicializando motor / Initializing engine. Archivos/Files: $($targetFiles.Count)" -ForegroundColor Yellow

        foreach ($file in $targetFiles) {
            $outputFileName = [System.IO.Path]::ChangeExtension($file.Name, ".$OutputFormat")
            $outputFullPath = Join-Path -Path $OutputDirectory -ChildPath $outputFileName
            $status         = 'OK'
            $errorMessage   = '---'
            $imgObject      = $null
            $memoryStream   = $null

            Write-Progress `
                -Activity "[/// PROCESSING DATA ///]" `
                -Status "$($file.Name) -> $outputFileName" `
                -PercentComplete (($counter / $targetFiles.Count) * 100)

            try {
                $fileBytes    = [System.IO.File]::ReadAllBytes($file.FullName)
                $memoryStream = [System.IO.MemoryStream]::new($fileBytes)
                $imgObject    = [System.Drawing.Bitmap]::new($memoryStream)

                $imgObject.Save($outputFullPath, $targetEncoding)
            }
            catch {
                $status       = 'FAIL'
                $errorMessage = $_.Exception.Message
            }
            finally {
                if ($null -ne $imgObject)    { $imgObject.Dispose() }
                if ($null -ne $memoryStream) { $memoryStream.Dispose() }
            }

            $reportCollection.Add([PSCustomObject]@{
                Source   = $file.Name
                Dest     = $outputFileName
                Status   = $status
                Log      = $errorMessage
            })
            $counter++
        }

        Write-Progress -Activity "[/// PROCESSING DATA ///]" -Completed

        # --- 7. Telemetria Final y Footer ---
        Write-Host "`n:: TELEMETRIA FINAL / FINAL TELEMETRY ::`n" -ForegroundColor Green
        $reportCollection | Format-Table -AutoSize

        $exitosos = ($reportCollection | Where-Object Status -eq 'OK').Count
        Write-Host " [>] Procesados / Successful : $exitosos" -ForegroundColor Green
        Write-Host " [>] Destino / Output Path   : $OutputDirectory`n" -ForegroundColor Cyan

    }
    catch {
        Write-Host "`n[FATAL ERROR] " -ForegroundColor Red -NoNewline
        Write-Host $_.Exception.Message -ForegroundColor White
    }
    finally {
        # --- FOOTER (CREDITOS & REPO) ---
        Write-Host " ___________________________________________________________ " -ForegroundColor DarkGray
        Write-Host "|                                                           |" -ForegroundColor DarkGray
        Write-Host "| " -ForegroundColor DarkGray -NoNewline
        Write-Host " Desarrollado por / Developed by: Jorge Luis Aviles Medina " -ForegroundColor DarkGray -NoNewline
        Write-Host "|" -ForegroundColor DarkGray
        Write-Host "| " -ForegroundColor DarkGray -NoNewline
        Write-Host " GitHub: https://github.com/javilesm/Desktop_Image_Converter" -ForegroundColor DarkGray -NoNewline
        Write-Host "|" -ForegroundColor DarkGray
        Write-Host "|___________________________________________________________|" -ForegroundColor DarkGray
        Write-Host "`n[ TERMINAL CLOSED ]" -ForegroundColor DarkGray
        Read-Host "Presiona ENTER para salir / Press ENTER to exit"
    }
}

Convert-ImageFormat
