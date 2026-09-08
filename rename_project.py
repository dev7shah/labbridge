import os
import re

ignore_dirs = {'.git', 'node_modules', 'build', '.dart_tool', '.wrangler', '.symlinks', '.gemini'}

def replace_in_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        return

    orig = content
    content = re.sub(r'CueFlex', 'DocTransit', content)
    content = re.sub(r'cueflex', 'doctransit', content)
    content = re.sub(r'CUEFLEX', 'DOCTRANSIT', content)
    content = re.sub(r'Cueflex', 'DocTransit', content)

    if orig != content:
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"Updated {filepath}")
        except Exception as e:
            print(f"Error writing to {filepath}: {e}")

for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ignore_dirs]
    for file in files:
        if file == 'rename_project.py' or file.endswith(('.png', '.jpg', '.jpeg', '.gif', '.zip', '.apk', '.ico', '.so', '.a')):
            continue
        filepath = os.path.join(root, file)
        replace_in_file(filepath)

print("Done")
