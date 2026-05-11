# max-weather Base Node.js Image (Chainguard apko)

Distroless Node.js 20 base image built declaratively from
[Chainguard Wolfi](https://github.com/wolfi-dev/) packages via
[apko](https://github.com/chainguard-dev/apko).

Application Dockerfiles (`app/Dockerfile`, `lambda-authorizer/Dockerfile` if added)
should `FROM` this image instead of `node:20-alpine` so every workload inherits:

- Wolfi distroless base (no shell, no package manager at runtime)
- CVE-free upstream packages with reproducible builds
- Non-root `app` user (uid/gid `65532`) and `/app` workdir already set
- `node` as the default entrypoint

## Files

| File | Purpose |
|---|---|
| `apko.yaml` | apko build manifest — package list, accounts, entrypoint, archs |
| `build.sh` | Wrapper that builds + pushes to ECR (`<cluster>-base-nodejs:<date>`, `:latest`) |

## Local build (no push)

```bash
# Requires apko on PATH: brew install apko  OR  go install chainguard.dev/apko@latest
cd base-image
./build.sh local
docker load < base-image.tar
docker run --rm -it max-weather-base-nodejs:* node --version
```

## Build + publish to ECR

```bash
make base-image-push
# equivalent to:
AWS_REGION=us-east-1 CLUSTER=max-weather base-image/build.sh
```

The ECR repository `<cluster>-base-nodejs` is provisioned by the `ecr` Terraform
module via `var.ecr_repositories` (default map is replaced — see
`infra/envs/poc/variables.tf`).

## Updating Node.js / package versions

Edit `apko.yaml` → `packages:` and rerun `./build.sh`. apko will resolve the
latest matching Wolfi package versions and produce a fully reproducible OCI
image. Pin to specific versions (e.g. `nodejs-20=20.18.0-r0`) for byte-stable
rebuilds.

## References

- apko: https://github.com/chainguard-dev/apko
- Wolfi packages: https://github.com/wolfi-dev/os
- Chainguard images (prebuilt equivalents): https://images.chainguard.dev
