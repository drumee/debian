# MAIL-02 atomic quota and private ingress amendment proposal

This amendment is written before implementing the replacement. Baseline Infra
4a9a77d / Debian0fc183e, package .4 and native f3fe9dc reproduce both failures
inside the retained Docker26 guest. The fresh profile is
/home/lab/runs/mail02-profile-i9gpgs2v. Concurrent LMTP+APPEND accepts1,150,509
RFC822 bytes for1,048,576. Private48 and49 clients both get ECONNREFUSED.

## Quota enforcement

Upstream Dovecot2.4.1 quota-count reads per-mailbox index totals; each quota
transaction snapshots remaining capacity, without a cross-process reservation.
The final quota check occurs before commit, so two successful checks can both
commit. quota-storage also deliberately permits writes after quota calculation
errors. Zero grace does not provide atomicity.

The proposed native module retains Dovecot's quota checking API but holds a
persistent-inode advisory flock in the stable UUID home from the first capacity
check through storage commit/rollback. Every LMTP save and IMAP APPEND/COPY/MOVE
uses this boundary. Lock waits are bounded and fail temporarily. Independent UUIDs
have separate lock inodes. No username/address-based lock is used. Process death
releases the kernel lock; no durable reservation counter can leak.

The first experimental module counted raw `cur/` and `new/` directory entries.
It is superseded and is **not qualified**: native readers can move a recent message
or rename its flag suffix while a raw iterator is running, causing an undercount.
Passing the initial writer race tests does not establish the invariant.

The replacement serializes growth transactions, folder creation/deletion/rename,
and quota-count/recalculation under the same stable-home lock. Native Dovecot
`mailbox_sync(FULL_READ)` precedes virtual-size/status reads; mailbox-list indexing
and process-local quota-count caching are disabled for this fixed profile. Dovecot
index locking handles native flag/recent renames. All count errors refuse growth.
A process-local lock registry permits nested read/namespace guards, but rejects a
second independent capacity transaction in the same process. The growth owner
retains the lock until native storage commit or rollback has completed.

The unit is Dovecot virtual RFC822 bytes, summed across all selectable folders of
the one private UUID namespace. Index/filesystem recovery runs before the next
admission after interruption; uncommitted `tmp/` files are not logical quota usage
and remain subject to the separate filesystem free-space guard. Failed writes
must not retain a reservation. Kernel locks disappear on process death; the lock
inode is never unlinked. External filesystem writers, shared/public namespaces,
replication, dsync, Sieve and non-Maildir storage are outside this image contract.
Do not enable them without a separate writer-path audit and requalification.

The exact verdict and native concurrency, namespace-churn, crash/write-failure,
restart and accounting evidence are recorded in the Infra MAIL-02 dossier.
Passing a subset never qualifies a different image or an external writer path.

A Maildir MOVE can stage a destination before source expunge. The proposal does
not credit a speculative source expunge: reserve destination capacity first,
release source usage after its actual removal. This may conservatively refuse a
MOVE without temporary headroom, rather than exceed the logical committed-byte
limit after an interruption. This consequence must be explicit in qualification;
no exactly-once or cross-folder atomic MOVE claim is made. Native positive and
negative COPY/MOVE tests and interruption accounting are mandatory.

## Private ingress

The canonical composition already makes its edge non-internal; the acceptance
composition incorrectly makes that same edge internal while requesting a published
1587 binding. Docker26 suppresses that publication. The acceptance private-bind
case must use the canonical routed edge inside the disconnected qualification VM.
No application backend is adopted. The private bind remains the exact gateway
address, never a wildcard. Control network remains internal.

Proposed additional protection: a native nftables input chain in Postfix's own
network namespace, restricted to private submission port and declared source
CIDRs, applied before Postfix starts. Unknown sources are dropped at packet input,
not merely rejected by SMTP. This requires NET_ADMIN and SETPCAP only during the fixed startup
sequence; drop both from the process capability bounding set before starting
Postfix. No host network mode or host firewall mutation is introduced. Activation
must attest exact image, rule configuration, binding/network and capability drop.
The VM's outer network stays disconnected, so routed test bridges cannot reach
real SMTP destinations. Recreated clients and a normal guarded reboot must pass
without rule repairs. If observed source NAT defeats this policy, keep the gate
failed rather than permitting the gateway indiscriminately.

Source reference: upstream Dovecot2.4.1 tag commit
7d8c0e57599636cff365373ca1ce34e92aac0e25. Exact source and native module/image hashes
must be recorded. Original/native/new-image paths must be requalified. This design
does not grant production/DNS/firewall/publication permission.
