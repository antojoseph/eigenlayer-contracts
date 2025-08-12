#!/usr/bin/env bash
set -euo pipefail

############################################
# Config (override via env)
############################################
AWS_REGION="${AWS_REGION:-us-east-1}"
SECRET_NAME="${SECRET_NAME:-bn254/enclave-key-yooo}"

# Optional: if set, we will STS AssumeRole and pass those creds into enclave
ASSUME_ROLE_ARN="${ASSUME_ROLE_ARN:-}"         # e.g. arn:aws:iam::123456789012:role/EnclaveWriter
ASSUME_DURATION="${ASSUME_DURATION:-900}"      # 15m..3600s

# Enclave sizing (use >= 1024 MiB for stability)
ENCLAVE_CPU="${ENCLAVE_CPU:-2}"
ENCLAVE_MEM_MIB="${ENCLAVE_MEM_MIB:-1088}"

# Vsock ports
PROXY_VSOCK_PORT="${PROXY_VSOCK_PORT:-8000}"   # parent vsock-proxy -> secretsmanager:443
CREDS_VSOCK_PORT="${CREDS_VSOCK_PORT:-7000}"   # parent -> enclave (send STS creds)

# Image/EIF
APP_IMG_NAME="${APP_IMG_NAME:-bn254-enclave-direct:latest}"
EIF_NAME="${EIF_NAME:-bn254-enclave-direct.eif}"

# Debug: keep enclave alive for console (KEEP_OPEN=true ./directsc.sh)
KEEP_OPEN="${KEEP_OPEN:-false}"

############################################
# Pre-flight
############################################
need() { command -v "$1" >/dev/null || { echo "Missing dependency: $1"; exit 1; }; }
for cmd in nitro-cli aws docker go jq vsock-proxy curl; do need "$cmd"; done
: "${AWS_REGION:?set AWS_REGION}"
WORKDIR="$(mktemp -d)"; trap 'rm -rf "$WORKDIR"' EXIT

############################################
# Start vsock-proxy (raw TCP tunnel)
############################################
SM_HOST="secretsmanager.${AWS_REGION}.amazonaws.com"
echo "Starting vsock-proxy on $PROXY_VSOCK_PORT -> $SM_HOST:443"
vsock-proxy "$PROXY_VSOCK_PORT" "$SM_HOST" 443 >/dev/null 2>&1 &
VSOCK_PROXY_PID=$!
cleanup_proxy(){ kill "$VSOCK_PROXY_PID" >/dev/null 2>&1 || true; }
trap cleanup_proxy EXIT

############################################
# Enclave program (Go)
############################################
cat >"$WORKDIR/enclave_main.go" <<'EOF'
package main

import (
        "context"
        "crypto/rand"
        "crypto/tls"
        "encoding/hex"
        "encoding/json"
        "errors"
        "fmt"
        "log"
        "math/big"
        "net"
        "net/http"
        "os"
        "strconv"
        "time"

        "github.com/aws/aws-sdk-go-v2/aws"
        "github.com/aws/aws-sdk-go-v2/config"
        "github.com/aws/aws-sdk-go-v2/credentials"
        sm "github.com/aws/aws-sdk-go-v2/service/secretsmanager"
        smtypes "github.com/aws/aws-sdk-go-v2/service/secretsmanager/types"
        smithyhttp "github.com/aws/smithy-go/transport/http"
        "github.com/mdlayher/vsock"
        "golang.org/x/crypto/bn256"
)

const parentCID = uint32(3)

var rOrder = func() *big.Int {
        v, _ := new(big.Int).SetString("30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001", 16)
        return v
}()

type stsCreds struct {
        AccessKeyId     string `json:"AccessKeyId"`
        SecretAccessKey string `json:"SecretAccessKey"`
        SessionToken    string `json:"SessionToken"`
        Region          string `json:"Region"`
        SecretName      string `json:"SecretName"`
        ProxyVsockPort  uint32 `json:"ProxyVsockPort"`
}

func listenForCreds(port uint32) (*stsCreds, error) {
        ln, err := vsock.Listen(port, nil)
        if err != nil { return nil, fmt.Errorf("vsock listen: %w", err) }
        defer ln.Close()
        _ = ln.SetDeadline(time.Now().Add(5 * time.Minute))
        c, err := ln.Accept()
        if err != nil { return nil, fmt.Errorf("accept: %w", err) }
        defer c.Close()
        var sc stsCreds
        if err := json.NewDecoder(c).Decode(&sc); err != nil { return nil, fmt.Errorf("decode: %w", err) }
        return &sc, nil
}

func vsockHTTPClient(proxyPort uint32, serverName string) *http.Client {
        // Raw TCP to parent vsock-proxy (forwards to Secrets Manager).
        dialContext := func(ctx context.Context, network, addr string) (net.Conn, error) {
                return vsock.Dial(parentCID, proxyPort, nil)
        }
        tlsCfg := &tls.Config{ MinVersion: tls.VersionTLS12, ServerName: serverName }
        tr := &http.Transport{
                DialContext:     dialContext,
                IdleConnTimeout: 30 * time.Second,
                TLSClientConfig: tlsCfg,
        }
        return &http.Client{Transport: tr, Timeout: 30 * time.Second}
}

func randScalarFr() (*big.Int, []byte) {
        for {
                b := make([]byte, 32)
                if _, err := rand.Read(b); err != nil { log.Fatalf("rand: %v", err) }
                k := new(big.Int).SetBytes(b)
                if k.Sign() != 0 && k.Cmp(rOrder) < 0 { return k, b }
        }
}

func main() {
        _ = os.Setenv("AWS_EC2_METADATA_DISABLED", "true")

        credsPort := uint32(7000)
        if v := os.Getenv("CREDS_VSOCK_PORT"); v != "" {
                if p, err := strconv.Atoi(v); err == nil && p > 0 && p < 65536 { credsPort = uint32(p) }
        }
        sc, err := listenForCreds(credsPort)
        if err != nil { log.Fatalf("creds: %v", err) }

        smHost := "secretsmanager." + sc.Region + ".amazonaws.com"
        httpc := vsockHTTPClient(sc.ProxyVsockPort, smHost)
        provider := credentials.NewStaticCredentialsProvider(sc.AccessKeyId, sc.SecretAccessKey, sc.SessionToken)

        cfg, err := config.LoadDefaultConfig(
                context.Background(),
                config.WithRegion(sc.Region),
                config.WithCredentialsProvider(provider),
                config.WithHTTPClient(httpc),
        )
        if err != nil { log.Fatalf("aws config: %v", err) }

        client := sm.NewFromConfig(cfg)

        // BN254 keypair
        k, raw := randScalarFr()
        pub := new(bn256.G1).ScalarBaseMult(k)
        pubBytes := pub.Marshal()
        payload := `{"curve":"bn254","priv_hex":"0x` + hex.EncodeToString(raw) + `","pub_hex":"0x` + hex.EncodeToString(pubBytes) + `"}`

        // Create or update
        _, err = client.CreateSecret(context.Background(), &sm.CreateSecretInput{
                Name:         &sc.SecretName,
                SecretString: aws.String(payload),
        })
        if err != nil {
                var re *smithyhttp.ResponseError
                if errors.As(err, &re) {
                        log.Printf("CreateSecret HTTP error: %s", re.Error())
                }
                var exists *smtypes.ResourceExistsException
                if errors.As(err, &exists) {
                        _, err2 := client.PutSecretValue(context.Background(), &sm.PutSecretValueInput{
                                SecretId:     &sc.SecretName,
                                SecretString: aws.String(payload),
                        })
                        if err2 != nil { log.Fatalf("PutSecretValue failed: %v", err2) }
                } else {
                        log.Fatalf("CreateSecret failed: %v", err)
                }
        }

        // Zeroize
        for i := range raw { raw[i] = 0 }

        if os.Getenv("KEEP_OPEN") == "true" {
                log.Printf("KEEP_OPEN=true; sleeping for 300s for console inspection")
                time.Sleep(300 * time.Second)
        }
}
EOF

cat >"$WORKDIR/go.mod" <<'EOF'
module enclave-app
go 1.22
require (
  github.com/aws/aws-sdk-go-v2 v1.30.5
  github.com/aws/aws-sdk-go-v2/config v1.27.21
  github.com/aws/aws-sdk-go-v2/credentials v1.17.47
  github.com/aws/aws-sdk-go-v2/service/secretsmanager v1.32.6
  github.com/aws/smithy-go v1.22.1
  github.com/mdlayher/vsock v1.2.1
  golang.org/x/crypto v0.26.0
)
EOF

cat >"$WORKDIR/Dockerfile" <<'EOF'
# Build
FROM golang:1.22 AS build
WORKDIR /src
COPY go.mod .
COPY enclave_main.go .
RUN go mod tidy
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/enclave-app enclave_main.go

# CA bundle
FROM public.ecr.aws/amazonlinux/amazonlinux:2 AS certs
RUN yum install -y ca-certificates && update-ca-trust

# Runtime
FROM scratch
COPY --from=certs /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt
COPY --from=build /out/enclave-app /enclave-app
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV CREDS_VSOCK_PORT=7000
ENV AWS_EC2_METADATA_DISABLED=true
ENV KEEP_OPEN=false
ENTRYPOINT ["/enclave-app"]
EOF

docker build -t "$APP_IMG_NAME" "$WORKDIR" >/dev/null

############################################
# Build EIF + run enclave (tolerate text/JSON)
############################################
nitro-cli build-enclave --docker-uri "$APP_IMG_NAME" --output-file "$EIF_NAME" >/dev/null
RUN_OUT="$(
  nitro-cli run-enclave \
    --eif-path "$EIF_NAME" \
    --cpu-count "$ENCLAVE_CPU" \
    --memory "$ENCLAVE_MEM_MIB" \
    --debug-mode
)"
echo "$RUN_OUT"

# Parse CID from text
CID="$(printf '%s\n' "$RUN_OUT" | sed -n 's/.*enclave-cid:[[:space:]]*\([0-9]\+\).*/\1/p' | head -n1)"
# Parse JSON block for ID/CID if present
JSON_BLOCK="$(printf '%s\n' "$RUN_OUT" | awk '/^\s*{/{f=1} f{print} /^\s*}/{f=0}')"
if [[ -n "$JSON_BLOCK" ]]; then
  ENCLAVE_ID="$(printf '%s' "$JSON_BLOCK" | jq -r '.EnclaveID // empty' 2>/dev/null || true)"
  [[ -z "${CID:-}" ]] && CID="$(printf '%s' "$JSON_BLOCK" | jq -r '.EnclaveCID // empty' 2>/dev/null || true)"
fi
# Last resort: describe-enclaves
if [[ -z "${CID:-}" ]]; then
  CID="$(nitro-cli describe-enclaves 2>/dev/null | awk '/CID:/ {print $2}' | tail -n1 || true)"
fi
: "${CID:?failed to get enclave CID}"
echo "Enclave CID: $CID"
[[ -n "${ENCLAVE_ID:-}" ]] && echo "Enclave ID: $ENCLAVE_ID" || echo "Warning: could not resolve Enclave ID; proceeding with CID=$CID"

############################################
# STS creds for enclave
#   1) If ASSUME_ROLE_ARN is set -> sts:AssumeRole
#   2) Else -> pull instance profile creds from IMDSv2
############################################
fetch_creds() {
  if [[ -n "${ASSUME_ROLE_ARN}" ]]; then
    aws sts assume-role \
      --role-arn "$ASSUME_ROLE_ARN" \
      --role-session-name "enclave-writer-$(date +%s)" \
      --duration-seconds "${ASSUME_DURATION}" \
      --region "$AWS_REGION"
    return
  fi

  # IMDSv2 flow (instance profile temporary creds)
  TOKEN="$(curl -sS --retry 3 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")"
  ROLE="$(curl -sS --retry 3 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)"
  curl -sS --retry 3 -H "X-aws-ec2-metadata-token: $TOKEN" \
       "http://169.254.169.254/latest/meta-data/iam/security-credentials/${ROLE}"
}

CREDS_JSON="$(fetch_creds)"
AKID="$(jq -r '.Credentials.AccessKeyId // .AccessKeyId' <<<"$CREDS_JSON")"
SAK="$(jq -r '.Credentials.SecretAccessKey // .SecretAccessKey' <<<"$CREDS_JSON")"
STOK="$(jq -r '.Credentials.SessionToken // .Token // .SessionToken' <<<"$CREDS_JSON")"

: "${AKID:?no AccessKeyId from STS/IMDS}"
: "${SAK:?no SecretAccessKey from STS/IMDS}"
: "${STOK:?no SessionToken from STS/IMDS}"

############################################
# send-creds helper (with retry)
############################################
cat >"$WORKDIR/send_creds.go" <<'EOF'
package main
import (
        "encoding/json"
        "flag"
        "log"
        "time"
        "github.com/mdlayher/vsock"
)
type payload struct {
        AccessKeyId     string `json:"AccessKeyId"`
        SecretAccessKey string `json:"SecretAccessKey"`
        SessionToken    string `json:"SessionToken"`
        Region          string `json:"Region"`
        SecretName      string `json:"SecretName"`
        ProxyVsockPort  uint32 `json:"ProxyVsockPort"`
}
func main() {
        var cid uint64; var port uint64; var proxyPort uint64
        var ak, sk, st, region, secret string
        flag.Uint64Var(&cid, "cid", 0, "enclave CID")
        flag.Uint64Var(&port, "port", 7000, "vsock port (creds)")
        flag.Uint64Var(&proxyPort, "proxy-port", 8000, "vsock proxy port to parent")
        flag.StringVar(&ak, "akid", "", ""); flag.StringVar(&sk, "sak", "", ""); flag.StringVar(&st, "stok", "", "")
        flag.StringVar(&region, "region", "", ""); flag.StringVar(&secret, "secret", "", "")
        flag.Parse()
        if cid==0 || ak=="" || sk=="" || st=="" || region=="" || secret=="" { log.Fatal("missing flags") }

        var lastErr error
        for i:=0; i<30; i++ {
                c, err := vsock.Dial(uint32(cid), uint32(port), nil)
                if err != nil { lastErr = err; time.Sleep(500*time.Millisecond); continue }
                defer c.Close()
                pl := payload{AccessKeyId: ak, SecretAccessKey: sk, SessionToken: st, Region: region, SecretName: secret, ProxyVsockPort: uint32(proxyPort)}
                if err := json.NewEncoder(c).Encode(pl); err != nil { lastErr = err; time.Sleep(300*time.Millisecond); continue }
                return
        }
        log.Fatalf("failed to deliver creds: %v", lastErr)
}
EOF

cat >"$WORKDIR/send_go.mod" <<'EOF'
module sender
go 1.22
require github.com/mdlayher/vsock v1.2.1
EOF

pushd "$WORKDIR" >/dev/null
go mod tidy >/dev/null
CGO_ENABLED=0 go build -o send-creds send_creds.go
popd >/dev/null

"$WORKDIR/send-creds" \
  -cid "$CID" \
  -port "$CREDS_VSOCK_PORT" \
  -proxy-port "$PROXY_VSOCK_PORT" \
  -akid "$AKID" -sak "$SAK" -stok "$STOK" \
  -region "$AWS_REGION" -secret "$SECRET_NAME"

echo "Creds delivered. Enclave will write the secret directly to Secrets Manager."

############################################
# Verify (best-effort)
############################################
sleep 6
if aws --region "$AWS_REGION" secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  echo "Secret present: $SECRET_NAME"
else
  echo "Secret not found yet. Check enclave console (KEEP_OPEN=true)."
fi

############################################
# Teardown (best effort; skip if KEEP_OPEN=true)
############################################
if [[ "${KEEP_OPEN}" != "true" ]]; then
  if [[ -z "${ENCLAVE_ID:-}" ]]; then
    ENCLAVE_ID="$(nitro-cli describe-enclaves | awk -v target="$CID" '
      $1=="Enclave" && $2=="ID:" {id=$3}
      $1=="CID:" {cid=$2; if (cid==target) {print id; exit}}
    ')"
  fi
  [[ -n "${ENCLAVE_ID:-}" ]] && nitro-cli terminate-enclave --enclave-id "$ENCLAVE_ID" >/dev/null || true
else
  echo "KEEP_OPEN=true; not terminating enclave."
fi
cleanup_proxy
echo "Done." 