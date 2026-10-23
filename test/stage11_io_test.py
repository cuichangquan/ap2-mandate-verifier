"""Exercise all three real Oracle CLI read boundaries without network."""
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix='stage11-oracle-') as directory:
        work = Path(directory)
        fifo = work / 'fifo'; os.mkfifo(fifo)
        oversized = work / 'oversized'; oversized.write_bytes(b'x' * 16385)
        link = work / 'link'; link.symlink_to(ROOT / 'research/phase2a_e06i/e03_e04_signed_oracle.py')
        for adapter in ('o1o3', 'o2o5', 'o4'):
            for bad in (fifo, oversized, link):
                output = work / (adapter + '-' + bad.name + '.json')
                command = [sys.executable, '-I', '-B', 'test/' + adapter + '_compare.py',
                           '--oracle', str(bad), '--report', str(output),
                           '--gem-replay', 'research/stage11/archive/STAGE11_IO_GEM_REPLAY_32.json']
                if adapter == 'o1o3':
                    command += ['--bundle', 'research/stage11/inputs/STAGE7_PUBLIC_CASES.json', '--policy', 'research/stage11/inputs/O1O3_POLICY.json']
                else:
                    command += ['--fixture', 'research/stage11/inputs/O2O5_PUBLIC_CASES.json']
                if adapter == 'o4':
                    command += ['--schema-dir', str(work), '--binding-report', 'research/stage11/archive/STAGE11_IO_O2O5_REPORT.json']
                result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=5)
                assert result.returncode != 0 and b'pinned input type/size' in result.stderr
                assert not output.exists()
                count += 1
        identity = runpy.run_path(str(ROOT / 'test/stage11_identity.py'))
        source = identity['bounded_regular'](ROOT / 'research/phase2a_e06i/e03_e04_signed_oracle.py', 16384)
        assert len(source) == 13953
        count += 1
    print(f'PASS {count} Python Oracle CLI read controls; all three entry points bounded')


if __name__ == '__main__':
    main()
