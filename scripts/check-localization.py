#!/usr/bin/env python3
"""Validate native catalogs, format arguments and Swift compiler extraction coverage."""
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parent.parent
derived = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/LocalizationBuild'
token = re.compile(r'%(?:(\d+)\$)?[-+#0 ]*\d*(?:\.\d+)?(ll|l|h|hh|z|t|j)?([diuoxXfFeEgGaAcsp@])')

def arguments(value):
    # Ignore escaped percent signs, but preserve argument position and type.
    values = []
    for index, match in enumerate(token.finditer(value.replace('%%', ''))):
        values.append((int(match[1] or index + 1), (match[2] or '') + match[3]))
    return Counter(values)

def units(value):
    if 'stringUnit' in value:
        yield value['stringUnit']
    for kind in value.get('variations', {}).values():
        for variation in kind.values():
            yield from units(variation)

def check_catalog(path):
    catalog = json.loads(path.read_text())
    assert catalog['sourceLanguage'] == 'en', path
    for key, entry in catalog['strings'].items():
        if entry.get('shouldTranslate') is False:
            continue  # Explicitly invariant product names / copyright, also excluded by Xcode.
        assert set(entry['localizations']) == {'en', 'de'}, (path, key)
        for language, localization in entry['localizations'].items():
            translated = list(units(localization))
            assert translated, (path, key, language)
            for unit in translated:
                assert unit['state'] == 'translated' and unit['value'], (path, key, language)
                assert arguments(unit['value']) == arguments(key), (path, key, language, unit['value'])
    return {key for key, entry in catalog['strings'].items() if entry.get('shouldTranslate') is not False}

app_keys = check_catalog(root / 'Snaprivo/Resources/Localizable.xcstrings')
info_keys = check_catalog(root / 'Snaprivo/Resources/InfoPlist.xcstrings')
domain = {}
for language in ['de', 'en']:
    path = root / f'Packages/SnagForgeDomain/Sources/SnagForgeDomain/Resources/{language}.lproj/Localizable.strings'
    data = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], check=True, capture_output=True, text=True)
    domain[language] = json.loads(data.stdout)
    for key, value in domain[language].items():
        assert arguments(key) == arguments(value), (path, key)
assert domain['de'].keys() == domain['en'].keys()

# Old archives in the same DerivedData directory are not part of the current build.
files = [path for path in (derived / 'Build/Intermediates.noindex').rglob('*.stringsdata')
         if 'ArchiveIntermediates' not in path.parts]
assert files, f'No compiler extraction found. Run ./scripts/build.sh -derivedDataPath "{derived}" first.'
for path in files:
    data = json.loads(path.read_text())
    keys = {entry['key'] for entry in data.get('tables', {}).get('Localizable', [])}
    expected = domain['en'].keys() if '/Packages/SnagForgeDomain/' in data.get('source', '') else app_keys
    missing = keys - expected
    assert not missing, (data.get('source'), sorted(missing))
print(f'Localization catalogs passed: {len(app_keys)} app + {len(info_keys)} InfoPlist + {len(domain["en"])} domain strings in English/German; complete compiler coverage and matching format arguments.')
