"""Apply bounded patches to an exact copy of upstream quota sources in /build/quota."""
import pathlib,sys
root=pathlib.Path(sys.argv[1])
def replace(file,old,new,count=1):
 p=root/file;s=p.read_text();assert s.count(old)==count,(file,old[:70],s.count(old));p.write_text(s.replace(old,new))
p=root/'quota-private.h';s=p.read_text();start=s.index('struct quota_transaction_context {');end=s.index('\n};',start);s=s[:end]+'\n\tvoid *drumee_lock; /* held through native commit/rollback */'+s[end:];s+='\nint drumee_quota_lock(struct quota_transaction_context *, const char **);\nvoid drumee_quota_unlock(struct quota_transaction_context *);\nvoid *drumee_quota_guard(struct mail_user *, const char **);\nvoid drumee_quota_unguard(void *);\n';p.write_text(s)
replace('quota.c','ctx = i_new(struct quota_transaction_context, 1);','ctx = i_new(struct quota_transaction_context, 1);\n\tctx->drumee_lock = NULL;')
replace('quota.c','\tif (ctx->limits_set)\n\t\treturn 0;', '''\tif (ctx->failed) { *error_result_r=QUOTA_GET_RESULT_INTERNAL_ERROR; *error_r="drumee quota transaction failed"; return -1; }
\tif (ctx->limits_set) return 0;
\tif (drumee_quota_lock(ctx,error_r)<0) { ctx->failed=TRUE; *error_result_r=QUOTA_GET_RESULT_INTERNAL_ERROR; return -1; }''')
replace('quota.c','\ti_free(ctx->roots);\n\ti_free(ctx);','\tdrumee_quota_unlock(ctx);\n\ti_free(ctx->roots);\n\ti_free(ctx);',2)
# Do not reserve against speculative future source removal (cross-folder MOVE).
replace('quota.c','struct mailbox *expunged_box = (expunged_mail == NULL ? NULL :','expunged_mail = NULL; /* Maildir source removal is not yet durable. */\n\tstruct mailbox *expunged_box = (expunged_mail == NULL ? NULL :')
# Use native index synchronization, never a racing raw readdir(new/cur).
p=root/'quota-count.c';s=p.read_text();start=s.index('static enum quota_get_result\nquota_count_cached(');body=s.index('\n{',start);end=s.index('\n}\n',body);s=s[:body]+'''\n{
 void *guard=drumee_quota_guard(root->root.quota->user,error_r);
 if(guard==NULL)return QUOTA_GET_RESULT_INTERNAL_ERROR;
 enum quota_get_result result=QUOTA_GET_RESULT_INTERNAL_ERROR;
 int ret=quota_count(&root->root,bytes_r,count_r,&result,error_r);
 drumee_quota_unguard(guard);
 return ret<0?result:QUOTA_GET_RESULT_LIMITED;'''+s[end:]
s=s.replace('} else if (mailbox_get_metadata(box, MAILBOX_METADATA_VIRTUAL_SIZE,','} else if (mailbox_sync(box, MAILBOX_SYNC_FLAG_FULL_READ) < 0 ||\n\t    mailbox_get_metadata(box, MAILBOX_METADATA_VIRTUAL_SIZE,',1)
s=s.replace('/* non-temporary error, e.g. ACLs denied access. */\n\t\t\tret = 0;', '*error_r=t_strdup_printf("Uncountable mailbox %s: %s",vname,errstr);\n\t\t\t*error_result_r=QUOTA_GET_RESULT_INTERNAL_ERROR; ret=-1;',1)
s=s.replace('static int\ncount_quota_update(', 'static int\ncount_quota_update_inner(',1)
s=s.replace('struct quota_backend quota_backend_count = {','''static int count_quota_update(struct quota_root *root, struct quota_transaction_context *ctx, const char **error_r)
{
 void *guard=drumee_quota_guard(root->quota->user,error_r);
 if(guard==NULL)return -1;
 int ret=count_quota_update_inner(root,ctx,error_r);
 drumee_quota_unguard(guard);return ret;
}
struct quota_backend quota_backend_count = {''',1)
p.write_text(s)
p=root/'quota-storage.c';s=p.read_text();s=s.replace('if (qt->failed)\n\t\treturn 0;', 'if (qt->failed) { mailbox_set_critical(t->box,"drumee quota transaction failed"); return -1; }')
# Every original permissive calculation-error path now refuses before writing.
s=s.replace('"saving mail anyway", error);\n\t\treturn 0;', '"refusing mail", error);\n\t\tquota_set_storage_error(qt,t->box,QUOTA_ALLOC_RESULT_TEMPFAIL,error); return -1;')
s=s.replace('"saving mail anyway", error);\n\t\t\tbreak;', '"refusing mail", error);\n\t\t\tquota_set_storage_error(qt,t->box,QUOTA_ALLOC_RESULT_TEMPFAIL,error); return -1;')
# Copy/save preallocation error blocks have no final return in upstream.
for boundary in ['\n\tif (qbox->module_ctx.super.copy(ctx, mail) < 0)', '\n\treturn qbox->module_ctx.super.save_begin(ctx, input);']:
 i=s.index(boundary);j=s.rfind('\n\t}',0,i);s=s[:j]+'\n\t\tquota_set_storage_error(qt,t->box,QUOTA_ALLOC_RESULT_TEMPFAIL,error); return -1;'+s[j:]
assert 'return 0;' not in s[s.index('case QUOTA_ALLOC_RESULT_TEMPFAIL:',s.index('static int quota_check')):s.index('default:',s.index('static int quota_check'))]
p.write_text(s)

# Folder membership must not change while a whole-mailbox recount is in progress.
p=root/'quota-storage.c';s=p.read_text().replace('quota_create_box(struct mailbox *box,','quota_create_box_inner(struct mailbox *box,',1)
wrappers='''static void *drumee_box_guard(struct mailbox *box)
{
 const char *error;
 void *guard=drumee_quota_guard(box->storage->user,&error);
 if(guard==NULL)mailbox_set_critical(box,"%s",error);
 return guard;
}
static int quota_create_box(struct mailbox *box,const struct mailbox_update *update,bool directory)
{
 void *guard=drumee_box_guard(box);if(guard==NULL)return -1;
 int ret=quota_create_box_inner(box,update,directory);
 drumee_quota_unguard(guard);return ret;
}
static int quota_delete_box(struct mailbox *box)
{
 struct quota_mailbox *qbox=QUOTA_CONTEXT_REQUIRE(box);
 void *guard=drumee_box_guard(box);if(guard==NULL)return -1;
 int ret=qbox->module_ctx.super.delete_box(box);
 drumee_quota_unguard(guard);return ret;
}
static int quota_rename_box(struct mailbox *box,struct mailbox *dest)
{
 struct quota_mailbox *qbox=QUOTA_CONTEXT_REQUIRE(box);
 void *guard=drumee_box_guard(box);if(guard==NULL)return -1;
 int ret=qbox->module_ctx.super.rename_box(box,dest);
 drumee_quota_unguard(guard);return ret;
}
'''
s=s.replace('static int\nquota_get_status(',wrappers+'\nstatic int\nquota_get_status(',1)
s=s.replace('v->create_box = quota_create_box;', 'v->create_box = quota_create_box;\n\tv->delete_box = quota_delete_box;\n\tv->rename_box = quota_rename_box;',1)
p.write_text(s)
