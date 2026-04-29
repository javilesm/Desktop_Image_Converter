#Requires -Version 5.1
<#
.SYNOPSIS
    Convierte imagenes entre formatos soportados por System.Drawing.
.DESCRIPTION
    Pipeline de conversion con validacion de entrada/salida, manejo seguro
    de memoria mediante MemoryStream (evita el lock GDI+ sobre archivos origen),
    y reporte estructurado por consola.
.PARAMETER DirectoryPath
    Ruta absoluta del directorio que contiene las imagenes a convertir.
.PARAMETER InputFormat
    Extension del formato de entrada (ej: bmp, jpg, png).
.PARAMETER OutputFormat
    Extension del formato de salida (ej: png, tiff, jpg).
.PARAMETER OutputDirectory
    (Opcional) Directorio de destino. Si se omite, los archivos se guardan
    en el mismo directorio que los originales.
#>

function Convert-ImageFormat {
    [CmdletBinding()]
    param (
        [string]$DirectoryPath,
        [string]$InputFormat,
        [string]$OutputFormat,
        [string]$OutputDirectory
    )

    # Add-Type se carga al inicio, fuera del try, para que cualquier fallo
    # de ensamblado sea evidente antes de iniciar el pipeline.
    Add-Type -AssemblyName System.Drawing

    # Mapa de formatos soportados (entrada Y salida)
    $supportedFormats = @{
        'png'  = [System.Drawing.Imaging.ImageFormat]::Png
        'jpg'  = [System.Drawing.Imaging.ImageFormat]::Jpeg
        'jpeg' = [System.Drawing.Imaging.ImageFormat]::Jpeg
        'bmp'  = [System.Drawing.Imaging.ImageFormat]::Bmp
        'gif'  = [System.Drawing.Imaging.ImageFormat]::Gif
        'tiff' = [System.Drawing.Imaging.ImageFormat]::Tiff
    }

    try {
        Write-Host "`n[+] Image Format Conversion Pipeline" -ForegroundColor Cyan
        Write-Host "======================================" -ForegroundColor Cyan

        # --- Recoleccion de parametros interactivos ---
        if ([string]::IsNullOrWhiteSpace($DirectoryPath)) {
            $DirectoryPath = Read-Host "Ingresa la ruta absoluta del directorio"
        }

        if (-not (Test-Path -Path $DirectoryPath -PathType Container)) {
            throw "El directorio especificado no existe: '$DirectoryPath'"
        }

        if ([string]::IsNullOrWhiteSpace($InputFormat)) {
            $InputFormat = Read-Host "Formato de ENTRADA (ej: bmp, jpg, png)"
        }

        if ([string]::IsNullOrWhiteSpace($OutputFormat)) {
            $OutputFormat = Read-Host "Formato de SALIDA (ej: png, tiff, jpg)"
        }

        # --- Normalizacion ---
        $InputFormat  = $InputFormat.Replace('.', '').ToLower().Trim()
        $OutputFormat = $OutputFormat.Replace('.', '').ToLower().Trim()

        # Validar formato de ENTRADA
        if (-not $supportedFormats.ContainsKey($InputFormat)) {
            throw "Formato de entrada no soportado: '.$InputFormat'. Validos: $($supportedFormats.Keys -join ', ')"
        }

        # Validar formato de SALIDA
        if (-not $supportedFormats.ContainsKey($OutputFormat)) {
            throw "Formato de salida no soportado: '.$OutputFormat'. Validos: $($supportedFormats.Keys -join ', ')"
        }

        # Anti-colision
        if ($InputFormat -eq $OutputFormat) {
            throw "El formato de salida (.$OutputFormat) no puede ser identico al de entrada (.$InputFormat)."
        }

        # --- Directorio de destino (opcional) ---
        if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
            $OutputDirectory = $DirectoryPath
        }
        elseif (-not (Test-Path -Path $OutputDirectory -PathType Container)) {
            Write-Host "[*] Creando directorio de salida: $OutputDirectory" -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        }

        # --- Descubrimiento de archivos ---
        $targetFiles = Get-ChildItem -Path $DirectoryPath -Filter "*.$InputFormat" -File

        if ($targetFiles.Count -eq 0) {
            Write-Warning "No se encontraron archivos .$InputFormat en: $DirectoryPath"
            return
        }

        $targetEncoding   = $supportedFormats[$OutputFormat]
        $reportCollection = [System.Collections.Generic.List[PSCustomObject]]::new()
        $counter          = 1

        Write-Host "`n[*] Procesando $($targetFiles.Count) archivo(s)..." -ForegroundColor Yellow

        # --- Loop principal ---
        foreach ($file in $targetFiles) {

            $outputFileName = [System.IO.Path]::ChangeExtension($file.Name, ".$OutputFormat")
            $outputFullPath = Join-Path -Path $OutputDirectory -ChildPath $outputFileName
            $status         = 'Exitoso'
            $errorMessage   = 'N/A'
            $imgObject      = $null
            $memoryStream   = $null

            Write-Progress `
                -Activity "Pipeline de Conversion Grafica" `
                -Status "Procesando: $($file.Name)" `
                -PercentComplete (($counter / $targetFiles.Count) * 100)

            try {
                # MemoryStream evita el lock GDI+ sobre el archivo origen.
                # FromFile() mantiene el archivo bloqueado hasta que el Bitmap
                # se descarta, impidiendo guardarlo en la misma ruta.
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

        # Limpiar barra de progreso al finalizar
        Write-Progress -Activity "Pipeline de Conversion Grafica" -Completed

        # --- Reporte final ---
        $exitosos = ($reportCollection | Where-Object Estado -eq 'Exitoso').Count
        $fallidos = ($reportCollection | Where-Object Estado -eq 'Fallido').Count

        Write-Host "`n[+] Telemetria de conversion:`n" -ForegroundColor Green
        $reportCollection | Format-Table -AutoSize

        Write-Host "    Exitosos : $exitosos" -ForegroundColor Green
        if ($fallidos -gt 0) {
            Write-Host "    Fallidos : $fallidos" -ForegroundColor Red
        }
        else {
            Write-Host "    Fallidos : $fallidos" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "`n[X] EJECUCION INTERRUMPIDA: " -ForegroundColor Red -NoNewline
        Write-Host $_.Exception.Message -ForegroundColor White
    }
    finally {
        Write-Host "`n[PIPELINE TERMINADO]" -ForegroundColor DarkGray
        Read-Host "Presiona ENTER para cerrar la consola"
    }
}

# Entry Point
Convert-ImageFormat
