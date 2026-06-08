# "maven-build pipeline"

This pipeline builds Maven project artifacts and deploys them as a Konflux
component build artifact OCI image manifest.

v1 does not prefetch dependencies. Security scans run via IntegrationTestScenarios
per ADR-0048 (https://github.com/konflux-ci/architecture/blob/main/ADR/0048-movable-build-tests.md).

_Uses `git-clone` to clone the source repository into a workspace PVC, and
`maven-deploy` to run Maven and deploy the staged repository layout as a Konflux
component build artifact OCI image manifest.
This pipeline is pushed as a Tekton bundle to [quay.io](https://quay.io/repository/konflux-ci/tekton-catalog/pipeline-maven-build?tab=tags)_

## Parameters
|name|description|default value|used in (taskname:taskrefversion:taskparam)|
|---|---|---|---|
|enable-cache-proxy| Enable cache proxy configuration| false| init:0.4:enable-cache-proxy|
|git-url| Source Repository URL| None| clone-repository:0.1:url|
|image-expires-after| Image tag expiration time, time values could be something like 1h, 2d, 3w for hours, days, and weeks, respectively.| | build-oci-artifact:0.1:IMAGE_EXPIRES_AFTER|
|output-image| Fully Qualified Output Image| None| build-oci-artifact:0.1:IMAGE|
|revision| Revision of the Source Repository| | clone-repository:0.1:revision|

## Results
|name|description|value|
|---|---|---|
|CHAINS-GIT_COMMIT| |$(tasks.clone-repository.results.commit)|
|CHAINS-GIT_URL| |$(tasks.clone-repository.results.url)|
|IMAGE_DIGEST| |$(tasks.build-oci-artifact.results.IMAGE_DIGEST)|
|IMAGE_URL| |$(tasks.build-oci-artifact.results.IMAGE_URL)|

## Workspaces
|name|description|optional|used in tasks
|---|---|---|---|
|git-auth| |True| clone-repository:0.1:basic-auth|
|workspace| |False| clone-repository:0.1:output ; build-oci-artifact:0.1:source|
