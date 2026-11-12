"""Bounded per-account admission and persistence; no message DATA is emitted."""
import hashlib,json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';commands=[]
def run(args):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()});assert r.returncode==0;return r
code="""import sys,json;sys.path.insert(0,'/lab');sys.argv=['probe','probe'];from client import connect
codes=[]
with connect() as s:
 for i in range(65):
  code,_=s.mail('contact@oxymot.fr');codes.append(code)
  if code>=400:break
  s.rset()
assert 400<=codes[-1]<500
with connect(auth='oxymotion') as s:
 other=s.mail('second@oxymot.fr')[0];assert other==250;s.rset()
print(json.dumps({'permitted':sum(c==250 for c in codes),'temporary_refusal':codes[-1],'other_account':other}))
"""
def probe(script):return json.loads(run(['docker','run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'-c',script]).stdout)
first=probe(code);run(['docker','compose','-p',project,'-f',p['compose_file'],'restart','policy']);after=probe("import sys,json,time;sys.path.insert(0,'/lab');sys.argv=['probe','probe'];from client import connect;time.sleep(1);s=connect();a=s.mail('contact@oxymot.fr')[0];s.close();assert 400<=a<500;print(json.dumps({'temporary_refusal_after_policy_restart':a}))")
repo=pathlib.Path(__file__).resolve().parents[2];obs=json.loads(run(['node',str(repo/'tests/mail/api.cjs'),'observe',str(root/'config.json')]).stdout);assert 'MAIL_ACCOUNT_RATE_LIMIT' in [a['code'] for a in obs['alerts']]
result={'status':'PASS_NATIVE_ACCOUNT_RATE_LIMIT','first':first,'after_restart':after,'observation':obs,'commands':commands};(root/'rate-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'first':first,'after_restart':after}))
