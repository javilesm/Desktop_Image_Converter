#Requires -Version 5.1
<#
.SYNOPSIS
    Pipeline de conversion grafica con validacion robusta para directorios y archivos individuales.
.DESCRIPTION
    Arquitectura de grado industrial que implementa:
    1. Soporte dual (procesamiento por lotes o archivo unico).
    2. Autodeteccion heuristica y extraccion de extensiones.
    3. Limpieza automatica de rutas copiadas de Windows.
    4. Validacion de existencia y permisos de directorios.
    5. Manejo de memoria mediante MemoryStream para evitar bloqueos.
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

    try {
        Write-Host "`n[+] IMAGE FORMAT CONVERSION PIPELINE" -ForegroundColor Cyan
        Write-Host "======================================" -ForegroundColor Cyan

        # --- 1. Ingesta y Saneamiento de Ruta ---
        if ([string]::IsNullOrWhiteSpace($DirectoryPath)) {
            $DirectoryPath = Read-Host "Ingresa la ruta absoluta del directorio o archivo de ORIGEN"
        }

        # Saneamiento: Elimina comillas si el usuario copio la ruta desde Windows Explorer
        $InputPath = $DirectoryPath.Replace('"', '').Replace("'", "").Trim()
        
        $isSingleFile  = $false
        $singleFileObj = $null

        if (Test-Path -Path $InputPath -PathType Leaf) {
            $isSingleFile  = $true
            $singleFileObj = Get-Item -Path $InputPath
            $DirectoryPath = $singleFileObj.DirectoryName
            $InputFormat   = $singleFileObj.Extension.Replace('.', '').ToLower()
            Write-Host "`n[*] Modo de Archivo Unico detectado. Omitiendo menu de entrada." -ForegroundColor Cyan
        }
        elseif (Test-Path -Path $InputPath -PathType Container) {
            $DirectoryPath = $InputPath
        }
        else {
            throw "ERROR: La ruta de origen no existe o es inaccesible: '$InputPath'"
        }

        # --- 2. Menu de Formato de Entrada (Solo para directorios) ---
        if (-not $isSingleFile) {
            Write-Host "`n[ Seleccione el formato de ENTRADA ]" -ForegroundColor Yellow
            for ($i = 0; $i -lt $menuOptions.Count; $i++) {
                Write-Host "  [$($i + 1)] $($menuOptions[$i].ToUpper())"
            }
            Write-Host "  [A] Autodetectar formatos en el directorio" -ForegroundColor Green
            
            $inSelection = Read-Host "`nOpcion (1-$($menuOptions.Count) o A)"
            if ($inSelection -match '^[aA]$') {
                $InputFormat = 'auto'
            }
            elseif ([int]$inSelection -ge 1 -and [int]$inSelection -le $menuOptions.Count) {
                $InputFormat = $menuOptions[[int]$inSelection - 1]
            }
            else { throw "Seleccion de entrada invalida." }
        }

        # --- 3. Menu de Formato de Salida ---
        Write-Host "`n[ Seleccione el formato de SALIDA ]" -ForegroundColor Yellow
        for ($i = 0; $i -lt $menuOptions.Count; $i++) {
            Write-Host "  [$($i + 1)] $($menuOptions[$i].ToUpper())"
        }
        
        $outSelection = Read-Host "`nOpcion (1-$($menuOptions.Count))"
        if ([int]$outSelection -ge 1 -and [int]$outSelection -le $menuOptions.Count) {
            $OutputFormat = $menuOptions[[int]$outSelection - 1]
        }
        else { throw "Seleccion de salida invalida." }

        # --- Normalizacion y Validacion de Formatos ---
        if (-not $isSingleFile) {
            $InputFormat = $InputFormat.Replace('.', '').ToLower().Trim()
        }
        $OutputFormat = $OutputFormat.Replace('.', '').ToLower().Trim()

        if ($InputFormat -eq $OutputFormat) {
            throw "Error Logico: El formato de salida (.$OutputFormat) es igual al de entrada."
        }
        if (-not $supportedFormats.ContainsKey($OutputFormat)) {
            throw "Error Logico: Formato de salida no soportado."
        }

        # --- 4. Menu de Directorio de Salida (Robustez de Ruta) ---
        Write-Host "`n[ Configuracion de DESTINO ]" -ForegroundColor Yellow
        Write-Host "  [1] Usar el mismo directorio de origen"
        Write-Host "  [2] Especificar un nuevo directorio"
        
        $outDirChoice = Read-Host "`nOpcion (1-2)"

        if ($outDirChoice -eq '2') {
            $OutputDirectory = Read-Host "Ingresa la ruta del nuevo directorio de salida"
            
            if (-not (Test-Path -Path $OutputDirectory -PathType Container)) {
                Write-Host "[!] El directorio no existe." -ForegroundColor Yellow
                $createDir = Read-Host "Desea crear la ruta: '$OutputDirectory'? (S/N)"
                
                if ($createDir -match '^[sS]$') {
                    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
                    Write-Host "[+] Infraestructura de salida creada." -ForegroundColor Green
                }
                else {
                    throw "Operacion abortada: No hay un directorio de salida valido."
                }
            }
        }
        else {
            $OutputDirectory = $DirectoryPath
        }

        # --- 5. Descubrimiento y Escaneo de Archivos ---
        $targetFiles = @()
        
        if ($isSingleFile) {
            $targetFiles = @($singleFileObj)
        }
        elseif ($InputFormat -eq 'auto') {
            Write-Host "`n[*] Escaneando archivos graficos soportados..." -ForegroundColor Cyan
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
            Write-Warning "No se encontraron archivos validos para procesar."
            return
        }

        # --- 6. Pipeline de Procesamiento ---
        $targetEncoding   = $supportedFormats[$OutputFormat]
        $reportCollection = [System.Collections.Generic.List[PSCustomObject]]::new()
        $counter          = 1

        Write-Host "[*] Preparando conversion de $($targetFiles.Count) archivo(s)." -ForegroundColor Yellow

        foreach ($file in $targetFiles) {
            $outputFileName = [System.IO.Path]::ChangeExtension($file.Name, ".$OutputFormat")
            $outputFullPath = Join-Path -Path $OutputDirectory -ChildPath $outputFileName
            $status         = 'Exitoso'
            $errorMessage   = 'N/A'
            $imgObject      = $null
            $memoryStream   = $null

            Write-Progress `
                -Activity "Procesamiento Grafico" `
                -Status "Procesando: $($file.Name)" `
                -PercentComplete (($counter / $targetFiles.Count) * 100)

            try {
                $fileBytes    = [System.IO.File]::ReadAllBytes($file.FullName)
                $memoryStream = [System.IO.MemoryStream]::new($fileBytes)
                $imgObject    = [System.Drawing.Bitmap]::new($memoryStream)

                $imgObject.Save($outputFullPath, $targetEncoding)
            }
            catch {
                $status       = 'Fallido'
                $errorMessage = $_.Exception.Message
            }
            finally {
                if ($null -ne $imgObject)    { $imgObject.Dispose() }
                if ($null -ne $memoryStream) { $memoryStream.Dispose() }
            }

            $reportCollection.Add([PSCustomObject]@{
                Origen   = $file.Name
                Destino  = $outputFileName
                Estado   = $status
                Detalles = $errorMessage
            })
            $counter++
        }

        Write-Progress -Activity "Procesamiento Grafico" -Completed

        # --- 7. Telemetria Final ---
        Write-Host "`n[+] REPORTE DE OPERACION:`n" -ForegroundColor Green
        $reportCollection | Format-Table -AutoSize

        $exitosos = ($reportCollection | Where-Object Estado -eq 'Exitoso').Count
        Write-Host "    Procesados con exito : $exitosos" -ForegroundColor Green
        Write-Host "    Destino Final        : $OutputDirectory" -ForegroundColor Cyan
    }
    catch {
        Write-Host "`n[X] ERROR CRITICO: " -ForegroundColor Red -NoNewline
        Write-Host $_.Exception.Message -ForegroundColor White
    }
    finally {
        Write-Host "`n[ END OF PROCESS ]" -ForegroundColor DarkGray
        Read-Host "Presiona ENTER para finalizar"
    }
}

Convert-ImageFormat
