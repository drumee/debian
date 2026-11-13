/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Fixed private Maildir-by-UUID profile; no external writers or replication.
 * Growth transactions and namespace mutations share a per-home kernel lock.
 * Index readers synchronize through Dovecot; raw directory scans are unsafe. */
#include "lib.h"
#include "quota-private.h"
#include "mail-user.h"
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
struct drumee_lock {
 struct drumee_lock *next;
 char *home;
 int fd;
 unsigned refs;
 struct quota_transaction_context *budget_owner;
};
static struct drumee_lock *locks;
void *drumee_quota_guard(struct mail_user *user,const char **error_r)
{
 const char *home;
 if(mail_user_get_home(user,&home)<=0) {
  *error_r="drumee quota: stable home unavailable";return NULL;
 }
 for(struct drumee_lock *l=locks;l!=NULL;l=l->next)
  if(strcmp(l->home,home)==0){l->refs++;return l;}
 const char *file=t_strconcat(home,"/.drumee-quota.lock",NULL);
 int fd=open(file,O_RDWR|O_CREAT|O_CLOEXEC|O_NOFOLLOW,0600);
 struct stat s;
 if(fd<0 || fstat(fd,&s)<0 || !S_ISREG(s.st_mode) || s.st_nlink!=1 ||
    s.st_uid!=geteuid() || (s.st_mode&07777)!=0600) {
  if(fd>=0)close(fd);*error_r="drumee quota: unsafe lock inode";return NULL;
 }
 for(unsigned n=0;n<500;n++) {
  if(flock(fd,LOCK_EX|LOCK_NB)==0) {
   struct drumee_lock *l=i_new(struct drumee_lock,1);
   l->home=i_strdup(home);l->fd=fd;l->refs=1;l->next=locks;locks=l;
   return l;
  }
  if(errno!=EWOULDBLOCK && errno!=EAGAIN && errno!=EINTR)break;
  struct timespec pause={0,10000000};nanosleep(&pause,NULL);
 }
 close(fd);*error_r="drumee quota: capacity reservation busy";return NULL;
}
void drumee_quota_unguard(void *guard)
{
 struct drumee_lock *l=guard;
 i_assert(l!=NULL && l->refs>0);
 if(--l->refs>0)return;
 i_assert(l->budget_owner==NULL);
 struct drumee_lock **prev=&locks;
 while(*prev!=l){i_assert(*prev!=NULL);prev=&(*prev)->next;}
 *prev=l->next;
 /* Never unlink: current and waiting writers must share the same inode. */
 close(l->fd);i_free(l->home);i_free(l);
}
int drumee_quota_lock(struct quota_transaction_context *ctx,const char **error_r)
{
 if(ctx->drumee_lock!=NULL)return 0;
 struct drumee_lock *l=drumee_quota_guard(ctx->quota->user,error_r);
 if(l==NULL)return -1;
 if(l->budget_owner!=NULL && l->budget_owner!=ctx) {
  drumee_quota_unguard(l);
  *error_r="drumee quota: overlapping capacity transactions";return -1;
 }
 l->budget_owner=ctx;ctx->drumee_lock=l;return 0;
}
void drumee_quota_unlock(struct quota_transaction_context *ctx)
{
 struct drumee_lock *l=ctx->drumee_lock;
 if(l==NULL)return;
 i_assert(l->budget_owner==ctx);l->budget_owner=NULL;ctx->drumee_lock=NULL;
 drumee_quota_unguard(l);
}
