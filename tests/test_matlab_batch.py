"""Linux 上の argv/終了コードの模擬試験。Windows MATLAB の試験ではない。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "tools" / "matlab-batch"


class MatlabBatchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="talkrtl O'Brien ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        self.script = self.root / "tools/matlab-batch"
        shutil.copyfile(SOURCE, self.script)
        bin_dir = self.root / "mockbin"
        bin_dir.mkdir()
        self.exe = self.root / "Program Files/MATLAB/RTest/bin/matlab.exe"
        self.exe.parent.mkdir(parents=True)
        self.exe.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
Path(os.environ['MOCK_ARGV']).write_text(json.dumps(sys.argv[1:]))
sys.exit(int(os.environ.get('MOCK_EXIT', '0')))
""", encoding="utf-8")
        self.exe.chmod(0o755)
        wslpath = bin_dir / "wslpath"
        wslpath.write_text("""#!/usr/bin/env python3
import os, sys
if sys.argv[1] == '-u':
    print(os.environ['MOCK_EXE'])
elif os.environ.get('MOCK_UNC'):
    print(r'\\\\wsl.localhost\\Test\\home\\repo')
else:
    print(r"E:\\projects\\O'Brien demo")
""", encoding="utf-8")
        wslpath.chmod(0o755)
        self.capture = self.root / "args.json"
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        MATLAB_EXE=str(self.exe), MOCK_EXE=str(self.exe),
                        MOCK_ARGV=str(self.capture))

    def run_script(self, *args):
        return subprocess.run(['bash', str(self.script), *args], env=self.env,
                              capture_output=True, text=True)

    def test_default_and_quoting(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = json.loads(self.capture.read_text())
        self.assertEqual(argv[0], '-wait')
        self.assertEqual(argv[2], "E:\\projects\\O'Brien demo")
        self.assertEqual(argv[-2:], ['-batch', "addpath('matlab'); probe_environment"])

    def test_statement_single_argument(self):
        statement = "disp('日本語 with spaces'); disp(2+2);"
        self.assertEqual(self.run_script(statement).returncode, 0)
        self.assertEqual(json.loads(self.capture.read_text())[-1], statement)

    def test_nonzero_exit_preserved(self):
        self.env['MOCK_EXIT'] = '23'
        self.assertEqual(self.run_script("error('intentional')").returncode, 23)

    def test_windows_override(self):
        self.env['MATLAB_EXE'] = r'C:\Program Files\MATLAB\RTest\bin\matlab.exe'
        self.assertEqual(self.run_script().returncode, 0)

    def test_unc_rejected(self):
        self.env['MOCK_UNC'] = '1'
        self.assertEqual(self.run_script().returncode, 2)
        self.assertFalse(self.capture.exists())

    def test_extra_arguments_rejected(self):
        self.assertEqual(self.run_script('disp(1)', 'disp(2)').returncode, 2)

    def test_missing_executable_rejected(self):
        self.env['MATLAB_EXE'] = str(self.root / 'missing.exe')
        self.assertEqual(self.run_script().returncode, 2)


if __name__ == '__main__':
    unittest.main()
