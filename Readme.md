# Redeth

Redeth is a mini fetching system for eth api competitors.

## TODO

- mock jobs executing and ack with Redis ✅
- mock jobs creating with Redis ✅
- Creating jobs dynamically with a mock block range. ✅
- Update block range with api ✅
- Support multiple API entrypoints
- Support reducing workers ✅
- Secure Redis ✅
- K8s definations ✅

## Usage

Outter service dependencies
- A chain node RPC entrypoint, like "https://polygon.api.onfinality.io/rpc?apikey=bb33ca96-9719-497e-bf06-c291ffed46b4"
- A Google bucket and a Google Service Account. The related cert file should be in K8s secret.

Deploy
- Deploy redis with password.
- Config main.yaml and worker.yaml with outter service dependencies.
- Apply the two yaml.

## Arch

```
 ┌──────────┐                               ┌─────────────────┐
 │Node RPC  │                               │ Google Bucket   │
 │          ├──────────┐           ┌────────►                 │
 └─────┬────┘          │           │        └───────────▲─────┘
       │               │           │                    │
       │               │           │                    │
       │               │           │                    │
       │          ┌────▼───────────┴───┐                │
       │          │ Worker             ├─┐              │
       │          │                    │ ├─┐            │
 ┌─────▼───────┐  └──┬─────────────────┘ │ │            │
 │ Generator   │     │                   │ │       ┌────┴────┐
 │             │     └───┬───────────────┘ │       │ Sorter  │
 └─────┬───────┘         │                 │       │         │
       │                 └────▲────────────┘       └────▲────┘
       │                      │                         │
       │                      │                         │
       │                 ┌────┴───┐                     │
       └────────────────►│Redis   ├─────────────────────┘
                         └────────┘
```

The `generator` will creat fetching job message into redis stream. Its related code is located in `./generator/`. The `worker` will process all fetching job message. Its related scripts is `./scripts/worker.sh`.  After that, `sorter` will make sure the blocks is continuously incremented. Its related scripts is `./scripts/sorter.sh`. `worker` and `sorter` share one docker image, `./scripts/Dockerfile`. The `generator` and `sorter` are in one K8s Pod, `./yaml/main.yaml`. The workers are in `./yaml/workers.yaml`.