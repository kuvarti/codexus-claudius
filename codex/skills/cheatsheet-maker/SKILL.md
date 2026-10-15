# Cheatsheet Maker Skill Draft

Create a compact, usable quick reference tailored to the user's topic, audience, and requested file formats. When the user supplies or points to a visual reference, inspect that reference and use it as a style cue. For Dracula-themed HTML, use a restrained dark theme with readable spacing and highlighted code. Do not hardcode machine-specific paths; locate references from the current workspace or the user's instructions.

## Content

- Organize material around common tasks and workflows. Put the most useful commands or facts first.
- Prefer concrete, copyable examples with short explanations. Explain placeholders such as `<file>` or `<name>` and mark examples that need adaptation.
- Verify version-sensitive commands from the installed tool's help or authoritative local documentation when available. Do not present guesses as confirmed syntax.
- Keep the reference concise enough to scan. Omit background material that does not help someone perform the task.
- Preserve exact command spelling, flags, code, and identifiers when translating the surrounding prose.
- Include safety or side-effect notes only where they materially help the reader choose or run an operation.

## Files and presentation

- Save files where the user asks. If no location is given, use the current workspace and choose an obvious topic-based filename.
- Use Markdown as the editable source when a file is requested. Create HTML, PDF, images, or other exports when requested or when the surrounding task clearly expects them.
- For HTML that should resemble the reference, use a Dracula palette: background `#282a36`, elevated code surface `#21222c`, selection/surface `#44475a`, foreground `#f8f8f2`, comment `#6272a4`, cyan `#8be9fd`, green `#50fa7b`, orange `#ffb86c`, pink `#ff79c6`, purple `#bd93f9`, red `#ff5555`, yellow `#f1fa8c`.
- Apply the theme consistently to the page, headings, links, inline code, code blocks, borders, and syntax highlighting. Keep contrast readable, code blocks easy to copy, and layout comfortable on narrow screens.
- Use the client's locally installed `Fira Code` font at weight `600` (Semibold) throughout the HTML, including headings and code. Set the font family and weight in CSS; do not bundle or fetch font files. Keep a monospace fallback if Fira Code is unavailable.
- Prefer self-contained HTML and local or built-in resources. Do not add remote scripts or dependencies just for decoration.
- Keep Markdown and HTML content in sync when producing both. Avoid changing or regenerating sibling exports unless the user requests them.

## Finish

Tell the user which files were created or updated and link to them. Mention any important command or version limitation briefly.
