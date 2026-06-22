# Bulby

Bulby is a lightweight macOS menu bar app for quick screen capture and local AI help.

Open the notch input, type a question, and Bulby captures the active window or selected windows for a local Ollama vision model. It is designed for fast "what is on my screen?" questions without copying screenshots by hand or uploading them to a cloud API.

## Highlights

- Fast screen capture from the current Mac window
- Optional multi-window capture when you want to choose the target
- Notch-style input for quick questions
- Local Ollama vision model support
- Follow-up questions inside the answer window
- Recent answer history
- Custom modes for translation, explanation, review, and other workflows
- No OpenAI, Gemini, or hosted cloud API key required

## Requirements

- macOS 14.0 or later
- [Ollama](https://ollama.com/) installed and running
- An Ollama model that supports vision input
- macOS Screen Recording permission for Bulby

The default model name is `gemma4:e4b`. If you use a different installed model, select it from the Bulby menu.

## Install

1. Download the latest DMG from [Releases](https://github.com/leeshinhyuk/bulby/releases).
2. Open the DMG and move `Bulby.app` to the Applications folder.
3. Start Ollama.
4. Open Bulby and allow Screen Recording permission when macOS asks.
5. Quit and reopen Bulby after changing the Screen Recording permission.

## How To Use

- Move the cursor near the MacBook notch to open the input.
- Type a question and press Return.
- Bulby captures the current screen context and sends it to your local Ollama server.
- Click the menu bar lightbulb to reopen the latest answer.
- Right-click the lightbulb to choose a model, open history, select capture windows, or check permission status.
- Use the answer window input to ask follow-up questions in the same conversation.

## Privacy

Bulby is local-first. Captured screen images and prompts are sent to the local Ollama server at `127.0.0.1:11434`.

Bulby does not directly send screenshots, prompts, answers, or history to OpenAI, Gemini, or any hosted cloud API. Recent conversation data is stored locally in macOS `UserDefaults`. Raw screenshot image files are not saved.

See [PRIVACY.md](PRIVACY.md) for details.

## License

Bulby is not released under an open-source license. You may view this repository and use official Bulby releases for personal use, but you may not copy, modify, redistribute, sublicense, sell, or commercially use Bulby without prior written permission.

See [LICENSE](LICENSE) for details.

## Troubleshooting

- If answers do not generate, make sure Ollama is running.
- If the model list is empty, install a vision-capable Ollama model.
- If screen capture fails, check macOS System Settings > Privacy & Security > Screen Recording.
- If you just changed the permission, fully quit and reopen Bulby.
- If Bulby captures the wrong window, clear selected windows from the menu and try again.
