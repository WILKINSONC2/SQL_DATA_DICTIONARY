import subprocess
import sys

import pkg_resources

required = {'markdown2', 'md-mermaid', 'pyodbc', 'pandas',
            'bs4', 'markdown', 'numpy==1.19.3'}
installed = {pkg.key for pkg in pkg_resources.working_set}
missing = required - installed

if missing:
    python = sys.executable
    subprocess.check_call([python, '-m', 'pip', 'install', *missing], stdout=subprocess.DEVNULL)
