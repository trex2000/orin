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

## Part 3: Configuring Kilo.ai

To hook Kilo.ai into your local backend through Open WebUI, point your connection parameters to Open WebUI's OpenAI-compatible endpoint.

1. **Endpoint URL:** Use Open WebUI's standard chat completions path:
   ```text
   http://<your-open-webui-ip-or-domain>:3000/api/chat/completions
   ```
2. **Authentication Header:** Pass your generated secret key as a Bearer Token in your request headers:
   ```http
   Authorization: Bearer YOUR_OPEN_WEBUI_API_KEY
   ```
3. **Model Selection:** Select or input your preferred model name (e.g., your loaded Qwen instance) as configured inside Open WebUI.
