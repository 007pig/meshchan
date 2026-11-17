"""Small source/native identity checks; no packaging or release allocation."""
import base64
import binascii
from pathlib import Path
import plistlib
import re

CONFIG = 'apps/meshchan_app/macos/Runner/Configs/Version.xcconfig'
BUNDLE_ID = 'org.meshchan.meshchan'


def apple_short_version(version):
    """Validate SemVer without build metadata, then map its numeric core."""
    number = r'(?:0|[1-9][0-9]*)'
    identifier = r'(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
    match = re.fullmatch(rf'({number}\.{number}\.{number})(?:-{identifier}(?:\.{identifier})*)?', version)
    if not match:
        raise ValueError('Invalid product version (expected SemVer without build metadata): ' + version)
    return match[1]


def expected_identity(version, build):
    short = apple_short_version(version)
    if type(build) is not int or build <= 0:
        raise ValueError('Expected app build must be a positive integer')
    return {'CFBundleShortVersionString': short, 'CFBundleVersion': str(build),
            'CFBundleIdentifier': BUNDLE_ID, 'CFBundleName': 'Meshchan',
            'MeshchanProductVersion': version}


def config_values(root):
    text = (root / CONFIG).read_text()
    return dict(re.findall(r'^(MESHCHAN_[A-Z_]+) = (\S+)$', text, re.M))


def check_source_identity(root, version, build):
    expected = expected_identity(version, build)
    values = config_values(root)
    for key, value in [('MESHCHAN_PRODUCT_VERSION', version),
                       ('MESHCHAN_APPLE_SHORT_VERSION', expected['CFBundleShortVersionString']),
                       ('MESHCHAN_APP_BUILD', str(build))]:
        if values.get(key) != value:
            raise ValueError('Native source identity mismatch: ' + key)
    runner = root / 'apps/meshchan_app/macos/Runner'
    with (runner / 'Info.plist').open('rb') as stream:
        template = plistlib.load(stream)
    for key, value in {'CFBundleShortVersionString': '$(MESHCHAN_APPLE_SHORT_VERSION)',
                       'CFBundleVersion': '$(MESHCHAN_APP_BUILD)',
                       'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
                       'CFBundleName': '$(PRODUCT_NAME)',
                       'MeshchanProductVersion': '$(MESHCHAN_PRODUCT_VERSION)'}.items():
        if template.get(key) != value:
            raise ValueError('Info.plist template mismatch: ' + key)
    info = (runner / 'Configs/AppInfo.xcconfig').read_text()
    if ('#include "Version.xcconfig"' not in info
            or not re.search(r'^PRODUCT_NAME = Meshchan$', info, re.M)
            or not re.search(r'^PRODUCT_BUNDLE_IDENTIFIER = org\.meshchan\.meshchan$', info, re.M)):
        raise ValueError('AppInfo identity/include mismatch')
    return expected


def check_app(app, version, build):
    """An explicit product path must contain a real plist and executable."""
    expected = expected_identity(version, build)
    app = Path(app)
    executable = app / 'Contents/MacOS/Meshchan'
    if (not executable.is_file() or executable.stat().st_size == 0
            or not executable.stat().st_mode & 0o111):
        raise ValueError('Missing or incomplete App executable: ' + str(app))
    with (app / 'Contents/Info.plist').open('rb') as stream:
        actual = plistlib.load(stream)
    for key, value in expected.items():
        if type(actual.get(key)) is not str or actual[key] != value:
            raise ValueError('Built Info.plist mismatch: ' + key)
    return expected


def check_xcode_environment(environment, version, build):
    """Check raw Flutter inputs, before trusting platform normalization.

    Flutter 3.50 embeds original manifest/override values in DART_DEFINES.
    Explicit overrides may also export BUILD_NAME/NUMBER. Neither a numeric --build-name nor divergent Dart defines
    are supported: change the synchronized source decision instead.
    """
    expected_identity(version, build)
    for key, expected in [('BUILD_NAME', version), ('BUILD_NUMBER', str(build))]:
        if key in environment and environment[key] != expected:
            raise ValueError('Conflicting Flutter input: ' + key)
    try:
        defines = [base64.b64decode(v, validate=True).decode('utf-8')
                   for v in environment.get('DART_DEFINES', '').split(',') if v]
    except (binascii.Error, UnicodeError) as error:
        raise ValueError('Malformed DART_DEFINES') from error
    for key, expected in [('FLUTTER_BUILD_NAME', version), ('FLUTTER_BUILD_NUMBER', str(build))]:
        if [d for d in defines if d.split('=', 1)[0] == key] != [key + '=' + expected]:
            raise ValueError('Missing or conflicting Dart build input: ' + key)
    # Runner-specific settings may be absent on the Flutter aggregate target.
    for key, expected in [('MESHCHAN_PRODUCT_VERSION', version),
                          ('MESHCHAN_APPLE_SHORT_VERSION', apple_short_version(version)),
                          ('MESHCHAN_APP_BUILD', str(build))]:
        if key in environment and environment[key] != expected:
            raise ValueError('Conflicting Xcode identity: ' + key)
