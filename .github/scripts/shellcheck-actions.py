"""Run shellcheck on the bash `run:` steps of every composite action.

actionlint checks the `run:` scripts in workflows but not in action.yml files,
so this covers the composite actions. Each `${{ ... }}` expression is replaced
by a plain word first, as actionlint does, since shellcheck cannot parse it.

Usage: python3 .github/scripts/shellcheck-actions.py  (from the repo root)
"""

import glob
import re
import subprocess
import sys
import tempfile

import yaml

EXPRESSION = re.compile(r"\$\{\{.*?\}\}", re.DOTALL)

failed = False
for path in sorted(glob.glob("*/action.yml")):
    with open(path) as f:
        steps = yaml.safe_load(f)["runs"].get("steps", [])
    for i, step in enumerate(steps):
        if "run" not in step or step.get("shell") != "bash":
            continue
        name = step.get("name", f"step {i + 1}")
        script = "#!/usr/bin/env bash\n" + EXPRESSION.sub("_expr_", step["run"])
        with tempfile.NamedTemporaryFile("w", suffix=".sh") as tmp:
            tmp.write(script)
            tmp.flush()
            result = subprocess.run(["shellcheck", "--format=gcc", tmp.name], capture_output=True, text=True)
        if result.returncode != 0:
            failed = True
            for line in result.stdout.splitlines():
                print(f"{path} ({name}): {line.split(':', 1)[1]}")
        else:
            print(f"ok {path} ({name})")

sys.exit(1 if failed else 0)
