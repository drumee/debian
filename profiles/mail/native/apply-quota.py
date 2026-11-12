"""Apply bounded patches to an exact copy of upstream quota sources in /build/quota."""
import pathlib,sys
root=pathlib.Path(sys.argv[1])
def replace(file,old,new,count=1):
 p=root/file;s=p.read_text();assert s.count(old)==count,(file,old[:70],s.count(old));p.write_text(s.replace(old,new))
p=root/'quota-private.h';s=p.read_text();start=s.index('struct quota_transaction_context {');end=s.index('\n};',start);s=s[:end]+'\n\tint drumee_lock_fd; /* held through native commit/rollback */'+s[end:];s+='\nint drumee_quota_lock(struct quota_transaction_context *, const char **);\nvoid drumee_quota_unlock(struct quota_transaction_context *);\nenum quota_get_result drumee_quota_count(struct quota_root *, uint64_t *, uint64_t *, const char **);\n';p.write_text(s)
replace('quota.c','ctx = i_new(struct quota_transaction_context, 1);','ctx = i_new(struct quota_transaction_context, 1);\n\tctx->drumee_lock_fd = -1;')
replace('quota.c','\tif (ctx->limits_set)\n\t\treturn 0;', '''\tif (ctx->failed) { *error_result_r=QUOTA_GET_RESULT_INTERNAL_ERROR; *error_r="drumee quota transaction failed"; return -1; }
\tif (ctx->limits_set) return 0;
\tif (drumee_quota_lock(ctx,error_r)<0) { ctx->failed=TRUE; *error_result_r=QUOTA_GET_RESULT_INTERNAL_ERROR; return -1; }''')
replace('quota.c','\ti_free(ctx->roots);\n\ti_free(ctx);','\tdrumee_quota_unlock(ctx);\n\ti_free(ctx->roots);\n\ti_free(ctx);',2)
# Do not reserve against speculative future source removal (cross-folder MOVE).
replace('quota.c','struct mailbox *expunged_box = (expunged_mail == NULL ? NULL :','expunged_mail = NULL; /* Maildir source removal is not yet durable. */\n\tstruct mailbox *expunged_box = (expunged_mail == NULL ? NULL :')
p=root/'quota-count.c';s=p.read_text();start=s.index('static enum quota_get_result\nquota_count_cached(');body=s.index('\n{',start);end=s.index('\n}\n',body);s=s[:body]+'''\n{
 return drumee_quota_count(&root->root,bytes_r,count_r,error_r);'''+s[end:];p.write_text(s)
p=root/'quota-storage.c';s=p.read_text();s=s.replace('if (qt->failed)\n\t\treturn 0;', 'if (qt->failed) { mailbox_set_critical(t->box,"drumee quota transaction failed"); return -1; }')
# Every original permissive calculation-error path now refuses before writing.
s=s.replace('"saving mail anyway", error);\n\t\treturn 0;', '"refusing mail", error);\n\t\tquota_set_storage_error(qt,t->box,QUOTA_ALLOC_RESULT_TEMPFAIL,error); return -1;')
s=s.replace('"saving mail anyway", error);\n\t\t\tbreak;', '"refusing mail", error);\n\t\t\tquota_set_storage_error(qt,t->box,QUOTA_ALLOC_RESULT_TEMPFAIL,error); return -1;')
# Copy/save preallocation error blocks have no final return in upstream.
for boundary in ['\n\tif (qbox->module_ctx.super.copy(ctx, mail) < 0)', '\n\treturn qbox->module_ctx.super.save_begin(ctx, input);']:
 i=s.index(boundary);j=s.rfind('\n\t}',0,i);s=s[:j]+'\n\t\tquota_set_storage_error(qt,t->box,QUOTA_ALLOC_RESULT_TEMPFAIL,error); return -1;'+s[j:]
assert 'return 0;' not in s[s.index('case QUOTA_ALLOC_RESULT_TEMPFAIL:',s.index('static int quota_check')):s.index('default:',s.index('static int quota_check'))]
p.write_text(s)
