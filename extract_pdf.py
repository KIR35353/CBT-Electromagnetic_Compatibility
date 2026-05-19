import pdfplumber

pdf_path = r'C:\S2L_Dev\CBT-EMI_EMC\CBT-Electromagnetic_Compatibility\Danfoss Motor and Drive Text.pdf'
output_path = r'C:\S2L_Dev\CBT-EMI_EMC\CBT-Electromagnetic_Compatibility\section6_text2.txt'

# Section 6 spans pages 133-152 per TOC, section 7 starts at 153
# PDF index = page number - 1 (0-based)
with pdfplumber.open(pdf_path) as pdf:
    with open(output_path, 'w', encoding='utf-8') as out:
        for i in range(145, 153):  # pages 146-153 (0-indexed)
            if i >= len(pdf.pages):
                break
            text = pdf.pages[i].extract_text() or ''
            out.write(f"\n{'='*60}\n")
            out.write(f"=== PDF PAGE {i+1} ===\n")
            out.write(f"{'='*60}\n")
            out.write(text + "\n")
    print(f"Done - written to {output_path}")
