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

## 6. Team discussion log (2026-10-02)

This section preserves the internal discussion that followed this analysis, for
traceability. Blockquoted entries marked **Copilot reflection** are this
assistant's analysis; everything else is quoted verbatim from the people
named.

### 6.1 Does rack labels + a 3rd Kafka instance + the existing vSAN setup already give HA?

**Question raised:** if we have reliable node labels (for rack/affinity) and a
3rd Kafka instance for quorum, is the existing vSAN solution sufficient for a
HA Kafka cluster?

> **Copilot reflection:** Not quite. Rack/zone node labels solve *replica
> placement* (§3b), but a 3rd Kafka controller only truly solves quorum if it
> sits in a genuinely independent third location. If it's just placed inside
> one of the two existing sites, you get an asymmetric 2/1 split: losing the
> site with 1 controller is fine, losing the site with 2 is not (no quorum,
> manual recovery). vSAN's witness only ever covers *storage* quorum — it says
> nothing about Kafka controller (KRaft) or Kubernetes `etcd` quorum, both of
> which remain unanswered (open question #1).

### 6.2 Thomas's email to Isabel, for forwarding to the NNIT Platform team

Thomas (developer, same team) sent the following, asking whether an "even/odd"
datacenter indication NNIT mentioned could be used as a supported scheduling
mechanism for Kafka A / Kafka B + MirrorMaker2 placement:

> Hi Isabel,
> We have spoken with the NNIT Platform team and were told that workloads can
> apparently be identified as "even" or "odd" depending on datacenter placement.
> I'm trying to understand whether this can be used as a supported deployment
> mechanism for the NAIP Kafka platform. Could you please forward this to the
> relevant NNIT team?
> We are currently designing the NAIP Kafka platform and need clarification
> regarding workload placement in the Kubernetes platform.
> Our understanding is that the Kubernetes platform is a stretched cluster
> spanning two physical datacenters.
> For NAIP, the intended architecture is to run two independent Kafka
> clusters, Kafka A and Kafka B, with replication between them using
> MirrorMaker2. The goal is to place Kafka A in one datacenter and Kafka B in
> the other so they represent separate failure domains.
> From the application side, we can configure node affinity, pod
> anti-affinity, topology spread constraints, Kafka rack awareness, separate
> Strimzi KafkaNodePools and MirrorMaker2 replication.
> What we need is a stable platform-provided scheduling attribute that allows
> us to target a specific datacenter.
> What we cannot safely do is schedule based on pod numbering, StatefulSet
> ordinals, pod names, or an observed even/odd pod pattern. Those values do not
> represent a stable failure domain and can change when workloads are
> rescheduled.
> Could you help clarify the following?
> - Is there a supported node label identifying the datacenter or failure domain?
> - Is the even/odd indication available on nodes before scheduling, or only
>   visible on running pods?
> - Are application teams allowed to use that label in required node affinity
>   rules?
> - Are there dedicated node pools, taints, placement classes, or another
>   preferred mechanism for this use case?
> - Is the storage layer topology-aware so persistent volumes remain aligned
>   with the selected datacenter?
> - Are there any restrictions on KafkaNodePool affinity, anti-affinity, or
>   topology spread settings?
> Our objective is to deploy Kafka A and Kafka B as separate failure domains.
> If the even/odd indication is available as a stable node label before
> scheduling and is supported as part of the platform contract, we believe we
> can implement the placement ourselves using standard Kubernetes and Strimzi
> scheduling capabilities.
> — Thomas Bennedsen

> **Copilot reflection:** Two things worth separating in the reply: (1) the
> concrete platform questions (label name/stability, pre-scheduling
> availability, affinity usage rights, dedicated node pools/taints, storage
> topology-awareness, KafkaNodePool restrictions) are all reasonable and worth
> forwarding as-is; (2) regardless of the answer, this is still predicated on
> the two-independent-clusters + MirrorMaker2 design that §2 of this document
> already flags as risky on a shared stretched vSAN fabric. A solid
> datacenter label answers "how do we place things," not "should Kafka A/B +
> MM2 be the target architecture at all."

### 6.3 Clarifying that Thomas is a teammate, not the customer

**Note:** Thomas is a developer on the same team (not NRCC). The question was
whether Thomas's points above independently line up with the concerns already
raised in this document.

> **Copilot reflection:** Thomas's demand for a stable, documented platform
> label (rejecting even/odd pod-ordinal-style scheduling) matches §3b exactly.
> What he has not raised: the shared-storage false-independence problem (§2b),
> the double-replication consistency conflict (§2a), latency stacking (§2c),
> or — most notably — the Kafka controller/`etcd` quorum gap (§3c), which his
> questions don't touch at all since they're scoped to broker/data-plane
> placement only.

### 6.4 Raising the MM2 question in the team chat

The following was drafted with Copilot's help and posted (in Danish) to the
team chat, flagging the architecture question while being new to the team:

> Hej alle,
>
> Jeg har tænkt over noget ifm. Thomas' spørgsmål til NNIT om node-labels — ret
> mig endelig hvis jeg har misforstået noget.
>
> Som jeg forstår det, kører NRCC's Kubernetes-platform på et enkelt VMware
> "stretch cluster" (vSAN Stretched Cluster) fordelt på to fysiske sites,
> snarere end to reelt uafhængige datacentre.
>
> Hvis det er korrekt, bliver storage mellem de to sites sandsynligvis allerede
> synkront replikeret på bloklag af vSAN — og NNIT's brug af ordet "witness"
> peger også i den retning (vSAN Stretched Cluster kræver en witness til
> storage-quorum).
>
> Det gør mig utryg ved om vores nuværende design — to uafhængige Kafka-clustre
> (A/B) replikeret med MirrorMaker2 — reelt løser det problem, NRCC har:
>
> MirrorMaker2 løser et problem NRCC i virkeligheden ikke har: at A og B er to
> genuint uafhængige datacentre, der skal bindes sammen. Hvis begge clustres
> volumes i stedet ligger på samme stretched vSAN-datastore, er de ikke reelt
> uafhængige failure domains — en storage-hændelse kan ramme begge sider
> samtidig, og MM2 giver en falsk tryghed det ikke kan indfri.
>
> Til gengæld løser MM2 ikke det problem, NRCC faktisk har: Der er ikke noget i
> den nuværende Kubernetes-platform, der løser quorum-problemet. Den
> eksisterende vSAN-witness løser kun storage-quorum mellem de to sites — den
> er usynlig for og gør intet for hverken Kubernetes' eget etcd-quorum eller
> Kafka's controller-quorum (KRaft/ZooKeeper). Det er separate kontrolplaner
> med egne flertalskrav, som witness'en ikke dækker.
>
> Vi ville desuden ende med at replikere de samme data to gange med to
> forskellige konsistensmodeller (synkron blok-replikering i vSAN + asynkron,
> applikationslag-replikering i MM2), hvilket kan give uenighed mellem de to
> kopier - potentielt katastrofalt.
>
> Et alternativ kunne være ét samlet, rack-aware Kafka-cluster der spænder over
> begge sites (via Strimzi rack.topologyKey + pod anti-affinity/topology spread
> = hvad Thomas har spurgt om), kombineret med at vi får løst quorum-problemet
> rigtigt — f.eks. ved at placere en tredje, uafhængig controller/arbiter-node
> samme sted som vSAN-witness'en (hvis man overhovedet kan det).
>
> Jeg ved ikke om vi er kontraktligt forpligtet til at levere MM2 — hvis det er
> tilfældet, er resten nok mindre relevant. Men hvis der er mulighed for det,
> synes jeg det kunne være værd at tage en runde på, om MM2-tilgangen stadig
> giver mening givet den faktiske topologi hos NRCC.
>
> alternativt kunne vi bede om at volumes med kafka data ikke replikeres og
> køre videre med mirrormaker, men det virker som unødvendig kompliksitet

**Daniel (tech lead) replied:**

> Du har ret ang. det overordnede vmware setup. Jeg ved ikke med storage
> setup'et. Når de snakker om at man spejler storage mellem de to datacentre,
> tænker at de har to SAN, som indeholder alt, men det skal man nøje udspørge
> dem om.
>
> Witenss sitet er til vmware. Det er et eller andet rack i et kusteskab, så vi
> kan ikke få en kafka witness ind på den.
>
> Mht. san replikering: De 2 kafka clustere skal have hver deres pvc. Det
> vigtige er at storage og kafka er i samme DC. De kan så replikeres så
> lystigt man vil uden at de træder hinanden over tæerne. Det bliver bare 2
> gange spild af disk plads i hvert DC.
>
> Ovenstående er prædikeret på at SAN'erne i DC'erne er duplikater og ikke et
> eller andet stretch-noget, som kan flytte sig mellem DC'er.
>
> Der er 2 sites og ikke flere. Ellers vil man naturligvis have valgt et
> witness med 2x<ulige tal> kafka i hvert DC.

> **Copilot reflection:** Daniel agrees with the overall stretched-topology
> read, and — by confirming there are only 2 sites — indirectly confirms the
> quorum gap (§3c/§4) stays unresolved. He disagrees with/rules out reusing the
> vSAN witness site for a Kafka/K8s arbiter (it's VMware-only infrastructure,
> not general-purpose compute). He also raises a genuine open question: if the
> two SANs are independent duplicates rather than a single stretched
> datastore, and each Kafka cluster's PVC/pods stay fully within one DC, the
> "double replication conflict" risk may just be wasted disk space rather than
> a correctness problem — but by his own admission this only holds if storage
> is *not* actually stretched (open question #2 in §4).

### 6.5 Isabel shares a `topologySpreadConstraints` example from another project

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: nordic-rcc.net/datacenter
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: cimnet-auto
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: cimnet-auto
```

> **Copilot reflection:** This answers the core question from Thomas's email
> and §3b/§4: `nordic-rcc.net/datacenter` is a real, stable node label that
> exists pre-scheduling (required for a spread constraint to function at all),
> and another app team already depends on it with a hard
> `DoNotSchedule` requirement — strong evidence it's a supported platform
> contract. It slots directly into Strimzi as
> `rack.topologyKey: nordic-rcc.net/datacenter`, or into `nodeAffinity` for
> per-cluster DC pinning. Still open: whether the storage
> provisioner/StorageClass honors the same key so PVs land in the matching DC.

### 6.6 Nikolaj (senior architect) weighs in

> du har helt ret og vi har taget adskillige runder om det her og faktisk
> anbefalet ikke at anvende Kafka fordi det ser ud til at deres infrastruktur
> dårligt kan bære Kafka (Mongo og K8S er vel som sådan i samme båd?). De bør
> have 3 datacentre og storage defineret som LRS, ZRS og GRS så man kan vælge
> storage topologi. Deres K8S er også stretched og ikke federated eller bare
> aktiv/passiv. Jeg tror det er vigtigt at afklare om det vi bygger ovenpå
> faktisk er HA og har separate fault domains (jeg kan have mine tvivl). Altså
> har K8S control plane / etcd rent faktisk HA? Så skal vi lave et fuldt HA
> design er det nok at stille krav, altså skrive en fuldestgørende ADR som
> beskriver hvad der skal til - så må NRCC træffe beslutningerne. Det kan vi
> gøre når vi har fået svar på den mail Thomas sendte til Isabel. Det kan også
> være at det ændre sig med deres nye data centre. Så vores forudsætning er at
> storage er ZRS-ish - Geo replication er MM2 og ikke VMWare, så ingen GRS!
> udover pinning til DC for Kafka/KRaft er der også node pinning, så brokers
> ikke afvikles på de samme fysiske nodes.

> **Copilot reflection / summary:**
> 1. Agrees this has been raised before, and the team has previously
>    recommended against Kafka here given the infrastructure — likely applies
>    to MongoDB and Kubernetes itself too.
> 2. NRCC should really have 3 datacenters, with storage offered at selectable
>    LRS/ZRS/GRS redundancy tiers.
> 3. Confirms the stretched-cluster read; contrasts it with federated or
>    active/passive alternatives that would give cleaner fault-domain
>    separation.
> 4. Shares the same core doubt as open question #1: does the K8s control
>    plane/`etcd` actually have real HA with separate fault domains?
> 5. Proposed path: don't solve this unilaterally — write a thorough ADR
>    stating the requirements for full HA and let NRCC decide; wait for the
>    answer to Thomas's email first (and note NRCC's upcoming new datacenters
>    may change the picture).
> 6. Working assumption to proceed with: treat storage as **ZRS-like only**
>    (no GRS from VMware/storage) — i.e. MM2 is the sole mechanism for genuine
>    geo-replication/DR, not the storage layer.
> 7. Additional requirement beyond DC-level pinning: node-level pinning/
>    anti-affinity, so broker replicas don't share the same physical node
>    within a DC either.

### 6.7 Resolving Daniel's open storage question

**Question raised:** does Nikolaj's "storage is ZRS-ish" statement answer
Daniel's earlier doubt about whether storage is stretched at the storage level
too (§6.4)?

> **Copilot reflection:** Yes, and it confirms the riskier of Daniel's two
> hypotheses. ZRS means synchronous replication across DCs as a single logical
> service — i.e. genuinely stretched/coupled storage, not Daniel's alternative
> of two independent, duplicated SANs. Nikolaj also explicitly rules out GRS at
> the storage layer, leaving MM2 as the only geo-replication mechanism. This is
> stated as the team's working assumption, not yet a fact confirmed directly by
> NRCC — that confirmation is still pending the answer to Thomas's email.
