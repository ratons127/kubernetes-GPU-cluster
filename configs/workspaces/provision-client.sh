#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <client-id> <nodeport> [storage-size]" >&2
  echo "Example: $0 client03 31003 200Gi" >&2
  exit 1
fi

CLIENT_ID="$1"
NODEPORT="$2"
STORAGE_SIZE="${3:-200Gi}"
NAMESPACE="$CLIENT_ID"
PVC_NAME="${CLIENT_ID}-home"
DEPLOY_NAME="${CLIENT_ID}-jupyter"
SERVICE_NAME="${CLIENT_ID}-jupyter"
NODEPORT_SERVICE_NAME="${CLIENT_ID}-jupyter-nodeport"
SECRET_NAME="${CLIENT_ID}-jupyter-auth"
INGRESS_NAME="${CLIENT_ID}-jupyter"
DOMAIN="${DOMAIN:-betopialtd.com}"
PUBLIC_IP="${PUBLIC_IP:-103.149.105.249}"
HOSTNAME="${CLIENT_ID}.${DOMAIN}"
TOKEN="$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + '_-'
print(''.join(secrets.choice(alphabet) for _ in range(32)))
PY
)"
OUT="/root/k8s/${CLIENT_ID}.yaml"

cat > "$OUT" <<MANIFEST
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${CLIENT_ID}-quota
  namespace: ${NAMESPACE}
spec:
  hard:
    requests.cpu: "9"
    limits.cpu: "9"
    requests.memory: 25Gi
    limits.memory: 33Gi
    requests.storage: ${STORAGE_SIZE}
    requests.nvidia.com/gpu: "1"
    limits.nvidia.com/gpu: "1"
    pods: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: ${CLIENT_ID}-defaults
  namespace: ${NAMESPACE}
spec:
  limits:
    - type: Container
      default:
        cpu: "8"
        memory: 32Gi
      defaultRequest:
        cpu: "8"
        memory: 24Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  JUPYTER_TOKEN: "${TOKEN}"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: ${STORAGE_SIZE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOY_NAME}
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DEPLOY_NAME}
  template:
    metadata:
      labels:
        app: ${DEPLOY_NAME}
    spec:
      runtimeClassName: nvidia
      securityContext:
        fsGroup: 1000
      containers:
        - name: jupyter
          image: pytorch/pytorch:2.1.2-cuda11.8-cudnn8-runtime
          imagePullPolicy: IfNotPresent
          command:
            - bash
            - -lc
            - >
              python -m pip install --no-cache-dir --user jupyterlab==4.2.5 notebook==7.2.1 &&
              python -m jupyter lab
              --ip=0.0.0.0
              --port=8888
              --no-browser
              --ServerApp.root_dir=/workspace
              --ServerApp.token="\$JUPYTER_TOKEN"
              --ServerApp.allow_origin='*'
              --ServerApp.disable_check_xsrf=True
          ports:
            - containerPort: 8888
          env:
            - name: HOME
              value: /workspace
            - name: PATH
              value: /workspace/.local/bin:/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            - name: JUPYTER_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ${SECRET_NAME}
                  key: JUPYTER_TOKEN
          resources:
            requests:
              cpu: "8"
              memory: "24Gi"
            limits:
              cpu: "8"
              memory: "32Gi"
              nvidia.com/gpu: 1
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
---
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${DEPLOY_NAME}
  ports:
    - name: http
      port: 80
      targetPort: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: ${NODEPORT_SERVICE_NAME}
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: ${DEPLOY_NAME}
  ports:
    - name: http
      port: 80
      targetPort: 8888
      nodePort: ${NODEPORT}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${INGRESS_NAME}
  namespace: ${NAMESPACE}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/service-upstream: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
    nginx.ingress.kubernetes.io/proxy-body-size: "20g"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ${HOSTNAME}
      secretName: ${CLIENT_ID}-${DOMAIN//./-}-tls
  rules:
    - host: ${HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${SERVICE_NAME}
                port:
                  number: 80
MANIFEST

echo "Manifest: $OUT"
echo "Token: $TOKEN"
echo "HTTPS URL: https://${HOSTNAME}/lab?token=${TOKEN}"
echo "NodePort URL: http://${PUBLIC_IP}:${NODEPORT}/lab?token=${TOKEN}"

