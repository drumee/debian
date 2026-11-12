/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Drumee's fixed Maildir-by-UUID profile only. No external writers/replication.
 * Kernel lock is held until native storage commit/rollback completes. */
#include "lib.h"
#include "quota-private.h"
#include "mail-user.h"
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

int drumee_quota_lock(struct quota_transaction_context *ctx, const char **error_r)
{
 const char *home;
 struct stat s;
 if (ctx->drumee_lock_fd >= 0) return 0;
 if (mail_user_get_home(ctx->quota->user, &home) <= 0) {
  *error_r="drumee quota: stable home unavailable"; return -1;
 }
 const char *file=t_strconcat(home,"/.drumee-quota.lock",NULL);
 int fd=open(file,O_RDWR|O_CREAT|O_CLOEXEC|O_NOFOLLOW,0600);
 if (fd<0 || fstat(fd,&s)<0 || !S_ISREG(s.st_mode) || s.st_nlink!=1 ||
     s.st_uid!=geteuid() || (s.st_mode&0777)!=0600) {
  if(fd>=0)close(fd); *error_r="drumee quota: unsafe lock inode"; return -1;
 }
 /* Bounded contention: never hold an LMTP delivery indefinitely behind a client. */
 for(unsigned n=0;n<500;n++) {
  if(flock(fd,LOCK_EX|LOCK_NB)==0) {
   ctx->drumee_lock_fd=fd;
   e_debug(ctx->quota->event,"drumee quota lock acquired wait_steps=%u",n);
   return 0;
  }
  if(errno!=EWOULDBLOCK && errno!=EAGAIN && errno!=EINTR)break;
  struct timespec pause={0,10000000};nanosleep(&pause,NULL);
 }
 close(fd); *error_r="drumee quota: capacity reservation busy"; return -1;
}
void drumee_quota_unlock(struct quota_transaction_context *ctx)
{
 if(ctx->drumee_lock_fd>=0) {
  /* Never unlink: waiters must always refer to the same inode. */
  close(ctx->drumee_lock_fd);ctx->drumee_lock_fd=-1;
 }
}
static int virtual_size(int fd,uint64_t *bytes)
{
 char buffer[16384];ssize_t n;unsigned char previous=0;struct stat before,after;
 if(fstat(fd,&before)<0 || !S_ISREG(before.st_mode) || before.st_uid!=geteuid())return -1;
 uint64_t size=0;
 while((n=read(fd,buffer,sizeof(buffer)))!=0) {
  if(n<0){if(errno==EINTR)continue;return -1;}
  for(ssize_t i=0;i<n;i++) {
   if(buffer[i]=='\n' && previous!='\r')size++;
   size++;previous=(unsigned char)buffer[i];
  }
 }
 if(fstat(fd,&after)<0 || before.st_size!=after.st_size ||
    before.st_mtim.tv_sec!=after.st_mtim.tv_sec || before.st_mtim.tv_nsec!=after.st_mtim.tv_nsec)return -1;
 if(UINT64_MAX-*bytes<size)return -1;*bytes+=size;return 0;
}
static int scan(int fd,bool messages,unsigned depth,uint64_t *bytes,uint64_t *count,unsigned *entries)
{
 if(depth>64)return -1;
 int copy=dup(fd);if(copy<0)return -1;DIR *dir=fdopendir(copy);if(dir==NULL){close(copy);return -1;}
 int ret=0;struct dirent *entry;
 errno=0;
 while((entry=readdir(dir))!=NULL) {
  const char *name=entry->d_name;if(strcmp(name,".")==0||strcmp(name,"..")==0)continue;
  if(++*entries>1000000){ret=-1;break;}
  struct stat s;if(fstatat(fd,name,&s,AT_SYMLINK_NOFOLLOW)<0){ret=-1;break;}
  if(S_ISLNK(s.st_mode)){ret=-1;break;}
  if(S_ISDIR(s.st_mode)) {
   if(messages){ret=-1;break;}
   if(strcmp(name,"tmp")==0)continue;
   int child=openat(fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
   if(child<0){ret=-1;break;}
   ret=scan(child,strcmp(name,"cur")==0||strcmp(name,"new")==0,depth+1,bytes,count,entries);close(child);
   if(ret<0)break;
  } else if(messages) {
   if(!S_ISREG(s.st_mode)){ret=-1;break;}
   int child=openat(fd,name,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
   if(child<0){ret=-1;break;}
   ret=virtual_size(child,bytes);close(child);if(ret<0)break;(*count)++;
  }
  errno=0;
 }
 if(entry==NULL && errno!=0)ret=-1;
 closedir(dir);return ret;
}
enum quota_get_result drumee_quota_count(struct quota_root *root,uint64_t *bytes,uint64_t *count,const char **error_r)
{
 const char *home;*bytes=*count=0;
 if(mail_user_get_home(root->quota->user,&home)<=0){*error_r="drumee quota: home unavailable";return QUOTA_GET_RESULT_INTERNAL_ERROR;}
 const char *maildir=t_strconcat(home,"/../Maildir",NULL);
 int fd=open(maildir,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);unsigned entries=0;
 int ret=fd<0?-1:scan(fd,FALSE,0,bytes,count,&entries);if(fd>=0)close(fd);
 if(ret<0){*error_r="drumee quota: committed Maildir recount failed";return QUOTA_GET_RESULT_INTERNAL_ERROR;}
 return QUOTA_GET_RESULT_LIMITED;
}
