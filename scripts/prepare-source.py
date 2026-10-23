#!/usr/bin/env python3
"""Export a release's corresponding source without private Git/build state."""
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPARKLE_REVISION = 'eef1a539a373c1f1a320624b1130fc5de7b2e100'
SPARKLE = ROOT / '.build/dependencies/Sparkle-source-2.10.0'


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if not SPARKLE.exists():
        subprocess.run(['git', 'clone', '--depth', '1', '--branch', '2.10.0',
                        '--recurse-submodules', '--shallow-submodules',
                        'https://github.com/sparkle-project/Sparkle.git', str(SPARKLE)], check=True)
    revision = subprocess.check_output(
        ['git', '-C', str(SPARKLE), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != SPARKLE_REVISION:
        raise SystemExit('Wrong Sparkle source revision')
    if subprocess.check_output(['git', '-C', str(SPARKLE), 'status', '--porcelain']):
        raise SystemExit('Sparkle source tree is modified')
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    built = ROOT / '.build/Draplet.app'
    if plistlib.loads((built / 'Contents/Info.plist').read_bytes()) != info:
        raise SystemExit('Build the matching application before exporting source')
    paths = sorted(set(git('ls-files', '--cached', '--others', '--exclude-standard', '-z')
                       .decode().strip('\0').split('\0')))
    paths = [p for p in paths if (ROOT / p).is_file()]
    before = {p: digest(ROOT / p) for p in paths}
    version = info['CFBundleShortVersionString']
    name = f'Draplet-{version}-source'
    (ROOT / 'dist').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='source-export-', dir=ROOT / '.build') as temp:
        source = pathlib.Path(temp) / name
        for relative in paths:
            target = source / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        shutil.copytree(SPARKLE, source / 'DependencySources/Sparkle-2.10.0',
                        ignore=shutil.ignore_patterns('.git'))
        manifest = {
            'version': version, 'build': info['CFBundleVersion'],
            'baseCommit': git('rev-parse', 'HEAD').decode().strip(),
            'workingTreeSnapshot': bool(git('status', '--porcelain')),
            'executableSHA256': digest(built / 'Contents/MacOS/Draplet'),
            'sparkleRevision': revision, 'applicationSourceSHA256': before,
        }
        (source / 'SOURCE-MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
        (source / 'SOURCE-BUILD.md').write_text(
            '# Corresponding source\n\n'
            'This is the source snapshot for the application identified in SOURCE-MANIFEST.json.\n'
            'Build on macOS with Xcode command-line tools: `DRAPLET_SIGNING_IDENTITY=- bash build.sh`.\n'
            'The default build downloads the pinned Sparkle 2.10.0 distribution after checksum verification.\n'
            'Its complete source and vendored dependencies are in DependencySources/Sparkle-2.10.0;\n'
            'see its Makefile, Xcode project and Documentation for rebuilding the framework.\n'
            'To use a rebuilt framework, replace .build/dependencies/sparkle-2.10.0/Sparkle.framework\n'
            'before running build.sh. Release Ed25519 private keys are not needed to build the app.\n'
            'All Draplet adaptations and license notices are included. See docs/UPDATES.md.\n')
        if before != {p: digest(ROOT / p) for p in paths}:
            raise SystemExit('Source changed during export; retry')
        output = ROOT / 'dist' / f'{name}.tar.gz'
        with tarfile.open(output, 'w:gz') as archive:
            archive.add(source, arcname=name)
    print(output)


if __name__ == '__main__':
    main()
