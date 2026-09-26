import csv
import gzip
import hashlib
import json
import pathlib
import shutil
import sys
import unicodedata

revision = 'bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b'
source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(__file__).resolve().parents[1] / 'src/main/data/ecdict'
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
if source_hash != '1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf':
    raise ValueError('ECDICT source does not match the pinned revision')
destination.mkdir(parents=True, exist_ok=True)
fields = ['word', 'phonetic', 'definition', 'translation', 'tag', 'exchange']
entries = {}


def normalize(text):
    return ' '.join(unicodedata.normalize('NFKC', text).strip().lower().split())


with source.open(encoding='utf-8-sig', newline='') as stream:
    for row in csv.DictReader(stream):
        key = normalize(row['word'])
        if not key or not (row['translation'] or row['definition']):
            continue
        if key not in entries or row['word'] == key:
            entries[key] = {field: row[field].replace('\\n', '\n') for field in fields if row[field]}

aliases = {}
for key, entry in entries.items():
    for change in entry.get('exchange', '').split('/'):
        kind, separator, values = change.partition(':')
        if separator and kind in ['p', 'd', 'i', '3', 'r', 't', 's']:
            for value in values.split(','):
                alias = normalize(value)
                if alias and alias not in entries:
                    aliases.setdefault(alias, key)

shards = [{} for _ in range(32)]
for key, entry in sorted({**entries, **aliases}.items()):
    bucket = hashlib.sha256(key.encode()).digest()[0] % len(shards)
    shards[bucket][key] = entry
for index, shard in enumerate(shards):
    payload = json.dumps(shard, ensure_ascii=False, separators=(',', ':')).encode()
    (destination / f'{index:02d}.json.gz').write_bytes(gzip.compress(payload, mtime=0))
shutil.copyfile(source.with_name('LICENSE'), destination / 'LICENSE')
metadata = {
    'name': 'ECDICT',
    'url': 'https://github.com/skywind3000/ECDICT',
    'revision': revision,
    'sha256': source_hash,
    'entries': len(entries),
    'aliases': len(aliases),
    'shards': len(shards),
}
(destination / 'manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
print(json.dumps(metadata, indent=2))
