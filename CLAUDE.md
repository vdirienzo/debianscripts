# Project Conventions - DebianScripts/Autoclean

## Language Guidelines

### Code Comments
- **ALL comments in code must be in ENGLISH**
- This applies to:
  - Inline comments (`# comment`)
  - Block comments
  - Section headers (`# ============ SECTION ============`)
  - Function documentation
  - Help text output (`--help`)

### Documentation
- **README.md must always be in ENGLISH**
- All markdown documentation files should be in English

### User-facing Strings
- User-facing messages use the i18n system (`MSG_*` variables)
- These are translated via language files in `plugins/lang/`
- Do NOT hardcode Spanish strings in the main script

## Code Style

### Bash Script
- Use `#!/bin/bash` shebang
- Variables in UPPER_SNAKE_CASE for globals
- Functions in lower_snake_case
- Indent with 4 spaces

### Commit Messages
- Use conventional commits format: `type(scope): description`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `security`
- Commit messages in English

## Project Structure

```
autoclean/
├── autoclean.sh          # Main script
├── autoclean.conf        # User configuration (auto-generated)
├── plugins/
│   ├── lang/            # Language files (*.lang)
│   ├── themes/          # Theme files (*.theme)
│   ├── notifiers/       # Notification plugins
│   └── help/            # Help files for steps
├── screenshots/         # UI screenshots
└── README.md            # Documentation (English)
```

## Git Workflow

- Main branches: `main`, `dev`
- Push changes to both branches when ready
- Always verify README is up to date after significant changes
