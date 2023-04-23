---
title: Simply managing Dynamic DNS in Kubernetes using the CronJob resource and the CloudFlare API
date: 2022-12-01T22:49:07-05:00
tags: [homelab, kubernetes, cloudflare, dns, tutorial]
---

So, your ISP won't give you a static IP address for your burgeoning homelab's network?
Tired of telling friends what your IP address is every time they want to access your Minecraft server?
Dynamic DNS is an extremely simple solution to that problem.
The gist is, if you can't rely on a static IP address, just have your servers periodically tell a third party where they're located.

In this post I'd like to share my exploration of Kubernetes and the CloudFlare API.

First of all I'd like to emphasize that there are definitely easier ways to do this.
Many consumer (even ISP provided) routers can connect to services like [NoIp](https://www.noip.com/) and [DynDNS](https://dyn.com/) without any hassle, and it's trivial to spin up services like [DDClient](https://github.com/ddclient/ddclient) in a Docker container or even packaged through your favorite Linux distribution.
I am running this in my Kubernetes cluster mostly out of curiosity.

I'm sharing this post to show how simple it is to run jobs on a Kubernetes cluster using tools that you're most likely already familiar with (simple bash scripts can go a long way!).

## Enter the Cloudflare API

You could use [DuckDNS](https://www.duckdns.org/), [Google Cloud DNS](https://cloud.google.com/dns), [AWS Route 53](https://aws.amazon.com/route53/), or really any service that offers you the ability to update DNS records programmatically.
I chose [CloudFlare](https://www.cloudflare.com/) because I already have a few domains managed by them.

Luckily, Cloudflare provides an easy to use API with [documentation and examples](https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-update-dns-record) on how to update a DNS record already provided:

```bash
# PUT https://api.cloudflare.com/client/v4/zones/{zone_identifier}/dns_records/{identifier}
curl --request PUT \
  --url https://api.cloudflare.com/client/v4/zones/zone_identifier/dns_records/identifier \
  --header 'Content-Type: application/json' \
  --header 'X-Auth-Email: ' \
  --data '{
    "content": "198.51.100.4",
    "name": "example.com",
    "proxied": false,
    "type": "A",
    "comment": "Domain verification record",
    "tags": [
      "owner:dns-team"
    ],
    "ttl": 3600
  }'
```

So like 70% of the work is already done for us, great! *(unfortunately their example is not perfect, and led me to quite a bit of debugging)*

Let's break down their example:

* We need to make a `PUT` request to `https://api.cloudflare.com/client/v4/zones/{zone_identifier}/dns_records/{identifier}`, filling in values for `zone_identifier` and `identifier`
  * `zone_identifier` seems to be a [special ID given to each domain](https://developers.cloudflare.com/fundamentals/get-started/basic-tasks/find-account-and-zone-ids/).
  * `identifier` is a bit more mysterious. It seems that an `identifier` is given to each DNS entry, but CloudFlare's dashboard unhelpfully does not tell you what the record identifiers are.

    To get around this, you can either make an API request to Cloudflare that [lists your DNS records for a domain](https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-list-dns-records), or you can try updating a record manually with your browser's network tab open to intercept requests. I chose the ladder.

* We'll need to authenticate our requests.

  I didn't have luck getting Cloudflare's key-based authentication working, but their [token-based authentication](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) worked without any problems.

  For token-based authentication we just provide a [bearer token](https://swagger.io/docs/specification/authentication/bearer-authentication/) in the `Authorization` header.

* The body of the request is fairly simple:
  * We provide the name of the record we'd like to update, the type of record and the IP address we'd like to set it to
  * The record can be tagged with metadata through the `comment` and `tags` fields
  * We can specify a `TTL`, or [Time to Live](https://en.wikipedia.org/wiki/Time_to_live) to control how frequently client DNS caches invalidate (the value they've provided here is fine)

## How do *we* even know what our public IP address is?

Funny enough, the easiest way to find your public IP address is to ask someone else:

```bash
IP_ADDRESS=$(curl https://domains.google.com/checkip)
```

## Our simple Bash script

If you throw everything we've learned so far at the screen you'll probably arrive at a bash script that looks something like this:

```bash
IP=$(curl $CHECK_IP)
curl --request PUT --url https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer $API_KEY" \
  --data "{
    \"content\": \"$IP\",
    \"name\": \"$NAME\",
    \"proxied\": $PROXIED,
    \"ttl\": $TTL,
    \"type\": \"$TYPE\"
  }"
```

Fill in the appropriate environment variables and with luck you've witnessed your DNS become *dynamic*.

Now, we could stop here and throw this script in a cronjob, or a systemd service unit, but if you're like me you already have a Kubernetes cluster laying around, so you might as well use it to manage things right?

## Enter Kubernetes

This script involves three simple Kubernetes resources:

* A [`ConfigMap`](https://kubernetes.io/docs/concepts/configuration/configmap/) resource containing our simple bash script.
* A [`Secret`](https://kubernetes.io/docs/concepts/configuration/secret/) resource containing the sensitive environment variables that the script relies on.
* A [`CronJob`](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) resource, which fittingly creates [`Job`](https://kubernetes.io/docs/concepts/workloads/controllers/job/) resources on a schedule.

### The `ConfigMap` resource

`ConfigMaps` are one of the easier Kubernetes resources to understand.
Fundamentally they just store maps (key-value pairs) of data that can be consumed by other resources.

In this case, I am using the `ConfigMap` to store the script that I [derived in the last section](#our-simple-bash-script).
This `ConfigMap` is meant to be mounted onto a container as files, but ConfigMaps can be used in other ways like injecting environment variables into a container.

```yaml
# cloudflare-ddns-cronjob.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflare-ddns-script-configmap
data:
  run.sh: |
    IP=$(curl $CHECK_IP)
    curl --request PUT --url https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $API_KEY" \
    --data "{
      \"content\": \"$IP\",
      \"name\": \"$NAME\",
      \"proxied\": $PROXIED,
      \"ttl\": $TTL,
      \"type\": \"$TYPE\"
    }"
```

### The `Secret` resource

Kubernetes `Secrets` are very similar in concept to a `ConfigMap`, but they are intended to be used to store sensitive variables.

*Note: `Secrets` are not any more secure then a `ConfigMap` by default, but with some hardening (encryption at rest & access control with RBAC, retrieval through the K8s API instead of as environment variables) they can be made much more secure.
[Snyk's article](https://snyk.io/blog/using-kubernetes-configmaps-securely/) on the subject is a great introduction.*

In this case I am using the secrets to inject environment variables needed by the script to function:

```yaml
# cloudflare-ddns-cronjob.yaml
...
---
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-ddns-secret
stringData:
  ZONE_ID: "" # redacted
  RECORD_ID: "" # redacted
  NAME: "example.com" # redacted
  TYPE: A
  PROXIED: true
  TTL: "300"
  API_KEY: "" # redacted
  CHECK_IP: https://domains.google.com/checkip
```

### The `CronJob` resource

The `CronJob` resource is the most complex of the 3, and to be fair there's a lot going on here:

```yaml
# cloudflare-ddns-cronjob.yaml
...
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cloudflare-ddns-job
spec:
  concurrencyPolicy: Forbid
  failedJobsHistoryLimit: 5
  successfulJobsHistoryLimit: 5
  startingDeadlineSeconds: 60
  schedule: "*/5 * * * *"
  jobTemplate:
    metadata:
      name: cloudflare-ddns-job
    spec:
      activeDeadlineSeconds: 240
      backoffLimit: 3
      template:
        metadata:
          name: cloudflare-ddns-job-pod
        spec:
          containers:
            - name: cloudflare-ddns-job-container
              image: fedora:36
              command: ["bash", "/scripts/run.sh"]
              envFrom:
                - secretRef:
                    name: cloudflare-ddns-secret
              volumeMounts:
                - name: script-volume
                  mountPath: /scripts
          volumes:
            - name: script-volume
              configMap:
                  name: cloudflare-ddns-script-configmap
          restartPolicy: OnFailure
```

#### The `Cron` part of a `CronJob`

From the top, first we define some properties about scheduling these jobs:

```yaml
concurrencyPolicy: Forbid
failedJobsHistoryLimit: 5
successfulJobsHistoryLimit: 5
startingDeadlineSeconds: 60
schedule: "*/5 * * * *"
```

Even without additional documentation it's fairly clear what these do.

* We don't want multiple DDNS updates happening simultaneously, so we forbid concurrency.
* We don't want to fill up our history with jobs, so we only keep the last 5 working and 5 failed jobs.
* Finally we set the `CronJob` to create `Jobs` on an interval using the [cron expression format](https://crontab.guru/#*/5_*_*_*_*) (in this case we're just saying "run every 5 minutes").

#### The `Job` part of a `CronJob`

Our `CronJob` emits a `Job` on a schedule, but what do jobs look like?

```yaml
containers:
  - name: cloudflare-ddns-job-container
    image: fedora:36
    command: ["bash", "/scripts/run.sh"]
    envFrom:
      - secretRef:
          name: cloudflare-ddns-secret
    volumeMounts:
      - name: script-volume
        mountPath: /scripts
volumes:
  - name: script-volume
    configMap:
        name: cloudflare-ddns-script-configmap
restartPolicy: OnFailure
```

Our job consists of one container running Fedora 36.
It'll run the command `/scripts/run.sh`, which is injected via the `ConfigMap` via a volume mount.
Environment variables will be passed in using the `Secret`.

### Creating the resource

Now that we have all of our actors, the last step is to create the resources in Kubernetes:

```bash
# optionally create a namespace for our resource first
kubectl create namespace cloudflare-ddns
# (remove the -n argument to put it on the default namespace)
kubectl apply -n cloudflare-ddns -f cloudflare-ddns-cronjob.yaml
```

If all goes well you should start to see jobs running (and hopefully succeeding) periodically:

{{<figure src="images/dashboard.png" title="The Kubernetes Dashboard displaying the new resources" caption="My Kubernetes dashboard after the Cronjob has run a few times">}}

Old jobs are cleaned up according to the `failedJobsHistoryLimit` and `successfulJobsHistoryLimit` parameters you have set in the `CronJob` resource.

## Conclusion

In this blog post we've explored:

* Why Dynamic DNS is used and how it works
* How to use services like Cloudflare to roll your own Dynamic DNS
* Some basic Kubernetes resources and how they fit in your toolbox to get things done

The full Kubernetes manifest can be found [at this GitHub gist](https://gist.github.com/nikitawootten/16125951b35224cd4f1a7934bbbface9).
