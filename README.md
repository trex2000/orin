# User Manual: Configuring Open WebUI and Kilo.ai Integration

This manual details how to enable API authentication within Open WebUI and connect external clients like Kilo.ai to your local instance.

---

## Part 1: Enabling API Keys in Open WebUI

To allow external platforms like Kilo.ai to securely communicate with your Open WebUI instance, API key authentication must first be enabled globally.

1. **Log in as Administrator:** Open your Open WebUI browser interface (typically at `http://<your-server-ip>:3000`) and log in using an administrator account.
2. **Access Admin Settings:** Click on your profile icon in the bottom-left corner and select **Admin Panel**.
3. **Navigate to Authentication:** Go to **Settings** > **Authentication**.
4. **Enable API Keys:** Locate the toggle for **API Keys** and switch it to **Enabled**. Save your changes.

---

## Part 2: Generating a Secret API Key

Once global API keys are enabled, you can generate a personal secret token for your client application.

1. **Open User Settings:** Click your profile icon in the bottom-left sidebar and select **Settings** (or **Account**).
2. **Locate API Keys Section:** Scroll down to find the **API keys** management section.
3. **Create New Key:** Click **Create new secret key**.
4. **Copy the Key:** A pop-up will display your new API key. Copy it immediately and store it securely, as it will not be shown again.

---

## Part 3: Kilo.ai Hybrid Configuration Guide: Jetson AGX Orin & Gemini Cloud

This configuration balances the raw speed and zero-cost privacy of a local Jetson AGX Orin with the massive context windows and advanced reasoning of Gemini cloud models.

### 3.1. Provider Endpoint Setup (Kilo Code Extension)

To securely route your local `qwen3-coder` traffic through your metrics pipeline, configure the custom provider in Kilo Code as follows:

* **Display Name:** `Open WebUI (Orin)`
* **Provider API:** `OpenAI Compatible`
* **Base URL:** `https://<URL_OF_OPEN_WEBUI>/ollama/v1`
* **API Key:** `<Your Open WebUI Personal Access Token>`
* **Models:** `qwen3-coder:latest` (or any other model to be used locally)

### 3.2. Agent Mode Mapping

Assign the models within Kilo Code's settings based on their architectural strengths to prevent Orin memory exhaustion while maximizing development velocity.

#### Local Edge (Jetson AGX Orin)
* **Code Mode:** `qwen3-coder:latest`
  * **Function:** High-frequency syntax generation, autocomplete, and boilerplate.
  * **Advantage:** Zero-latency feedback loop. Keeps proprietary C/C++ and ESP-IDF embedded code strictly on-premise without round-trip network delays.
* **Ask Mode:** `qwen3-coder:latest`
  * **Function:** Routine file Q&A, syntax explanations, and API lookup.
  * **Advantage:** Fast responses for single files and localized logic blocks.  
  * *Note: Switch to Gemini 3.1 Flash only when injecting massive context (e.g., 200-page datasheets or full repository dumps).*

#### Cloud Frontier (Google Gemini)
* **Plan (Architect) Mode:** `Gemini 2.5 Pro`
  * **Function:** System design, parsing entire repository structures, and breaking down epics into sub-tasks.
  * **Advantage:** Requires a massive context window to hold the entire project architecture and prevent structural dead-ends.
* **Orchestrator Mode:** `Gemini 2.5 Pro`
  * **Function:** Coordinating complex workflows and delegating sub-tasks across agents.
  * **Advantage:** Superior instruction-following ensures multi-step refactoring doesn't derail midway.
* **Debug Mode:** `Gemini 2.5 Pro` (or Tiered)
  * **Function:** Root-cause analysis of complex RTOS faults, memory leaks, and multi-file stack traces.
  * **Advantage:** Deep reasoning reduces time spent chasing obscure hardware interrupt timing issues or silent memory corruptions.

---

## Part 4: Configuring Agent Behaviour (Plan vs. Code Mode)

This guide explains how to configure prompt instructions, model assignments, and permissions to offload coding execution reliably from cloud architect models (e.g., Gemini Pro) to a local model (e.g., Qwen on an internal server/Orin).

### Architecture Overview

* **Plan Mode (Cloud Agent / Gemini Pro):** Has full repo visibility (`grep`, `glob`, `read`, `semantic_search`) to diagnose problems, trace cross-file references, and generate exact diff specifications.
* **Code Mode (Local Agent / Qwen Coder):** Has write permissions (`read`, `write`, `edit`) but is blocked from exploratory tools (`grep`, `glob`) and interactive stall tools (`question`, `suggest`) to ensure immediate file modifications.

### 4.1. Plan Mode Configuration

#### Objectives
1. Prevent ambiguous guidance like "update the function as needed."
2. Force the cloud model to generate deterministic, machine-readable `SEARCH`/`REPLACE` blocks.
3. Automatically append the exact `@file` execution context for the local Code agent.

#### System Prompt Override
In **Settings** > **Agent Behaviour** > **Plan Mode** > **Custom prompt override**:

```text
You are an expert software architect and implementation planner.
Your role is to analyze requirements, inspect codebases, and create deterministic, execution-ready implementation plans for an automated local coder model.

When formulating plans:
1. Identify all target files using relative paths from the workspace root.
2. Trace all function declarations, definitions, and dependent call sites.
3. For each change, provide exact code blocks using standard SEARCH/REPLACE formatting:
   - SEARCH: Must include 2-3 lines of matching context before and after the change.
   - REPLACE: The exact new code to insert.
4. Eliminate ambiguity: specify variable types, include headers, and handle edge cases explicitly.
5. Conclude the plan by listing the target file paths with `@` prefixes so they can be loaded directly into Code Mode.
```

### 4.2. Code Mode Configuration

#### Objectives
1. Prevent the local model from slipping into code reviews, audit commentary, or polite dialogue.
2. Deny interactive fallback tools (`question`, `suggest`) that allow the model to ask questions instead of editing files.
3. Enforce deterministic sampling parameters.

#### Agent Parameters
In **Settings** > **Agent Behaviour** > **Code Mode**:
* **Model Override:** `qwen3-coder:latest` (or `qwen2.5-coder:32b`). Avoid chat-biased `-next` variants.
* **Temperature:** `0.0`
* **Top P:** `0.1`

#### Tool Permissions
* `read`: **allow**
* `write_to_file` / `replace_in_file`: **allow**
* `question`: **deny**
* `suggest`: **deny**
* `semantic_search`: **deny**
* `bash grep` / `bash ls`: **deny**

#### System Prompt Override
In **Settings** > **Agent Behaviour** > **Code Mode** > **Custom prompt override**:

```text
You are an autonomous execution-only code implementation engine.
You receive implementation instructions and apply changes directly to disk using editor tools.

Strict Operational Constraints:
1. You are strictly forbidden from writing code reviews, summarizing architecture, identifying code smells, or outputting conversational commentary.
2. You must NOT ask questions, request confirmation, or propose alternatives.
3. Do NOT initiate searches across the repository.
4. Your immediate and only objective is to apply changes to target files using the file edit/write tools.
5. Read the targeted file, locate the target lines, and apply the modification immediately.
```

---

## Part 5: Additional Local Offloading Strategies

With `qwen3-coder:latest` (30B) consuming roughly 20 GB of the AGX Orin's 64 GB unified memory, you have 40+ GB of headroom for supplementary local operations:

* **Local Embeddings (RAG):** Pull `bge-m3` or `nomic-embed-text` (1-2 GB footprint) via Ollama to index your codebase for fast, private semantic search without relying on external vector databases.
* **Unit Tests:** Use the local Qwen model for repetitive scaffolding generation (e.g., Unity/CMock test cases for embedded C).
* **First-Pass Debugging:** Feed standard GCC/Clang syntax warnings and missing header errors to the local model first, escalating to Gemini Pro only for logical or multi-thread race conditions.
