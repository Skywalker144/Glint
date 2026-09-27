import csv
import hashlib
import json
from pathlib import Path
import sqlite3
import unicodedata
import urllib.request

root = Path(__file__).resolve().parents[1]
resources = root / 'src-tauri/resources'
revision = 'bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b'
source = resources / 'ecdict.csv'
if not source.exists():
    urllib.request.urlretrieve(f'https://raw.githubusercontent.com/skywind3000/ECDICT/{revision}/ecdict.csv', source)
if hashlib.sha256(source.read_bytes()).hexdigest() != '1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf':
    raise ValueError('ECDICT checksum mismatch')


def normalize(value):
    return ' '.join(unicodedata.normalize('NFKC', value).lower().split())


destination = resources / 'dictionary.sqlite'
staging = destination.with_suffix('.building')
staging.unlink(missing_ok=True)
connection = sqlite3.connect(staging)
connection.executescript('''
CREATE TABLE entries (key TEXT PRIMARY KEY, word TEXT NOT NULL, phonetic TEXT NOT NULL, translation TEXT NOT NULL, definition TEXT NOT NULL);
CREATE TABLE forms (form TEXT NOT NULL, lemma TEXT NOT NULL, relation TEXT NOT NULL, pure INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(form,lemma,relation));
''')
labels = {'p': '过去式', 'd': '过去分词', 'i': '现在分词', '3': '第三人称单数', 'r': '比较级', 't': '最高级', 's': '复数'}
with source.open(encoding='utf-8-sig', newline='') as stream:
    for row in csv.DictReader(stream):
        key = normalize(row['word'])
        if not key or not (row['translation'] or row['definition']):
            continue
        connection.execute('INSERT OR REPLACE INTO entries VALUES (?,?,?,?,?)', [key, row['word'], row['phonetic'], row['translation'].replace('\\n', '\n'), row['definition'].replace('\\n', '\n')])
        changes = dict(part.split(':', 1) for part in row['exchange'].split('/') if ':' in part)
        for kind, values in changes.items():
            if kind in labels:
                for value in values.split(','):
                    form = normalize(value)
                    if form and form != key:
                        connection.execute('INSERT OR IGNORE INTO forms VALUES (?,?,?,0)', (form, key, labels[kind]))
        for lemma in changes.get('0', '').split(','):
            lemma = normalize(lemma)
            if lemma and lemma != key:
                relation = '、'.join(labels[kind] for kind in changes.get('1', '') if kind in labels) or '词形关系'
                connection.execute('INSERT OR IGNORE INTO forms VALUES (?,?,?,0)', (key, lemma, relation))
for form, review in json.loads((resources / 'lexical-review.json').read_text()).items():
    connection.execute('DELETE FROM forms WHERE form=? AND lemma=?', (form, review['lemma']))
    connection.execute('INSERT INTO forms VALUES (?,?,?,?)', (form, review['lemma'], review['relation'], review['pure']))
connection.commit()
print(f"Built {connection.execute('SELECT count(*) FROM entries').fetchone()[0]} entries")
connection.close()
staging.replace(destination)
