bash <<'MISS_DEMEANOR_R030'
set -Eeuo pipefail
python3 - <<'PYTHON_RELAY_BOOTSTRAP'
import base64, hashlib, io, json, os, subprocess, sys, tempfile, urllib.request
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

OWNER = 'monicamidnight'
REPO = 'Miss.Demeanor'
REMOTE_PATH = 'relay/MISS.DEMEANOR.0030.zip.b64'
FILENAME = 'MISS.DEMEANOR.0030.zip'
EXPECTED_SHA256 = 'cd6286f2d03c2ab92b54932570d085eab61fd06862952d85330c592843446d5f'

def stop(message):
    raise SystemExit('MISS DEMEANOR RELAY ERROR: ' + message)

def existing_token():
    try:
        p = subprocess.run(['gh', 'auth', 'token'], capture_output=True, text=True,
                           timeout=8, check=False)
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        pass
    try:
        env = dict(os.environ, GIT_TERMINAL_PROMPT='0')
        p = subprocess.run(['git', 'credential', 'fill'],
                           input='protocol=https\nhost=github.com\n\n',
                           capture_output=True, text=True, timeout=8, env=env)
        if p.returncode == 0:
            for line in p.stdout.splitlines():
                if line.startswith('password=') and line[9:]:
                    return line[9:]
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        pass
    stop('No existing GitHub CLI or Git credential found. Nothing executed; authenticate first.')

def main():
    token = existing_token()
    url = f'https://api.github.com/repos/{OWNER}/{REPO}/contents/{REMOTE_PATH}?ref=main'
    req = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Phantomtronics-MissDemeanor-R030-Relay'
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.load(response)
        if result.get('type') != 'file' or result.get('encoding') != 'base64':
            stop('Unexpected private GitHub content response.')
        encoded_zip = base64.b64decode(result['content']).decode('ascii').strip()
        raw_zip = base64.b64decode(encoded_zip, validate=True)
    except Exception as error:
        stop('Authenticated download failed; no code executed. ' + type(error).__name__)
    if hashlib.sha256(raw_zip).hexdigest() != EXPECTED_SHA256:
        stop('PINNED SHA-256 MISMATCH. Wrong, stale or corrupted archive. Nothing executed.')
    try:
        with ZipFile(io.BytesIO(raw_zip)) as archive:
            members = archive.namelist()
            if len(members) != len(set(members)) or archive.testzip() is not None:
                stop('Duplicate or corrupted ZIP members.')
            for info in archive.infolist():
                path = PurePosixPath(info.filename)
                if (path.is_absolute() or '..' in path.parts or '\\' in info.filename
                    or ((info.external_attr >> 16) & 0o170000) == 0o120000):
                    stop('Unsafe ZIP entry. Nothing executed.')
            manifest = json.loads(archive.read('CONTENT_SHA256.json'))['members']
            if set(manifest) != set(members) - {'CONTENT_SHA256.json'}:
                stop('Incomplete member manifest. Nothing executed.')
            for name, digest in manifest.items():
                if hashlib.sha256(archive.read(name)).hexdigest() != digest:
                    stop('Archive content hash mismatch. Nothing executed.')
            config = json.loads(archive.read('RELAY.CONFIG.json'))
            if (config.get('agent_slug') != 'MISS.DEMEANOR'
                or config.get('revision') != '0030'
                or config.get('filename') != FILENAME):
                stop('Wrong agent or revision. Nothing executed.')
            if members.count('RUN.sh') != 1:
                stop('Missing/duplicate RUN.sh. Nothing executed.')
            runner = archive.read('RUN.sh')
    except Exception as error:
        stop('ZIP verification failed; nothing executed. ' + type(error).__name__)
    downloads = Path.home() / 'Downloads'
    downloads.mkdir(parents=True, exist_ok=True)
    target = downloads / FILENAME
    if target.is_symlink():
        stop('Download path is a symlink; refusing overwrite.')
    if target.exists():
        if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != EXPECTED_SHA256:
            stop('A DIFFERENT R030 file already exists in Downloads. Nothing overwritten.')
    else:
        with tempfile.NamedTemporaryFile(prefix='.md-r030-', suffix='.tmp', dir=downloads, delete=False) as f:
            temp = Path(f.name)
            f.write(raw_zip)
        try:
            if hashlib.sha256(temp.read_bytes()).hexdigest() != EXPECTED_SHA256:
                stop('Temporary ZIP checksum failure.')
            os.replace(temp, target)
        finally:
            temp.unlink(missing_ok=True)
    print('Verified authenticated private GitHub archive:', target)
    print('Pinned SHA-256:', EXPECTED_SHA256)
    try:
        subprocess.run(['bash', '-s', '--', str(target)], input=runner, check=True)
    except subprocess.CalledProcessError:
        stop('Packaged task failed; inspect error above. No success claimed.')

main()
PYTHON_RELAY_BOOTSTRAP
MISS_DEMEANOR_R030
