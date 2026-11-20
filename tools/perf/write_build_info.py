#!/usr/bin/env python3
"""Stamp the exported project, never infer that an unstamped binary is a known SHA."""
import json
import os
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
def build_info():
    commit=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    if not re.fullmatch('[0-9a-f]{40}',commit):raise ValueError('Invalid build commit')
    return {'schema_version':1,'source_sha':commit,'version':re.search(r'config/version="([^"]+)"',(ROOT/'project.godot').read_text())[1],
            'ci_run_id':os.environ.get('GITHUB_RUN_ID'),'ci_run_number':os.environ.get('GITHUB_RUN_NUMBER'),
            'dirty_worktree':bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip())}
if __name__=='__main__':
    path=ROOT/'data/build_info.json';path.write_text(json.dumps(build_info(),indent=2)+'\n');print(path)
