# UAS Report DOCX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an editable Indonesian DOCX report for Kelompok 6's Noted UAS mobile application project.

**Architecture:** Build the document with a small Python `python-docx` script using deterministic styles, tables, cover metadata, and screenshot placeholders. Render the DOCX to PNG pages with the Documents skill renderer, inspect the pages, and iterate until the layout is clean.

**Tech Stack:** Python, `python-docx`, bundled Codex document runtime, LibreOffice/Poppler renderer from the Documents skill, existing Noted project source files.

---

## File Map

- Create: `tools/build_uas_report.py`
  - Generates the DOCX report with fixed content, styles, tables, links, and placeholders.
- Create: `deliverables/Laporan_UAS_Noted_Kelompok_6.docx`
  - Final editable UAS report.
- Create: `deliverables/rendered-report/`
  - Internal render QA PNGs and optional PDF, not intended as final deliverable.
- Read: `docs/superpowers/specs/2026-06-15-uas-report-design.md`
  - Approved report design.
- Read: `docs/IMPLEMENTATION_LOG.md`
  - Verification and implementation evidence.
- Read: `README.md`
  - Public-facing project summary and links.
- Read: `pubspec.yaml`
  - Package list.

## Task 1: Prepare Document Guidance

**Files:**
- Read: `C:/Users/sangh/.codex/plugins/cache/openai-primary-runtime/documents/26.614.11602/skills/documents/references/design_presets.md`
- Read: `C:/Users/sangh/.codex/plugins/cache/openai-primary-runtime/documents/26.614.11602/skills/documents/references/header_templates.md`

- [ ] **Step 1: Choose design preset**

Use `standard_business_brief` because the report is a formal university project report that still benefits from polished section hierarchy, tables, and restrained accent color.

- [ ] **Step 2: Choose header approach**

Use a simple academic cover page followed by normal report pages with footer page numbers. Do not over-design the cover.

## Task 2: Create DOCX Builder Script

**Files:**
- Create: `tools/build_uas_report.py`
- Output: `deliverables/Laporan_UAS_Noted_Kelompok_6.docx`

- [ ] **Step 1: Create the script skeleton**

Use the bundled Python runtime and `python-docx`. The script must:

```python
from pathlib import Path
from docx import Document

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "deliverables" / "Laporan_UAS_Noted_Kelompok_6.docx"
OUT.parent.mkdir(exist_ok=True)

doc = Document()
doc.save(OUT)
```

- [ ] **Step 2: Add document styles**

Define a restrained style system:

```python
FONT = "Arial"
ACCENT = "6A9C89"
TEXT = "2F2F2F"
MUTED = "666666"
LIGHT_FILL = "F8F7F2"
TABLE_HEADER = "E7F0EC"
```

Set US Letter page size, 1 inch margins, Arial body text, green heading accents, clear table header fills, and readable paragraph spacing.

- [ ] **Step 3: Add cover page**

Include:

```text
UNIVERSITAS TELKOM
KAMPUS JAKARTA
Laporan Project UAS Aplikasi Perangkat Bergerak
NOTED
Kelompok 6
S1IT-KJ-23-001
Dosen: Demi Adidrana
Mata Kuliah: Aplikasi Perangkat Bergerak
```

Add a note line for the Telkom logo placeholder if no official Telkom logo file is available:

```text
[Logo Universitas Telkom]
```

Then list all team members and NIMs.

- [ ] **Step 4: Add report body sections**

Create these sections with Indonesian prose:

```text
Kata Pengantar
Pendahuluan
Tujuan Aplikasi
Pembagian Tugas Kelompok
Arsitektur Aplikasi
Package dan Teknologi yang Digunakan
Alasan Pemilihan Firebase dan Provider
Fitur dan Output Aplikasi
Pengujian
Link Project, APK, dan Showcase
Kesimpulan
```

- [ ] **Step 5: Add required tables**

Create tables for:

```text
1. Anggota kelompok
2. Pembagian tugas
3. Package pubspec.yaml
4. Fitur aplikasi
5. Pengujian dan hasil
6. Link lampiran
```

- [ ] **Step 6: Add screenshot placeholders**

In the "Fitur dan Output Aplikasi" section, add clear placeholders:

```text
[Screenshot 1 - Welcome / Sign In]
[Screenshot 2 - Dashboard]
[Screenshot 3 - Notes List]
[Screenshot 4 - Add/Edit Note]
[Screenshot 5 - Note Detail]
[Screenshot 6 - Favorites]
[Screenshot 7 - Profile]
[Screenshot 8 - Connections]
```

Each placeholder should be inside a light bordered box so screenshots can be inserted later without breaking the structure.

## Task 3: Generate The DOCX

**Files:**
- Run: `tools/build_uas_report.py`
- Output: `deliverables/Laporan_UAS_Noted_Kelompok_6.docx`

- [ ] **Step 1: Run builder**

```powershell
C:\Users\sangh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tools\build_uas_report.py
```

Expected output:

```text
Created deliverables\Laporan_UAS_Noted_Kelompok_6.docx
```

- [ ] **Step 2: Inspect DOCX package**

Confirm the file exists and is non-empty:

```powershell
Get-ChildItem deliverables\Laporan_UAS_Noted_Kelompok_6.docx
```

Expected: DOCX file exists with size greater than 0 bytes.

## Task 4: Render And Verify Layout

**Files:**
- Input: `deliverables/Laporan_UAS_Noted_Kelompok_6.docx`
- Output: `deliverables/rendered-report/page-*.png`

- [ ] **Step 1: Render DOCX**

```powershell
C:\Users\sangh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe C:\Users\sangh\.codex\plugins\cache\openai-primary-runtime\documents\26.614.11602\skills\documents\render_docx.py deliverables\Laporan_UAS_Noted_Kelompok_6.docx --output_dir deliverables\rendered-report --emit_pdf
```

Expected: PNG pages appear in `deliverables/rendered-report/`.

- [ ] **Step 2: Visually inspect rendered pages**

Open every `page-*.png` with the image viewer tool and check:

```text
No clipped text
No overlapping tables
No broken headings
No huge accidental blank gaps
Placeholder boxes are readable
Links are visible
Cover metadata is complete
```

- [ ] **Step 3: Iterate if needed**

If any page has layout defects, edit `tools/build_uas_report.py`, regenerate the DOCX, rerender, and reinspect.

## Task 5: Final Verification And Handoff

**Files:**
- Final: `deliverables/Laporan_UAS_Noted_Kelompok_6.docx`

- [ ] **Step 1: Verify final file**

```powershell
Get-ChildItem deliverables\Laporan_UAS_Noted_Kelompok_6.docx
```

Expected: final DOCX exists and is non-empty.

- [ ] **Step 2: Check git status**

```powershell
git status --short
```

Expected: builder script and deliverable may be uncommitted unless the user asks to commit them.

- [ ] **Step 3: Final response**

Report:

```text
Created DOCX path
Whether render QA passed
Any manual placeholders remaining, especially Telkom logo and showcase link
```

Only link the DOCX as the deliverable unless the user asks for internal render artifacts.

