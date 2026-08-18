# Local rendering backends

All Mermaid source and artifacts must remain on the workstation. Do not replace these backends with a hosted renderer.

## 1. Local Mermaid CLI

The first backend is an existing `mmdc` executable with a working local Chromium/Puppeteer installation. The helper probes it with a built-in diagram before using it.

## 2. Mermaid CLI container

The default image is `minlag/mermaid-cli:latest`. Preload and approve the image outside the skill workflow. The helper never pulls it and runs it with networking disabled.

Override the approved local image when required:

```bash
export MERMAID_CLI_IMAGE='registry.corp.example/mermaid-cli@sha256:APPROVED_DIGEST'
```

Set `MERMAID_CONTAINER_RUNTIME=docker` or `podman` to disable automatic Docker-first detection.

## 3. Local Kroki

Mermaid requires the Kroki gateway and the Mermaid companion. The following Compose configuration binds the gateway only to loopback, prevents pulls, and places both services on an internal network:

```yaml
services:
  kroki:
    image: ${KROKI_IMAGE:-yuzutech/kroki:latest}
    pull_policy: never
    depends_on:
      - mermaid
    environment:
      KROKI_MERMAID_HOST: mermaid
    ports:
      - "127.0.0.1:8000:8000"
    networks:
      - kroki-internal

  mermaid:
    image: ${KROKI_MERMAID_IMAGE:-yuzutech/kroki-mermaid:latest}
    pull_policy: never
    expose:
      - "8002"
    networks:
      - kroki-internal

networks:
  kroki-internal:
    internal: true
```

Preload pinned, approved images before running `docker compose up -d`. The helper accepts `KROKI_URL` only when it is an HTTP loopback URL without credentials or a path; the default is `http://127.0.0.1:8000`.

Kroki renders Mermaid PNG and SVG. It cannot provide the PDF fallback.
