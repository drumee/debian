"""Runtime quota changes, precise below-use observation and deferred LMTP."""
from common import *
passwords['second@oxymot.fr']=json.loads((source/'keys/client.json').read_text())['second'];user='second@oxymot.fr';folder='mail03-quota-'+uuid.uuid4().hex
cli('mailbox','quota',user,opts=['--bytes','2097152'],mutate=True);assert probe(action='append',user=user,folder=folder,bytes=1200000)['append_code']=='OK';shown=cli('mailbox','show',user)['data'];assert shown['used_bytes']>1048576 and not shown['over_quota'];check('quota-increase-effective-and-exact-observed-bytes',{'used_bytes':shown['used_bytes'],'quota_bytes':shown['quota_bytes']})
shrunk=cli('mailbox','quota',user,opts=['--bytes','1048576'],mutate=True);assert shrunk['data']['over_quota'] and shrunk['data']['used_bytes']==shown['used_bytes'];assert probe(action='append',user=user,folder=folder,bytes=100)['append_code']=='NO';tag='quota-deferred-'+uuid.uuid4().hex;sent=probe(action='send',recipient=user,tag=tag);assert sent['data_code']==250
def queue():
 r=run(['docker','exec',project+'-postfix-1','postqueue','-c','/config','-j']);assert r.returncode==0;return [json.loads(x) for x in r.stdout.splitlines()]
for _ in range(40):
 delayed=next((x for x in queue() if x['queue_id']==sent['queue_id'] and x['queue_name']=='deferred' and 'quota' in str(x).lower()),None)
 if delayed:break
 time.sleep(.2)
assert delayed;check('quota-decrease-below-use-retains-data-tempfails-lmtp',{'quota':shrunk['data'],'queue':delayed})
assert probe(action='clear-folder',user=user,folder=folder)['delete_code']=='OK';run(['docker','exec',project+'-postfix-1','postqueue','-c','/config','-f']);assert wait_read(user,tag)['matches']==1;assert not any(x['queue_id']==sent['queue_id'] for x in queue());check('quota-space-release-drains-same-accepted-message',{'queue_id':sent['queue_id'],'delivered_matches':1})
result={'status':'PASS_MAIL03_NATIVE_QUOTA_CHANGE','checks':checks,'commands':commands,'last_revision':state['revision']};(root/'mail03-quota-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'checks':len(checks)}))
