import json

def update_file(file_path, ts_path, var_name):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    ts_content = f"export const {var_name} = {json.dumps(content)};\n"
    
    with open(ts_path, 'w', encoding='utf-8') as f:
        f.write(ts_content)

update_file('webapp/index.html', 'worker/src/index_html.ts', 'INDEX_HTML')
update_file('webapp/phone.html', 'worker/src/phone_html.ts', 'PHONE_HTML')
update_file('webapp/install.html', 'worker/src/install_html.ts', 'INSTALL_HTML')
update_file('webapp/sw.js', 'worker/src/sw_js.ts', 'SW_JS')
