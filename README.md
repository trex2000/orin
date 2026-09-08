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


# ## Part 3: C Kilo.ai Hybrid Configuration Guide: Jetson AGX Orin & Gemini Cloud

This configuration balances the raw speed and zero-cost privacy of a local Jetson AGX Orin with the massive context windows and advanced reasoning of Gemini cloud models. 

## 3.1. Provider Endpoint Setup (Kilo Code Extension)

To securely route your local `qwen3-coder` traffic through your metrics pipeline, configure the custom provider in Kilo Code as follows:

*   **Display Name:** `Open WebUI (Orin)`
*   **Provider API:** `OpenAI Compatible`
*   **Base URL:** `https://<URL_OF_OPEN_WEBUI>/ollama/v1`
*   **API Key:** `<Your Open WebUI Personal Access Token>`
*   **Models:** `qwen3-coder:latest or any other model to be used locally`

## 3.2. Agent Mode Mapping

Assign the models within Kilo Code's settings based on their architectural strengths to prevent Orin memory exhaustion while maximizing development velocity.

### Local Edge (Jetson AGX Orin)
*   **Code Mode:** `qwen3-coder:latest`
    *   **Function:** High-frequency syntax generation, autocomplete, and boilerplate.
    *   **Advantage:** Zero-latency feedback loop. Keeps proprietary C/C++ and ESP-IDF embedded code strictly on-premise without round-trip network delays.
*   **Ask Mode:** `qwen3-coder:latest`
    *   **Function:** Routine file Q&A, syntax explanations, and API lookup.
    *   **Advantage:** Fast responses for single files and localized logic blocks. 
    *   *Note: Switch to Gemini 3.1 Flash only when injecting massive context (e.g., 200-page datasheets or full repository dumps).*

### Cloud Frontier (Google Gemini)
*   **Plan (Architect) Mode:** `Gemini 2.5 Pro`
    *   **Function:** System design, parsing entire repository structures, and breaking down epics into sub-tasks.
    *   **Advantage:** Requires a massive context window to hold the entire project architecture and prevent structural dead-ends.
*   **Orchestrator Mode:** `Gemini 2.5 Pro`
    *   **Function:** Coordinating complex workflows and delegating sub-tasks across agents.
    *   **Advantage:** Superior instruction-following ensures multi-step refactoring doesn't derail midway.
*   **Debug Mode:** `Gemini 2.5 Pro` (or Tiered)
    *   **Function:** Root-cause analysis of complex RTOS faults, memory leaks, and multi-file stack traces.
    *   **Advantage:** Deep reasoning reduces time spent chasing obscure hardware interrupt timing issues or silent memory corruptions. 

## 4. Additional Local Offloading Strategies

With `qwen3-coder:latest` (30B) consuming roughly 20 GB of the AGX Orin's 64 GB unified memory, you have 40+ GB of headroom for supplementary local operations:

*   **Local Embeddings (RAG):** Pull `bge-m3` or `nomic-embed-text` (1-2 GB footprint) via Ollama to index your codebase for fast, private semantic search without relying on external vector databases.
*   **Unit Tests:** Use the local Qwen MoE for repetitive scaffolding generation (e.g., Unity/CMock test cases for embedded C).
*   **First-Pass Debugging:** Feed standard GCC/Clang syntax warnings and missing header errors to the local model first, escalating to Gemini Pro only for logical or multi-thread race conditions.
*   
