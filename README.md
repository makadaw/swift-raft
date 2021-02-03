# swift-raft

Swift implementation of the (Raft protocol)[https://raft.github.io/raft.pdf]

https://github.com/ongardie/dissertation/blob/master/online-trim.pdf

## Implementation

### Raft

[x] Leader Election

[ ] Log Replecation

[ ] Safety

    [ ] Election restriction
    [ ] Commiting entries from previous terms
    
[ ] Peristed state (term and log)

    [ ] Memory log
    [ ] Segmented log

[ ] Leadership Transfer

### Cluster membership

[x] Fixed peers

[ ] Add/Remove server RPC call

[ ] New servers log distribution

### Log compaction

[ ] Memory based snapshots
