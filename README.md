# このリポジトリについて
GCPのドキュメントで説明されている[GKEとプロキシレスgRPCを利用してTraffic Directorを構成する手順](https://cloud.google.com/traffic-director/docs/set-up-proxyless-gke?hl=ja)をterraform化したものです。

## デプロイ手順
GKE Clusterを構成
```sh
cd gke_cluster
terraform apply -var gcp_project_id=YOUR_PROJECT_ID
```

Traffic Directorを構成
```sh
cd traffic_director
terraform apply -var gcp_project_id=YOUR_PROJECT_ID
```

## 確認手順

gRPCクライアントのpodにログイン
```sh
gcloud container clusters get-credentials grpc-td-cluster
kubectl exec -it $(kubectl get pods -o custom-columns=:.metadata.name \
    --selector=run=client) -- /bin/bash
```

gRPCをコール
```sh
curl -L https://github.com/fullstorydev/grpcurl/releases/download/v1.8.1/grpcurl_1.8.1_linux_x86_64.tar.gz | tar -xz
./grpcurl --plaintext \
  -d '{"name": "world"}' \
  xds:///helloworld-gke:8000 helloworld.Greeter/SayHello
```
