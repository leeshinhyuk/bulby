# Bulby Privacy

Bulby is built around local processing.

## What Bulby Sends

- Bulby captures the selected or active on-screen window only when you submit a prompt.
- Captured images and prompt text are sent to the local Ollama server at `127.0.0.1:11434`.
- Bulby does not send screenshots, prompts, questions, answers, or history to a hosted cloud API.

## What Bulby Stores Locally

Bulby stores the following data locally in macOS `UserDefaults`:

- custom modes and their prompts
- selected Ollama model name
- conversation history, including questions, answers, timestamps, and captured source window titles

Bulby limits stored history to recent conversations and trims long fields. Bulby does not persist raw screenshot image files.

## Permissions

Bulby requires Screen Recording permission because its core feature is understanding the current screen. The permission is used for ScreenCaptureKit window capture.

## Local Model Server Notice

Bulby assumes Ollama is running locally. If you modify the app, proxy Ollama, or connect `127.0.0.1:11434` to a non-local model server, screenshots and prompts may leave your device. Update this policy before distributing a modified build.
