# Quick Start Guide

## Setup (One-Time)

```bash
cd /path/to/pdf-to-markdown
source venv/bin/activate
```

## Basic Usage

```bash
# Convert a single PDF
./pdf2md input.pdf output.md

# Auto-name output file
./pdf2md input.pdf

# Convert ALL PDFs in a folder (batch mode)
./pdf2md --batch input/
```

## Common Commands

```bash
# Activate environment
source venv/bin/activate

# Deactivate environment
deactivate

# Reinstall dependencies
pip install -r requirements.txt

# Test with sample
./pdf2md input/test.pdf output/test.md
```

## File Structure

- `input/` - Put your PDFs here
- `output/` - Converted markdown files appear here
- `pdf2md` - The converter script
- `venv/` - Python environment (don't touch!)

## Troubleshooting

**"Command not found"**
- Did you activate the virtual environment? `source venv/bin/activate`

**"No such file or directory"**
- Check your file paths are correct
- Use `ls input/` to see available PDFs

**"Import error"**
- Run `pip install -r requirements.txt`

---

**Need help?** Read the full [README.md](README.md)
