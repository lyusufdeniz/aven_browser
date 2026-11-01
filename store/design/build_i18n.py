# Bundles store/design/i18n/<code>.json into i18n/i18n.js for studio.html (file:// cannot fetch JSON).
import json, glob, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
data = {}
for f in sorted(glob.glob('i18n/*.json')):
    code = os.path.basename(f)[:-5]
    if code.startswith('_'):
        continue
    data[code] = json.load(open(f, encoding='utf-8'))
open('i18n/i18n.js', 'w', encoding='utf-8').write('window.I18N = ' + json.dumps(data, ensure_ascii=False) + ';\n')
print('languages:', ' '.join(data))
