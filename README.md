# Overmind [![travis badge](https://travis-ci.org/nietaki/overmind.svg?branch=master)](https://travis-ci.org/nietaki/overmind) ![Coverage](https://img.shields.io/coveralls/github/nietaki/overmind/master.svg)

Multinode, persistent, consistent, scalable, named virtual actors.

## Motivation

I realised that when working with Elixir I often end up writing a similar
system - long running gen_servers representing domain entities (user profiles,
chatrooms, organisations) and having them save their state to a database
every time they handle a message. While this approach works, it requires you
to write a good amount actor lifecycle and persistence boilerplate code.
Moreover it's hard to scale beyond a single node, especially while
maintaining consistence in the face of network partitions and nodes dying or
being dynamically added and removed.

I also wanted to finally make good use of consistent hashing :D

## Inspirations

- [riak core](https://github.com/Kyorai/riak_core)
- @myobie's [zk_registry](https://github.com/myobie/zk_registry) and his talk at CodeBeam STO
- @CrowdHailer, his musings on pure actors and his work on [pachyderm](https://github.com/CrowdHailer/event-sourcing.elixir)
- [erleans](https://github.com/SpaceTime-IoT/erleans)

## How is it supposed to work?

The authoritative list of participating Elixir nodes is maintained in Zookeeper
and updated by one of the nodes which is elected as a leader. Virtual actors
(identified by a `{type, id :: String.t}` tuple) are assigned to the individual
nodes using consistent hashing.

When you send a message to a virtual actor, it gets routed to the node responsible
for it and if the actor process isn't already running, it gets "activated" using
its previous persisted state or spawned fresh if it doesn't exist yet. After
handling the message the virtual actor's state is persisted. After a period of
inactivity the actor can be powered down to save memory.

When nodes join or leave the cluster, the virtual actors get re-partitioned -
the ones that now belong to a different node get powered down on the previous one.
We'll make sure that at any point in time there's no more than one running
virtual actor for a given actor_id.

Unlike Orleans, which favours availability over consistency, Overmind will strive
to remain consistent in adverse conditions, even if it means taking a performance hit.
It does aim for high performance and uniform load distribution across the nodes
when the cluster remains stable.

## Roadmap

### First

- [x] Get a feel for using ZK from Elixir
- [ ] per-node Coordinator actor to handle cluster membership changes
  - [x] a nice state diagram for it
- [ ] registry for local virtual actors
- [ ] virtual actor wrapper to separate the actor process and its lifecycle management
- [ ] saving actor state to the db

### Afterwards
- [ ] Batching db saves for performance
- [ ] Replicate the actor state to secondary nodes (potentially db-less operation)
- [ ] Look into message guarantees
- [ ] accounting for situation when Elixir node can connect to ZK but can't see other nodes

### Someday Maybe

- [ ] long running / active actors (activated as soon as they get moved between the nodes)
- [ ] secondary saving / saving hooks (i.e. for maintaining indexes based on actor state)

### Non-goals
