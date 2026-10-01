# NRCC Cluster Analysis — Kafka on a VMware Stretch Cluster

## 1. Summary of findings

The customer's environment is **not** the two-independent-datacenter topology this
repo was originally designed for. Instead:

- Kubernetes runs on top of a **single VMware vSphere "stretch cluster"** — one
  logical vSphere cluster whose ESXi hosts are split across two physical sites,
  most likely backed by **vSAN Stretched Cluster** storage.
- The customer's use of the term **"witness"** all but confirms this: vSAN
  Stretched Cluster requires a third, small **Witness Host/appliance** to act as a
  tie-breaker for *storage object* quorum between the two sites.
- Storage replication between the two sites is therefore almost certainly
  **synchronous, block-level, RPO=0** (that is what vSAN Stretched Cluster does —
  VMware's supported design requires ≤5 ms RTT and sufficient bandwidth between
  the two sites for this to work at all).
- Critically: **the witness solves storage quorum only.** It is invisible to, and
  does nothing for, Kubernetes' own `etcd` quorum or a Kafka cluster's controller
  (KRaft/ZooKeeper) quorum. Those are separate control planes with their own
  majority-voting requirements that the existing witness does not cover.

This changes the shape of the problem substantially from "two real datacenters,
bridge them with MirrorMaker2" to "one environment, two failure domains baked
into the same storage fabric, make Kafka aware of that split."

## 2. Why the intended MirrorMaker2 setup is dangerous here

The blueprint in this repo ([terraform/cluster/main.tf](terraform/cluster/main.tf)) provisions
**two independent Kubernetes clusters** (`primary` / `dr`), each intended to run its
own Kafka cluster, bridged by **MirrorMaker2** for cross-cluster replication. In
the real environment, this pattern is risky for several concrete reasons:

### a. Double replication of the same bytes, two different consistency models
If each Kafka broker's persistent volume sits on vSAN-stretched storage, the
underlying disk blocks are **already** being synchronously mirrored between the
two sites by vSAN. Layering MirrorMaker2's **asynchronous, application-level**
topic replication on top means the same data is being replicated twice, by two
mechanisms with different consistency guarantees (sync block replication vs.
async offset-translated topic copying). The two copies can disagree about what
"happened" at any given moment, and nothing reconciles that disagreement.

### b. False independence of failure domains
The entire premise of MirrorMaker2 is that primary and DR are **genuinely
independent** — a disaster that takes out primary should not be able to touch DR.
Here, both "clusters" would live on the *same* stretched vSphere cluster and the
*same* underlying vSAN datastore group. A storage-layer incident — a bad
failover, a witness outage causing an object access loss, a split-brain at the
vSAN layer — can affect both sites, and therefore both Kafka clusters,
**simultaneously**. The MM2 "DR" copy gives a false sense of safety it cannot
actually deliver, because it doesn't protect against the failure modes that
matter most here.

### c. Latency stacking
vSAN Stretched Cluster already pays a synchronous cross-site round trip on every
write that needs to be acknowledged on both sites. If Kafka brokers for the
"primary" cluster are themselves spread in a way that *also* requires cross-site
ISR acknowledgement (e.g. by accident of pod scheduling), writes now pay the
cross-site cost twice: once at the storage layer, once at the Kafka replication
layer. Throughput and latency could degrade in surprising, hard-to-diagnose ways.

### d. Operational complexity without a matching benefit
MM2 brings real operational cost: offset translation, consumer-group migration
tooling, replication lag monitoring, potential for inexact (`at-least-once`)
delivery semantics across the mirror, and a second Strimzi operator/cluster to
patch and upgrade. All of that cost is justified when primary and DR are truly
separate failure domains. It is much harder to justify when both sides are
secretly sharing the same underlying storage fabric and (likely) the same
physical network.

### e. Split-brain risk under partition
If the link between the two sites is ever partitioned, an **active/active** MM2
setup (or even active/passive with a botched failover) could let both sides
accept independent writes that can never be cleanly merged — producing
permanently divergent histories. A single rack-aware Kafka cluster with
`acks=all` and a sane `min.insync.replicas` fails *closed* (stops accepting
writes it can't safely replicate) rather than *open* (accepting writes on both
sides that later conflict).

**Bottom line:** MirrorMaker2 solves a problem the customer doesn't actually
have (two truly independent sites), while doing nothing about the problem they
do have (one logical environment that needs to be made site-aware internally).

## 3. Recommended architecture

### a. One Kafka cluster, not two
Replace the primary+DR+MM2 topology with a **single Kafka cluster** that spans
both halves of the stretch cluster, made failure-domain-aware internally via
Strimzi rack awareness. This maps directly onto what the storage layer is
already doing (sync-replicating across two sites), instead of fighting it.

### b. Label nodes by physical site and use rack awareness
Whoever manages the vSphere/stretch layer needs to expose which site each
Kubernetes node physically lives in — Kubernetes has no innate knowledge of
this. Label nodes accordingly (e.g. `topology.kubernetes.io/zone=site-a` /
`site-b`), then configure Strimzi:

```yaml
spec:
  kafka:
    rack:
      topologyKey: topology.kubernetes.io/zone
    config:
      replica.selector.class: org.apache.kafka.common.replica.RackAwareReplicaSelector
```

Combine this with pod anti-affinity / topology spread constraints on the broker
`KafkaNodePool` so the scheduler, not just Kafka's internal placement logic,
guarantees replicas land on both sites.

### c. Solve control-plane quorum the same way storage already did
This is the most important structural gap. The existing vSAN witness solves
*storage* quorum with a third, independent site. Kubernetes `etcd` and Kafka's
KRaft controllers need the **same treatment** and don't currently have it:

- Ask whether the witness appliance's site (or any third, truly independent
  location) could also host a lightweight third Kubernetes control-plane node
  and/or a controller-only Kafka node. Reusing that existing third site/trust
  relationship is the cleanest fix.
- If no third site is achievable, document the asymmetry explicitly: e.g. 3
  controllers split 2/1 across the two sites, decide up front which site "wins"
  in a split, and treat losing the majority site as a manual-recovery runbook
  event rather than something expected to self-heal.
- Do not try to paper over this by adding more brokers — replica count fixes
  data availability, not controller election.

### d. Size replication around the storage layer, not against it
Given storage is already synchronously mirrored, there's no need to over-size
Kafka's own replication factor purely for "disk redundancy" — that's already
handled a layer down. Size `replicationFactor` / `min.insync.replicas` for
**broker and process availability** (surviving the loss of brokers/pods in one
site), not to re-solve a problem vSAN already solves. A reasonable starting
point: RF=4 split 2/2 across sites with `min.insync.replicas=3`, tuned once real
latency numbers are confirmed.

### e. Keep storage replication and Kafka replication from fighting each other
Where possible, get Kafka broker volumes excluded from the synchronous
storage-replication/consistency group, or at least get confirmation of exactly
what's protected. Having both layers independently "fix" the same failure can
mask problems (e.g., restoring a stale, storage-level snapshot that doesn't
match what Kafka's own controller metadata expects) rather than solve them.

## 4. Open questions to take back to the customer

1. Is `etcd`/the Kubernetes control plane itself stretched across both sites, or
   only the worker nodes? (Determines whether K8s quorum is already broken.)
2. Confirm the storage replication technology and mode precisely — vSAN
   Stretched Cluster, array-based SRM, something else; synchronous or async.
3. What is the actual measured RTT and bandwidth between the two sites? (vSAN
   Stretched Cluster implies ≤5 ms RTT — if confirmed, that's good news for
   running Kafka's own synchronous cross-site replication too.)
4. Where does the vSAN witness physically/logically live, and could that same
   site host a Kubernetes/Kafka control-plane witness/arbiter node?
5. Are Kafka broker volumes included in the storage-level replication
   consistency group today, and can they be excluded?
6. Is there any requirement for a genuine third, independent DR site beyond the
   stretch cluster (this is the one scenario where MirrorMaker2 still earns its
   keep)?

## 5. Suggested changes to this repo

- Treat [terraform/cluster](terraform/cluster) (two independent Hetzner k3s
  clusters) as a **local prototyping rig only**, useful for testing the
  rack-aware Strimzi config before it goes anywhere near the customer's actual
  environment — not as the shape of the real deployment.
- Replace the primary/DR + MirrorMaker2 manifests under
  [kubernetes/strimzi](kubernetes/strimzi) with a single rack-aware
  `Kafka`/`KafkaNodePool` definition, driven by the site topology label once
  it's confirmed.
- Keep MirrorMaker2 in the toolbox but reframe it as the answer to open question
  6 (a genuine third-site DR target), not as the primary/DR bridge within the
  stretch cluster itself.
