# Desktop Image Converter

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://microsoft.com/powershell)
[![.NET](https://img.shields.io/badge/.NET-System.Drawing-purple.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

A high-performance, robust PowerShell pipeline for batch image conversion. Engineered with a focus on memory safety, execution stability, and seamless user experience, this tool leverages native `.NET` libraries to process graphic files without external dependencies.

## 🚀 Core Architecture & Features

This pipeline was designed to handle large volumes of design assets and textures reliably, avoiding common pitfalls in standard script-based conversions:

* **Memory-Safe Processing:** Utilizes `System.IO.MemoryStream` to isolate source files from the `System.Drawing.Bitmap` object. This prevents native GDI+ file-locking issues, ensuring files are not corrupted or locked by the OS during batch operations.
* **Heuristic Autodetection:** Features an intelligent scanning mode that automatically parses the target directory for supported graphic formats, streamlining the workflow when dealing with mixed-extension asset folders.
* **Anti-Collision Logic:** Implements strict validation to prevent redundant processing (e.g., attempting to convert a PNG to a PNG). The script automatically filters out files that already match the target output format, saving CPU cycles and preventing I/O access denial.
* **ASCII-Safe Design:** The codebase is entirely stripped of special characters and diacritics to guarantee absolute stability against `ParserError` crashes caused by UTF-8/ANSI encoding mismatches in standard Windows PowerShell 5.1 environments.
* **Dynamic Path Management:** Enforces directory integrity checks before execution. It allows users to safely map output files to the source directory or dynamically create new target infrastructures on the fly.

## 🧰 Supported Formats

The tool natively supports bilateral conversion between the following formats:
* `.BMP`
* `.JPG` / `.JPEG`
* `.PNG`
* `.GIF`
* `.TIFF`

## ⚙️ Installation

Clone the repository to your local machine:

```bash
git clone [https://github.com/javilesm/Desktop_Image_Converter.git](https://github.com/javilesm/Desktop_Image_Converter.git)
```
## 🛠️ Usage
This tool is designed to be executed interactively. The console UI will guide you through the process, minimizing input errors.

Open an elevated Windows PowerShell or Windows Terminal session.

Navigate to the directory containing the script.

Execute the pipeline: .\Convert-ImageFormat.ps1 or just Right Click and "Run with Powershell".

## Execution Flow:
Source Input: Provide the absolute path to the directory containing your images.

Input Format: Select the format you wish to convert from the menu, or select [A] to let the heuristic engine detect all convertible files.

Output Format: Select the desired target format.

Destination: Choose to output files in the same directory or specify/create a new output path.

A detailed telemetry report will be displayed upon completion, breaking down successful operations and any anomalies encountered.

## 💻 System Requirements
Windows OS

Windows PowerShell 5.1 or later

Execution Policy configured to allow local scripts (Set-ExecutionPolicy RemoteSigned or executed via -ExecutionPolicy Bypass)

Developed and maintained by javilesm
