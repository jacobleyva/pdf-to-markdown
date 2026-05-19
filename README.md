# PDF to Markdown Converter

A CLI tool (and optional web UI) to convert PDF and DOCX files to Markdown, powered by [Docling](https://github.com/DS4SD/docling) (IBM open source) and [pandoc](https://pandoc.org/).

## Features

- Converts **PDF** files using Docling — handles both text-based and complex layouts
- Converts **DOCX** files using pandoc
- **Batch mode** — convert an entire folder at once, with manifest-based skip for already-converted files
- **Web UI** — optional FastAPI server with drag-and-drop interface

## Requirements

- Python 3.11–3.13 (Python 3.14+ is not yet supported — docling depends on PyTorch/torchvision, which do not have Python 3.14 wheels as of this writing)
- [pandoc](https://pandoc.org/installing.html) (for DOCX conversion)

### Installing pandoc

**macOS:**
```bash
brew install pandoc
```

**Linux — with Homebrew (recommended for immutable distros like Bazzite / Silverblue):**
```bash
brew install pandoc
```

**Linux — Fedora / RHEL:**
```bash
sudo dnf install pandoc
```

> **Note for immutable Fedora variants** (Bazzite, Silverblue, Kinoite): `dnf install` is not available for ad-hoc packages. Use Homebrew above, or layer with rpm-ostree (`sudo rpm-ostree install pandoc`, then reboot).

**Linux — Debian / Ubuntu:**
```bash
sudo apt-get install pandoc
```

**Linux — Arch:**
```bash
sudo pacman -S pandoc
```

For other platforms, see the [pandoc install page](https://pandoc.org/installing.html).

## Setup

**Quick setup (recommended):** use the included `install.sh` — it detects your OS, installs pandoc if needed, creates a Python venv, and installs all dependencies:

```bash
git clone <repo-url>
cd pdf-to-markdown
./install.sh
```

**Manual setup:**

```bash
git clone <repo-url>
cd pdf-to-markdown

python3 -m venv venv
source venv/bin/activate

pip install -r requirements.txt
```

Make the CLI executable:
```bash
chmod +x pdf2md
```

## Usage

### Single file

```bash
source venv/bin/activate

# PDF → Markdown (output: document.md)
./pdf2md document.pdf

# DOCX → Markdown
./pdf2md report.docx

# Specify output filename
./pdf2md document.pdf custom-output.md
```

### Batch mode

```bash
# Convert all PDFs and DOCXs in a folder (output goes to output/)
./pdf2md --batch input/

# Custom output folder
./pdf2md --batch input/ --output ~/my-docs/converted/

# Reconvert everything, ignoring the skip manifest
./pdf2md --batch input/ --force
```

Batch mode creates a `.pdf2md_manifest.json` in the output folder to track which files have already been converted. Subsequent runs skip unchanged files automatically.

### Web UI

```bash
source venv/bin/activate
./serve
```

Then open `http://localhost:8765` in your browser for a drag-and-drop interface.

## Optional: Add to PATH

```bash
# Add to ~/.zshrc or ~/.bashrc
export PATH="/path/to/pdf-to-markdown:$PATH"

# Then use from anywhere
pdf2md ~/Downloads/paper.pdf ~/Documents/paper.md
```

## Dependencies

| Package | Purpose |
|---|---|
| `docling` | PDF parsing and Markdown export |
| `fastapi` + `uvicorn` | Web UI server |
| `python-multipart` | File upload handling |
| `pandoc` (system) | DOCX conversion |

## Notes

- First run will download Docling's AI models (~1GB). Subsequent runs use the cached models.
- For image-based PDFs (scanned documents), install `ocrmypdf` and pre-process: `ocrmypdf --force-ocr input.pdf input-ocr.pdf`, then convert the OCR'd version.
