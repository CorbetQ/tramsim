#!/usr/bin/env python3
"""Run a Godot check and reject script errors even when the engine returns zero."""
import argparse, subprocess, sys
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot',default='godot');p.add_argument('--display',action='store_true')
    p.add_argument('script');p.add_argument('args',nargs=argparse.REMAINDER);a=p.parse_args()
    command=[a.godot]+(['--rendering-driver','opengl3','--rendering-method','gl_compatibility'] if a.display else ['--headless'])+['--path','.','--audio-driver','Dummy','-s',a.script]+a.args
    result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=300)
    print(result.stdout,end='')
    failed=result.returncode!=0 or any(s in result.stdout for s in ['SCRIPT ERROR','Parse Error','ECHEC:'])
    return 1 if failed else 0
if __name__=='__main__':sys.exit(main())
