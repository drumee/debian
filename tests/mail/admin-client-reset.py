"""Rotate only synthetic lab client projections before private-network replay."""
import sys,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent/'admin'))
from common import *
clients=json.loads((source/'keys/client.json').read_text())
for account,mailbox in [('ghost','contact@oxymot.fr'),('oxymotion','second@oxymot.fr')]:
 password='Private-'+uuid.uuid4().hex;cli('account','password',account,password=password,mutate=True);cli('account','update',account,opts=['--envelope-from',mailbox,'--header-from',mailbox,'--dsn-mailbox',mailbox],mutate=True);cli('account','enable',account,mutate=True);clients[account]=password
file=source/'keys/client.json';file.write_text(json.dumps(clients));file.chmod(0o600);print(json.dumps({'status':'PASS_SYNTHETIC_CLIENT_PROJECTIONS_ROTATED','applied_revision':state['revision']}))
