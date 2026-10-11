"""Check review-package integrity; does not run FPGA or board validation."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def check():
    manifest = json.loads((ROOT / 'docs/source_manifest.json').read_text(encoding='utf-8'))
    for entry in manifest['files']:
        raw = (ROOT / entry['path']).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry['sha256'], entry['path']
        decoded = raw.decode(entry['encoding'])
        mirrored = (ROOT / entry['utf8_copy']).read_bytes().decode('utf-8')
        assert decoded == mirrored, entry['utf8_copy']
        assert len(decoded.splitlines()) == entry['line_count'], entry['path']

    ns = {'s': 'http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009'}
    packages = list((ROOT / 'ip_repo').rglob('component.xml'))
    assert len(packages) == 2
    for package in packages:
        tree = ET.parse(package)
        for filename in tree.findall('.//s:file/s:name', ns):
            assert (package.parent / filename.text).is_file(), filename.text

    for interface in (ROOT / 'ip_repo/rgb2lcd/if').rglob('*.xml'):
        ET.parse(interface)
    xpr = ET.parse(ROOT / 'ov5640_lcd.xpr')
    paths = [o.attrib['Val'] for o in xpr.findall('.//Option') if o.attrib.get('Name') == 'IPRepoPath']
    assert set(paths) == {'$PPRDIR/ip_repo/rgb2lcd', '$PPRDIR/ip_repo/ov5640_capture_data'}
    for path in paths:
        assert (ROOT / path.replace('$PPRDIR/', '')).is_dir()

    design = json.loads((ROOT / 'ov5640_lcd.srcs/sources_1/bd/system/system.bd').read_text(encoding='utf-8'))['design']
    evidence = json.loads((ROOT / 'docs/evidence/design_summary.json').read_text(encoding='utf-8'))
    for key, value in evidence.items():
        assert design[key] == value, key
    assert design['components']['axi_vdma_0']['parameters']['c_num_fstores']['value'] == '3'
    assert design['components']['axi_vdma_0']['parameters']['c_m_axis_mm2s_tdata_width']['value'] == '24'

    assert (ROOT / 'vitis/system_wrapper.xsa').is_file()
    for path in ['README.md', 'docs/PROJECT_ANALYSIS.md', 'docs/WEB_ANALYSIS_PROMPT.md', 'docs/REPRODUCTION.md']:
        assert (ROOT / path).read_text(encoding='utf-8').strip(), path
    print(f'PASS: {len(manifest["files"])} source snapshots, 2 custom IP packages, XPR/BD/evidence and review documents.')


if __name__ == '__main__':
    check()
