# Render Paseo dev box

This is a small private Render service that runs the official Paseo daemon,
Pi, OpenCode, GitHub CLI, AWS CLI, and Google Cloud CLI. The persistent disk is
mounted at `/workspace`; agent state, repositories, and CLI configuration are
redirected there because Render SSH does not allow a disk mounted at the
running user's `$HOME`.

## Deploy

1. Put this directory in a **private** GitHub repository, for example
   `render-paseo-devbox`.
2. In Render, create a Blueprint from that repository and choose the region.
   The Blueprint creates one Standard private service and a 20 GB disk. Keep it
   at one instance; Render disks are single-instance storage.
3. Fill the `sync: false` values during the first Blueprint creation. Render
   only prompts for those values on initial creation.
4. In the service's **Environment → Secret Files**, upload the GCP service
   account JSON as exactly `gcp-service-account.json`. Render exposes it to the
   Docker service at `/etc/secrets/gcp-service-account.json`.
5. Add `~/.ssh/id_ed25519.pub` to Render account SSH keys. Never upload the
   private key.

The private service has no public URL. Paseo's hosted relay is outbound from
this service, so no inbound port or public hostname is needed for mobile access.
`PASEO_PASSWORD` is still generated for defense in depth and for any direct
connection that may be added later.

## First SSH session

Use the service's **Connect → SSH** command or:

```bash
render ssh <service-id>
```

Run this without printing any secret values:

```bash
command -v paseo opencode pi gh aws gcloud
printf 'OpenAI key: '; test -n "$OPENAI_API_KEY" && echo present || echo missing
printf 'Azure key: '; test -n "$AZURE_API_KEY" && echo present || echo missing
printf 'GCP key file: '; test -r "$GOOGLE_APPLICATION_CREDENTIALS" && echo readable || echo missing
printf 'GitHub: '; gh auth status >/dev/null 2>&1 && echo ready || echo check-GH_TOKEN
aws sts get-caller-identity
```

`GOOGLE_APPLICATION_CREDENTIALS` is enough for Google client libraries and
agents. If the `gcloud` CLI itself is needed, activate the account once; its
configuration is on the persistent disk:

```bash
gcloud auth activate-service-account \
  --key-file="$GOOGLE_APPLICATION_CREDENTIALS" --quiet
gcloud config set project "$GOOGLE_CLOUD_PROJECT"
```

Clone repositories with the GitHub token; do not copy a personal SSH private
key into the service:

```bash
mkdir -p /workspace/repos
cd /workspace/repos
gh auth setup-git
gh repo clone OWNER/REPOSITORY
```

## Azure AI Foundry

Render stores the Azure key as the `AZURE_API_KEY` environment secret. The
non-secret endpoint is `AZURE_FOUNDRY_BASE_URL`. On first boot, the image seeds:

- `/workspace/.config/opencode/opencode.json`
- `/workspace/.pi/agent/models.json`

OpenCode uses a local proxy in the container so Azure's GPT-5.6 parameter rules
are handled without exposing the Azure key to the agent config. From SSH, run:

```bash
cd /workspace/repos/REPOSITORY
opencode run -m azure/kimi-k2.7-code "Inspect the repository and report its test command."
opencode run -m azure/gpt-5.6-terra "Inspect the repository and report its architecture."
pi --provider azure-foundry --model kimi-k2.7-code
```

From the Paseo phone app, create an OpenCode or Pi session and select the same
model IDs in its model picker.

The model IDs are the deployments currently configured in the local setup. A
model that returns Azure `404` is not deployed under that ID; update both
persistent JSON files with the deployment ID shown by Azure AI Foundry.

## Pair Paseo with the phone

From the SSH shell, generate a one-time pairing offer:

```bash
paseo daemon pair --json
```

Copy the returned `url` into the Paseo mobile app's add-host/pair flow. Treat
that URL like a password. If it is exposed, restart the service/daemon and pair
again to rotate the offer.

The daemon is already running when the service is healthy. In the Paseo phone
app, select a repository and choose either OpenCode or Pi. For direct SSH model
commands, see the Azure section below.

`OPENAI_API_KEY` is consumed by both OpenCode's OpenAI provider and Pi. Use the
agent's `/connect` or `/login` flow only if choosing a different provider.

## Security boundaries

All processes in this single-user container can read the environment and the
GCP secret file. Use trusted repositories only, give the PAT and cloud
credentials the smallest practical permissions, and rotate them independently.
Do not run `env`, `set -x`, or paste credentials into an agent prompt. Push code
to GitHub; the disk is persistence, not a replacement for source control.

Render restarts and redeploys terminate running agent processes even though
`/workspace` survives. The disk also prevents service scaling and zero-downtime
deploys, so schedule image changes accordingly.

## Local check

Before committing the bootstrap repository:

```bash
bash -n render-entrypoint.sh
```
