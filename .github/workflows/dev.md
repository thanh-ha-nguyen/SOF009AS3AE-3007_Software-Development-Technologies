## Sequence diagram

```mermaid
sequenceDiagram
    autonumber
    actor Developer

    box rgb(255, 246, 236) GitHub cloud
    participant GH as GitHub Actions
    participant Runner as GitHub Runner on Ubuntu
    end
    
    box rgb(205, 232, 255) CSC Cloud
    participant Rahti as CSC Rahti Cluster
    participant Registry as Rahti Container Registry
    end

    %% Trigger Phase
    Developer->>GH: Push commit to 'master' branch
    GH->>GH: Cancel any in-progress runs in 'dev' group

    %% Job 1: Build
    rect rgba(240, 245, 255, .75)
        Note over GH,Runner: Job 1: Build Phase
        GH->>GH: Checkout repository code
        GH->>Runner: Install Runner & target (wasm32-unknown-unknown)
        GH->>Runner: Install tools (trunk, wasm-bindgen-cli)
        GH->>GH: Execute scripts/fetch-words.sh
        GH->>Runner: Run 'trunk build --release'
        Runner-->>GH: Output compiled assets to ./dist
        GH->>GH: Upload './dist' as build artifact
    end

    %% Job 2: Deploy
    rect rgba(245, 250, 240, .75)
        Note over GH,Registry: Job 2: Deploy Phase (depends on Job 1)
        GH->>GH: Install CSC Rahti CLI (oc & kubectl)
        GH->>Rahti: Authenticate via 'oc login' using CSC_TOKEN
        GH->>GH: Checkout repository code
        GH->>GH: Download build artifact ('./dist')
        
        GH->>Runner: Build and tag Docker image
        Runner-->>GH: Image created and tagged
        GH->>Registry: Authenticate current user
        Registry-->>GH: User authenticated
        GH->>Registry: Push image (sanuli-webapp:dev)
        Registry-->>GH: Image pushed
        
        GH->>GH: Generate deployment config based on chosen environment
        GH->>Rahti: Apply deployment config via CSC Rahti CLI
        Rahti-->>GH: Deployment config applied
    end

    %% Post-Deployment Cluster Operations
    rect rgba(238, 238, 238, .75)
        Note over Rahti,Registry: Post-Deployment Execution in Rahti
        Rahti->>Rahti: Detect updated deployment configuration
        Rahti->>Registry: Request image 'sanuli-webapp:dev'
        Registry-->>Rahti: Stream container image layers
        Rahti->>Rahti: Spin up new Pod(s) with updated image
        Rahti->>Rahti: Perform readiness / liveness health checks
        Rahti->>Rahti: Route traffic to new Pod(s) & terminate old Pod(s)
    end
```

-   Triggering & Concurrency: Commits pushed to master cause GitHub Actions to cancel active runs before kicking off the workflow.
-   Job 1 (Build): Interacts with Rust tools to compile WebAssembly assets and stores the resulting ./dist artifact within GitHub.
-   Job 2 (Deploy): Handshakes directly with the CSC Rahti Cluster (for authentication and OpenShift manifest deployment) and the Rahti Container Registry (to store the newly built Docker container image).
-   Deployment Detection: OpenShift/Rahti receives the updated deployment.yml manifest from the CI runner and triggers a new rolling deployment.
-   Image Pull: The cluster controller requests and pulls the updated sanuli-webapp:dev container image layers from the Rahti Container Registry.
-   Pod Lifecycle & Traffic Routing: Rahti provisions the new Pods, verifies their health, updates service routing, and safely terminates the legacy Pods.

## Flowchart

```mermaid
flowchart TD
    %% Trigger & Concurrency
    Trigger(["Trigger: Push to 'master' branch"]) --> Concurrency["Concurrency Control<br>Group: dev<br>Cancel in-progress: true"]
    Concurrency --> Job1

    %% Job 1: Build
    subgraph Job1 ["Job 1: Build & Deploy (build)"]
        direction TB
        B_Step1["1. Checkout repository"] --> B_Step2["2. Install Rust"]
        B_Step2 --> B_Step3["3. Create build artifact<br>• Add wasm32 target<br>• Install trunk & wasm-bindgen<br>• Run fetch-words.sh script<br>• Execute 'trunk build --release'"]
        B_Step3 --> B_Step4["4. Upload build artifact<br>(./dist)"]
    end

    %% Dependency Link
    Job1 -->|Artifacts & Dependency: 'needs: build'| Job2

    %% Job 2: Deploy
    subgraph Job2 ["Job 2: Deploy to CSC Rahti (deploy)"]
        direction TB
        D_Step1["1. Install CSC Rahti CLI<br>(Download & extract 'oc' / 'kubectl')"] --> D_Step2["2. Setup CSC Rahti environment<br>(Login to Rahti API & select project)"]
        D_Step2 --> D_Step3["3. Checkout repository"]
        D_Step3 --> D_Step4["4. Download build artifact<br>(./dist)"]
        D_Step4 --> D_Step5["5. Build & publish Docker image<br>• Build Docker image<br>• Login to Rahti Image Registry<br>• Push Docker image"]
        D_Step5 --> D_Step6["6. Deploy to CSC Rahti<br>• Substitute env vars in deployment template<br>• Apply configuration via 'oc apply'"]
    end

    Job2 --> Complete(["Workflow Complete"])
```

1.  Trigger & Concurrency Control:
    -   Trigger: Runs automatically on any push to the master branch.
    -   Concurrency: Prevents overlapping runs in the dev environment by automatically canceling any previously running workflow when a new push occurs.
2.  Job 1: build
    -   Prepares the Rust/WebAssembly environment.
    -   Compiles the application into web artifacts using trunk build --release.
    -   Uploads the generated ./dist directory as a GitHub Actions artifact.
3.  Job 2: deploy
    -   Dependency: Runs only after the build job completes successfully (needs: build).
    -   Environment & Credentials: Authenticates against CSC Rahti using CSC_TOKEN and CSC_PROJECT secrets.
    -   Docker & Deployment: Downloads the ./dist artifact, builds a Docker image, pushes it to the Rahti Image Registry, processes the deployment YAML template via envsubst, and applies it to OpenShift/Rahti using oc apply.

## Activity diagram

```mermaid
stateDiagram-v2
    [*] --> BranchCheck

    state "Push to master?" as BranchCheck
    BranchCheck --> CancelPreviousRuns : Yes
    BranchCheck --> [*] : No

    state CancelPreviousRuns {
        [*] --> CancelInProgress : Concurrency group 'dev'
    }

    CancelInProgress --> JobBuild

    state "Job 1: Build (ubuntu-latest)" as JobBuild {
        [*] --> CheckoutBuildRepo
        CheckoutBuildRepo --> InstallRust
        InstallRust --> SetupWasmTarget
        SetupWasmTarget --> InstallCLI Tools
        InstallCLITools --> FetchWordsScript
        FetchWordsScript --> TrunkBuild
        TrunkBuild --> UploadArtifact
        UploadArtifact --> [*]
    }

    JobBuild --> CheckBuildStatus

    state "Build Succeeded?" as CheckBuildStatus
    CheckBuildStatus --> JobDeploy : Yes
    CheckBuildStatus --> [*] : No (Fail Workflow)

    state "Job 2: Deploy (ubuntu-latest)" as JobDeploy {
        [*] --> InstallCSC_CLI
        InstallCSC_CLI --> LoginRahti
        
        state "Parallel Deployment Prep" as ParallelPrep {
            CheckoutDeployRepo
            --
            DownloadArtifact
        }
        
        LoginRahti --> ParallelPrep
        ParallelPrep --> BuildDockerImage
        BuildDockerImage --> LoginDockerRegistry
        LoginDockerRegistry --> PushDockerImage
        PushDockerImage --> SubstituteEnvVars
        SubstituteEnvVars --> OcApply
        OcApply --> [*]
    }

    JobDeploy --> WorkflowComplete
    WorkflowComplete --> [*]
```

-   Guard Conditions: The workflow evaluates the git push branch event. If it hits master, it cancels any existing in-progress run under the dev concurrency group before starting.
-   Job Dependency: The deploy job enforces strict execution ordering using needs: build, meaning deployment will immediately abort if the build step fails.
-   Deployment Execution: Prepares necessary setup steps (like CLI tools and authentication) before pulling the built static files and repository files, building the Docker container image, and applying the environment configuration via OpenShift/Rahti CLI (oc apply).