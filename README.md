# swift-raft

Swift implementation of the [Raft protocol](https://raft.github.io/raft.pdf), [more detailed paper](https://github.com/ongardie/dissertation/blob/master/online-trim.pdf)

Visualisation of the [protocol](http://thesecretlivesofdata.com/raft/)

## Implementation

### Raft

- [x] Leader Election
- [ ] Log Replecation
- [ ] Safety
  - [ ] Election restriction
  - [ ] Commiting entries from previous terms
- [ ] Peristed state (term and log)
  - [ ] Memory log
  - [ ] Segmented log
- [ ] Leadership Transfer

### Cluster membership

- [x] Fixed peers
- [ ] Add/Remove server RPC call
- [ ] New servers log distribution

### Log compaction

- [ ] Memory based snapshots

## Development
- [ ] Add Linux tests
- [ ] Setup CI

## Maelstrom tests

Run Jepsen tests with [maelstrom](https://github.com/jepsen-io/maelstrom).
```
maelstrom test -w lin-kv --bin maelstrom-node --time-limit 10 --rate 10 --nodes 1 2 3
```

Where `maelstrom-node` is a bin. 
And `--nodes` list of nodes in local cluster.

`maelstrom-node` also can be a bash wrapper, if you want to run binary with snapshot toolchain 

```
#!/usr/bin/env bash

# Add toolchain libs to the library path. Need for _Concurrency library.
export DYLD_FALLBACK_LIBRARY_PATH=/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2021-03-02-a.xctoolchain/usr/lib/swift/macosx

# Run compiled binary
exec .build/debug/maelstrom-node
```

## Contribution

To compile the project you need to use [snapshot](https://swift.org/download/#snapshots) toolchain with Actors support.
