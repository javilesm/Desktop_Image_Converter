# Desktop Image Converter

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://microsoft.com/powershell)
[![ImageSharp](https://img.shields.io/badge/SixLabors.ImageSharp-3.x-purple.svg)](https://github.com/SixLabors/ImageSharp)
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

**Desktop Image Converter** is a PowerShell pipeline for single-file and batch image conversion. It auto-downloads its only dependency ([SixLabors.ImageSharp](https://github.com/SixLabors/ImageSharp)) from NuGet at first run, then validates paths, enforces file-size limits, and produces a structured conversion report.

---

## Features

- **Auto-managed dependency** — downloads and caches `SixLabors.ImageSharp` from NuGet on first run; resolves the latest stable version automatically unless a version is pinned in the script header.
- **Single-file and batch modes** — pass a file path to convert one image, or a directory to process all matching files at once.
- **Heuristic autodetect** — in batch mode, option `[A]` scans the directory for any supported image format and converts everything in one pass.
- **Path safety** — rejects path traversal (`../`), remote UNC paths, and shell-injection characters before any file is touched.
- **File-size guard** — skips files exceeding the configured limit (default 200 MB) and reports them separately, preventing out-of-memory crashes on large assets.
- **Anti-collision logic** — excludes files whose extension already matches the target format so no redundant I/O occurs.
- **Safe output directory creation** — asks for explicit confirmation before creating a new destination directory.
- **Clean error messages** — exceptions are caught per-file, directory paths are redacted from the output, and processing continues with the remaining files.

---

## Supported formats

| Category | Formats |
|---|---|
| JPEG family | `.jpg` `.jpeg` `.jfif` |
| Lossless | `.png` `.bmp` `.tiff` |
| Animated / other | `.gif` `.webp` |

All combinations are bidirectional.

---

## Requirements

| | |
|---|---|
| OS | Windows 10 / 11 |
| PowerShell | 5.1 or PowerShell 7+ |
| .NET | Framework 4.7.2+ or .NET 6+ (bundled with PS 7) |
| Internet | Required on first run to download ImageSharp from NuGet |
| Execution policy | `RemoteSigned` or `Bypass` — see [Installation](#installation) |

---

## Installation

```bash
git clone https://github.com/javilesm/Desktop_Image_Converter.git
cd Desktop_Image_Converter
```

Allow local scripts if not already set (run PowerShell as Administrator):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

No further setup needed. Dependencies are downloaded automatically on first run.

---

## Usage

```powershell
# Interactive (prompts for all options)
.\Convert-Image.ps1

# Provide the source path directly
.\Convert-Image.ps1 -Path "C:\Assets"
.\Convert-Image.ps1 -Path "C:\Assets\photo.webp"

# Override defaults
.\Convert-Image.ps1 -Path "C:\Assets" -MaxFileSizeMB 500
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Path` | _(prompted)_ | File or directory to convert |
| `-MaxFileSizeMB` | `200` | Files larger than this are skipped (1–10240) |
| `-MaxConcurrent` | `4` | Reserved for future parallel processing (PS 7+) |

### Interactive workflow

```
[>] Ruta origen: C:\Assets

:: Formato de entrada ::
  [1] JPG  [2] JPEG  [3] JFIF  [4] PNG  [5] BMP  [6] GIF  [7] TIFF  [8] WEBP
  [A] AUTO (detectar extensión)

:: Formato de salida ::
  [1] JPG  [2] PNG  [3] BMP  ...

:: Directorio de salida ::
  [1] Mismo directorio de origen
  [2] Especificar nueva ruta
```

After processing, a summary table is printed:

```
═══ Resultado de conversión ═══
  Formato:   WEBP → JPG
  Destino:   C:\Assets
  OK:        42
  FAIL:      1

Source          Dest          SizeMB  Status
------          ----          ------  ------
banner.webp     banner.jpg      0.31  OK
corrupted.webp  ---             0.01  FAIL
```

---

## Pinning a dependency version

By default the script resolves the latest stable ImageSharp release from NuGet. To lock to a specific version, edit the `$NUGET_PACKAGES` block near the top of the script:

```powershell
$NUGET_PACKAGES = @(
    @{ Name = 'SixLabors.ImageSharp'; Version = '3.1.4' }
)
```

Set `Version = $null` to revert to automatic resolution.

---

## Demo

[![Watch the Demo](https://img.shields.io/badge/YouTube-Watch%20Example%20Usage-red?style=for-the-badge&logo=youtube)](https://youtu.be/gDs7XSnMX2g)

---

## Development

Developed and maintained by [![javilesm](https://img.shields.io/badge/github-javilesm-blue?logo=github)](https://javilesm.github.io)
