# maven-deploy-oci-ta task

Trusted Artifacts variant of [`maven-deploy`](../maven-deploy/README.md). The task
YAML is **generated** from [`recipe.yaml`](recipe.yaml); do not edit
[`maven-deploy-oci-ta.yaml`](maven-deploy-oci-ta.yaml) directly. Regenerate with
`hack/generate-ta-tasks.sh`.

Builds Maven project artifacts using the Maven `deploy` goal, then deploys a
component build artifact to a container registry as an OCI image manifest.

## What this task does / does not do

**Does:**

- Runs `mvn clean source:jar deploy` with a local staging repository at
  `target/stage-deploy` (`-DaltDeploymentRepository=local::file:./target/stage-deploy`).
  Maven's deploy machinery is used only as a build-time packaging step.
- Packages the staged Maven repository layout into a single OCI image layer.
- **Deploys (pushes)** that layout to the container registry as an OCI image
  manifest with `artifactType: application/vnd.konflux.maven.repository.v1+tar`.

**Does not:**

- Publish artifacts to a remote Maven repository (Nexus, Artifactory, GitHub
  Packages, etc.).
- Run dependency prefetching or hermetic/Cachi2 builds in v1.

Consumers pull the OCI artifact from the registry and extract the embedded
Maven-repository-layout layer when needed.

## Parameters

| name | description | default value | required |
|---|---|---|---|
| SOURCE_ARTIFACT | Trusted Artifact URI with application source code. | | true |
| IMAGE | Registry reference for the OCI artifact to deploy. | | true |
| IMAGE_EXPIRES_AFTER | Quay tag expiry (for example `1w`). Empty keeps the tag. | `""` | false |
| caTrustConfigMapName | ConfigMap with CA bundle data. | `trusted-ca` | false |
| caTrustConfigMapKey | Key in the CA ConfigMap. | `ca-bundle.crt` | false |

## Results

| name | description |
|---|---|
| IMAGE_URL | Repository and tag where the artifact was deployed |
| IMAGE_DIGEST | Digest of the deployed OCI artifact |
| IMAGE_REF | Full image reference with digest |

## Workspaces

None. Source is provided via Trusted Artifacts (`SOURCE_ARTIFACT`).
