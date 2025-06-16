# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Standard build
zig build

# Release build (optimized)
zig build --release=fast

# Debug build
zig build debug

# Run tests
zig build test

# Build and run
zig build run

# Install to /usr/local/bin
make install
```

## Development Workflow

### Docker Development
```bash
# Start development environment
make docker-dev
docker-compose exec zterm-dev bash

# Build in Docker
make docker-build

# Run tests in Docker
make test
```

### Running Single Tests
```bash
# Run specific test file
zig test src/shell_test.zig
zig test src/completion_test.zig
```

## Architecture Overview

The codebase follows a modular architecture with clear separation of concerns:

### Core Components

1. **main.zig** - Entry point, ncurses initialization, and main event loop
   - Handles keyboard input processing
   - Manages ncurses lifecycle
   - Dispatches events to terminal

2. **terminal.zig** - Terminal emulator core
   - Screen rendering and cursor management
   - Command history navigation
   - Git branch display in prompt
   - Tab completion UI rendering
   - Line editing functionality

3. **shell.zig** - Command execution engine
   - Built-in commands: cd, pwd, ls, echo, clear, help, exit
   - External command execution with proper ncurses suspension
   - Working directory management
   - Interactive program handling (vim, nano, etc.)

4. **completion.zig** - Tab completion system
   - Command completion (built-in and PATH)
   - File path completion
   - Git subcommand and branch completion
   - Common prefix calculation

### Key Implementation Details

- **Ncurses Management**: The system properly suspends ncurses for interactive programs (vim, nano) and reinitializes after they exit
- **Memory Management**: Uses GeneralPurposeAllocator with careful cleanup in all modules
- **Unicode Support**: Proper handling of multi-byte UTF-8 characters throughout
- **Git Integration**: Real-time branch detection with colored prompt display

## Testing Strategy

- Unit tests use Zig's built-in testing framework
- Tests include memory leak detection via GeneralPurposeAllocator
- Test files follow the pattern `*_test.zig`
- Tests cover edge cases like non-existent directories, empty inputs, and Unicode handling

## Important Notes

- The project uses Zig 0.14.1 (latest stable)
- Requires ncurses library for terminal UI
- Docker environments available for development, building, and runtime
- Japanese documentation in README.md provides additional context