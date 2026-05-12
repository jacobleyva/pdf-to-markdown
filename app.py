#!/usr/bin/env python3
"""
PDF to Markdown Web UI
FastAPI server using Docling for PDF conversion.
"""

import asyncio
import io
import json
import re
import shutil
import subprocess
import tempfile
import uuid
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from docling.document_converter import DocumentConverter
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles

app = FastAPI(title="PDF to Markdown Converter")

# Per-job state: { job_id: { "files": [...], "progress": {...}, "done": bool } }
jobs: dict[str, dict] = {}
executor = ThreadPoolExecutor(max_workers=4)

STATIC_DIR = Path(__file__).parent / "static"
JOBS_DIR = Path(tempfile.gettempdir()) / "pdf2md_jobs"
JOBS_DIR.mkdir(exist_ok=True)

MAX_UPLOAD_BYTES = 50 * 1024 * 1024
MAX_UPLOAD_MB = MAX_UPLOAD_BYTES // (1024 * 1024)
_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
_PANDOC_PATH: str | None = None


def _validate_job_id(job_id: str) -> None:
    if not _UUID_RE.match(job_id):
        raise HTTPException(400, "Invalid job ID")


def _pandoc() -> str:
    global _PANDOC_PATH
    if _PANDOC_PATH is None:
        _PANDOC_PATH = shutil.which("pandoc")
        if not _PANDOC_PATH:
            raise RuntimeError(
                "pandoc not found. Install it with: brew install pandoc  (macOS) "
                "or: sudo apt install pandoc  (Debian/Ubuntu)"
            )
    return _PANDOC_PATH


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/", response_class=HTMLResponse)
async def index():
    return (STATIC_DIR / "index.html").read_text()


@app.post("/upload")
async def upload(files: list[UploadFile] = File(...)):
    """Accept one or more PDF/DOCX files, kick off conversion, return job_id."""
    job_id = str(uuid.uuid4())
    job_dir = JOBS_DIR / job_id
    job_dir.mkdir(parents=True)

    file_list = []
    for f in files:
        safe_name = Path(f.filename).name
        if not safe_name.lower().endswith((".pdf", ".docx")):
            raise HTTPException(400, f"{f.filename} is not a supported file type (PDF or DOCX)")

        content = await f.read()
        if len(content) > MAX_UPLOAD_BYTES:
            raise HTTPException(413, f"{f.filename} exceeds {MAX_UPLOAD_MB} MB limit")

        dest = job_dir / safe_name
        dest.write_bytes(content)
        file_list.append(safe_name)

    jobs[job_id] = {
        "files": file_list,
        "progress": {name: {"status": "pending", "pct": 0, "error": None} for name in file_list},
        "done": False,
    }

    loop = asyncio.get_running_loop()
    loop.run_in_executor(executor, _convert_job, job_id, job_dir)

    return {"job_id": job_id, "files": file_list}


def _convert_job(job_id: str, job_dir: Path):
    """Run conversion for every file in the job directory (runs in thread pool)."""
    job = jobs[job_id]
    converter = DocumentConverter()
    for filename in job["files"]:
        pdf_path = job_dir / filename
        md_path = job_dir / Path(filename).with_suffix(".md").name
        prog = job["progress"][filename]
        try:
            prog["status"] = "converting"
            prog["pct"] = 10

            suffix = Path(filename).suffix.lower()
            if suffix == ".pdf":
                prog["pct"] = 20
                result = converter.convert(str(pdf_path))
                md_text = result.document.export_to_markdown()
                prog["pct"] = 90
                md_path.write_text(md_text, encoding="utf-8")
            elif suffix == ".docx":
                prog["pct"] = 20
                sp = subprocess.run(
                    [_pandoc(), str(pdf_path), "-o", str(md_path),
                     "--wrap=none", "--markdown-headings=atx"],
                    capture_output=True, text=True
                )
                if sp.returncode != 0:
                    raise RuntimeError(f"pandoc failed: {sp.stderr}")
                prog["pct"] = 90
                md_text = md_path.read_text(encoding="utf-8")
            else:
                raise ValueError(f"Unsupported file type: {suffix}")

            prog["status"] = "done"
            prog["pct"] = 100
            prog["chars"] = len(md_text)
            prog["output"] = md_path.name
        except Exception as exc:
            prog["status"] = "error"
            prog["error"] = str(exc)

    job["done"] = True


@app.get("/progress/{job_id}")
async def progress(job_id: str):
    """Server-Sent Events stream for conversion progress."""
    _validate_job_id(job_id)
    if job_id not in jobs:
        raise HTTPException(404, "Job not found")

    async def event_stream():
        while True:
            job = jobs.get(job_id)
            if not job:
                break
            data = json.dumps({"progress": job["progress"], "done": job["done"]})
            yield f"data: {data}\n\n"
            if job["done"]:
                break
            await asyncio.sleep(0.4)

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@app.get("/download/{job_id}/{filename}")
async def download_file(job_id: str, filename: str):
    """Download a single converted .md file."""
    _validate_job_id(job_id)
    safe_name = Path(filename).name
    file_path = (JOBS_DIR / job_id / safe_name).resolve()
    if not file_path.is_relative_to((JOBS_DIR / job_id).resolve()):
        raise HTTPException(404, "File not found")

    if not file_path.exists() or file_path.suffix != ".md":
        raise HTTPException(404, "File not found")
    return FileResponse(str(file_path), media_type="text/markdown", filename=safe_name)


@app.get("/download-all/{job_id}")
async def download_all(job_id: str):
    """Download all converted .md files as a ZIP archive."""
    _validate_job_id(job_id)
    job_dir = JOBS_DIR / job_id
    if not job_dir.exists():
        raise HTTPException(404, "Job not found")

    md_files = list(job_dir.glob("*.md"))
    if not md_files:
        raise HTTPException(404, "No converted files found")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in md_files:
            zf.write(f, f.name)
    buf.seek(0)

    return StreamingResponse(
        buf,
        media_type="application/zip",
        headers={"Content-Disposition": "attachment; filename=converted.zip"},
    )


@app.delete("/job/{job_id}")
async def delete_job(job_id: str):
    """Clean up job files."""
    _validate_job_id(job_id)
    job_dir = JOBS_DIR / job_id
    if job_dir.exists():
        shutil.rmtree(job_dir)
    jobs.pop(job_id, None)
    return {"ok": True}
