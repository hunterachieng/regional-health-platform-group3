# FIDELITY.md — where the emulator lied to us

LocalStack pretends to be AWS. Sometimes it doesn't act like real AWS. This
file lists every place we caught that happening, how we caught it, and what
we'd double-check on real AWS.

Why bother writing this down: if the emulator lies and we don't notice, our
tests pass but mean nothing. Catching the lie and writing it down means the
next person doesn't waste a day rediscovering it.

---

## 1. RDS isn't on the free plan

**What happened:** `terraform apply` worked fine right up until it tried to
create the actual database. Then it failed with:
```
Sorry, the rds service is not included within your LocalStack license
```

**Why:** LocalStack's health check says RDS is "available" no matter what
plan you're on. That check just means "we know how to fake this service" —
it doesn't mean your plan is allowed to use it. Those are two different
checks, and only one shows up before you try.

**How we found it:** Watched it fail live, then checked LocalStack's docs
directly. RDS needs the Base or Ultimate plan. S3, DynamoDB, Secrets
Manager, and EC2 are all still free. The assignment brief said RDS was
free — that was true when it was written, not anymore. We told the
trainer, and the whole class switched to Aiven for the database instead.

**On real AWS:** Nothing to check — real AWS has no plan-locking like this.
The real lesson: check a free tool's current limits yourself, don't trust
an old doc.

## 2. LocalStack forgets everything when it restarts

**What happened:** Our S3 bucket and DynamoDB table vanished after the
container restarted — not paused, gone completely.

**Why:** LocalStack's free tier keeps everything in memory, not on disk.
Restarting it is like closing a browser tab with unsaved work — whatever
was in there is just gone. The paid tier adds real saved state; the free
tier doesn't have it.

**How we found it:** `terraform init` failed with "connection refused"
right after a Codespace restart. Once LocalStack was back up, the very
next command failed with "bucket does not exist" — even though we'd
created that bucket successfully earlier the same day. Fixed by
re-running `bootstrap.sh`, which is safe to run again and just rebuilds it.

**On real AWS:** Nothing to check — real S3 and DynamoDB never disappear
like this. Just remember: any time the container restarts, run `make up`
again from scratch, don't assume it's still there.

## 3. EC2 containers can't be reached from a Mac

**What happened:** Nothing broke yet — this is a known limitation we read
about ahead of time, before it could bite us.

**Why:** LocalStack fakes EC2 by starting a regular Docker container.
On Linux, your computer can talk to that container directly. On a Mac,
Docker actually runs inside a hidden Linux VM, and Docker Desktop doesn't
let your Mac reach inside that VM's network. LocalStack says this
outright in their docs: EC2 containers just aren't reachable from macOS.

**How we found it:** Read LocalStack's EC2 docs before starting, since
this work is happening on a MacBook. Switched to GitHub Codespaces (a
real Linux machine in the browser) instead of fighting Mac networking.

**On real AWS:** Nothing to check — real EC2 works fine from any laptop.
This only matters for the emulator. Worth telling the team now: anyone
testing the EC2 piece on a Mac needs Codespaces too, or they'll hit a wall.

## 4. Aiven's free database falls asleep

**What happened:** Not LocalStack's fault — Aiven's database went idle and
stopped answering. The seed script just hung with no error at all.

**Why:** Aiven's free plan pauses your database after it sits unused for a
while, to save cost, and wakes it back up on the next connection. Same
idea as a phone screen going to sleep — first tap wakes it, takes a
second.

**How we found it:** The seed script sat retrying forever with no error
message. Opened the database's page on Aiven's website, which woke it up.
Tried connecting again right after — worked instantly.

**On real AWS:** Nothing to check — a real paid database doesn't sleep.
Just know: if a script hangs talking to Aiven, go wake it up on their
dashboard first before assuming something's broken.

---

## 5. ELBv2 isn't on the Hobby plan either

**What happened:** `terraform apply` created Secrets Manager and the security
group, then failed when it tried to create or read the ALB and target group:
```
Sorry, the elbv2 service is not included within your LocalStack license
```

**Why:** Same pattern as RDS — the health endpoint lists `elbv2` as
"available" but the Hobby license blocks actual API calls. The assignment
still requires `aws_lb` Terraform for IaC grading and `trivy config` scans;
nginx on the EC2 instance carries real traffic instead. We gate ALB creation
behind `enable_alb` (default `false`) so `make up` works on Hobby while the
ALB blocks stay in the module for scanning.

**How we found it:** Watched `make up NAME=hunter` fail on
`DescribeLoadBalancers` with HTTP 501 after the data tier applied cleanly.

**On real AWS:** Enable `enable_alb = true` and verify listener health checks
actually pull unhealthy targets — LocalStack never documented that behaviour
faithfully anyway.

## 6. DescribeImages fails for custom Docker AMIs (Terraform only)

**What happened:** `terraform apply` failed on `aws_instance` with:
```
collecting instance settings: couldn't find resource
```
Debug logging showed `DescribeImages` returning `InvalidAMIID.NotFound` for
`ami-1ec9f2444d2c`, even though the same AMI worked via `aws ec2 run-instances`
and the Docker image `localstack-ec2/app:ami-1ec9f2444d2c` existed on the host.

**Why:** The Terraform AWS provider calls `DescribeImages` before create when
`root_block_device` is set. LocalStack's DescribeImages does not register
custom docker-tagged AMIs, but `RunInstances` does find them.

**How we found it:** `TF_LOG=DEBUG terraform apply` showed the DescribeImages
400 response. Confirmed RunInstances succeeded with the same AMI via AWS CLI.

**Workaround:** Set `skip_root_block_device = true` in your `<name>.tfvars` for
LocalStack local apply (see `terraform/environments/*.tfvars.example`). The
module default is `false` so CI `trivy config` sees an encrypted root volume;
LocalStack deploys must opt out explicitly. On real AWS, leave it `false`.

---

## A few more things worth knowing (not emulator bugs, just real gotchas)

- **A cancelled command can leave a lock stuck.** If you hit Ctrl+C on
  Terraform mid-command, it can leave a "someone is using this" lock
  behind, since it only releases the lock if it finishes normally. Next
  command fails with a lock error. Fix: `terraform force-unlock <id>` —
  only do this if you're sure nobody else is actually running something
  right now.

- **Secret scanners flag the shape of a secret, not whether it's real.**
  GitGuardian flagged a line that just said `password = "REPLACE_ME"` in
  an example file, because it looks like a real password line. It wasn't
  one. Always check what the flagged commit actually contains before
  panicking or ignoring it. (Same thing happens with LocalStack's fake
  `"test"`/`"test"` credentials — expected, safe to mark as false positive.)

- **You can't use Terraform to build the thing Terraform needs to start.**
  The S3 bucket that stores Terraform's notes can't be built by that same
  Terraform, because it needs that bucket to exist first. That's why
  `bootstrap.sh` is a plain script, not a `.tf` file.