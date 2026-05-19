import json

path = r'C:\S2L_Dev\CBT-EMI_EMC\CBT-Electromagnetic_Compatibility\CBT_Template_Files\_course_manifest.json'
with open(path, encoding='utf-8') as f:
    data = json.load(f)

print('JSON valid')
print(f'Course: {data["course"]["id"]} — {data["course"]["title"]}')
print(f'Sections: {len(data["sections"])}')
for s in data["sections"]:
    screens = len(s["screens"])
    pool = len(s["quiz"]["pool"])
    print(f'  S{s["num"]}: {s["title"]} — {screens} screens, {pool} quiz pool questions')
print(f'Summary screens: {len(data["summary"]["screens"])}')
print(f'Exam questions: {len(data["exam"]["questions"])}')
print(f'q_section_map length: {len(data["exam"]["q_section_map"])}')
print(f'Objectives: {len(data["intro"]["objectives"])}')
