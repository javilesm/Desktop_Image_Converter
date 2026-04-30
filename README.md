# Desktop Image Converter

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://microsoft.com/powershell)
[![.NET](https://img.shields.io/badge/.NET-System.Drawing-purple.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

**Desktop Image Converter** is a high-performance, industrial-grade PowerShell pipeline designed for high-volume batch image processing. Engineered for professionals who require absolute stability, it leverages native `.NET` libraries to ensure memory safety and execution integrity without the overhead of external dependencies.

---

## 🚀 Core Architecture & Features

This pipeline was designed to handle large volumes of design assets and textures reliably, avoiding common pitfalls in standard script-based conversions:

* **Memory-Safe Processing:** Utilizes `System.IO.MemoryStream` to isolate source files from the `System.Drawing.Bitmap` object. This prevents native GDI+ file-locking issues, ensuring files are not corrupted or locked by the OS during batch operations.
* **Heuristic Autodetection:** Features an intelligent scanning mode that automatically parses the target directory for supported graphic formats, streamlining the workflow when dealing with mixed-extension asset folders.
* **Anti-Collision Logic:** Implements strict validation to prevent redundant processing (e.g., attempting to convert a PNG to a PNG). The script automatically filters out files that already match the target output format, saving CPU cycles and preventing I/O access denial.
* **ASCII-Safe Design:** The codebase is entirely stripped of special characters and diacritics to guarantee absolute stability against `ParserError` crashes caused by UTF-8/ANSI encoding mismatches in standard Windows PowerShell 5.1 environments.
* **Dynamic Path Management:** Enforces directory integrity checks before execution. It allows users to safely map output files to the source directory or dynamically create new target infrastructures on the fly.

---

## 🧰 Supported Formats

The pipeline supports full bilateral conversion between:
*   **Lossless:** `.PNG`, `.BMP`, `.TIFF`
*   **Compressed:** `.JPG` / `.JPEG`, `.GIF`

---

## ⚙️ Installation

Clone the repository to your local machine:

```bash
git clone [https://github.com/javilesm/Desktop_Image_Converter.git](https://github.com/javilesm/Desktop_Image_Converter.git)
```

---

## 🛠️ Operational Workflow
This tool is designed for interactive use with a focus on minimizing input friction.
1. Open an elevated Windows PowerShell or Windows Terminal session.
2. Navigate to the script's directory.
3. Execute the pipeline via:
  - Direct Command: .\Convert-ImageFormat.ps1
  - Shell Integration: Right-click the file and select "Run with PowerShell".

* **Execution Pipeline: **
- Step 1: Source Ingest: Provide the absolute path (Directory or Single File).
- Step 2: Input Selection: Define the source format or trigger the Heuristic Autodetect [A].
- Step 3: Target Format: Define the desired output extension.
- Step 4: Destination Mapping: Select the same directory or specify a new target path.
- Step 5: Telemetry: Review the final structured report detailing successful conversions and any anomalies.

---

## 📺 Demonstration
Experience the workflow in action:

[![Watch the Demo](https://img.shields.io/badge/YouTube-Watch%20Example%20Usage-red?style=for-the-badge&logo=youtube)](https://youtu.be/gDs7XSnMX2g)

---

## 💻 System Requirements
- OS: Windows 10/11
- Runtime: Windows PowerShell 5.1 or PowerShell Core.
- Policy: Execution Policy must allow local scripts (Set-ExecutionPolicy RemoteSigned).

---

## Development
Developed and maintained by [![javilesm](https://javilesm.github.io)]()
