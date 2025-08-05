# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Gleam web application using the Lustre framework for frontend development. The project is configured to target JavaScript and runs in the browser, using Lustre for reactive UI components with TailwindCSS for styling.

## Architecture

- **Language**: Gleam (targeting JavaScript)
- **Framework**: Lustre (functional reactive UI framework)
- **Styling**: TailwindCSS
- **Build System**: Gleam + Lustre Dev Tools

### Key Files
- `examples/src/example.gleam` - Main application entry point with Lustre application using the `dnd` module for drag-and-drop functionality
- `gleam.toml` - Project configuration and dependencies, also in example subdirectories

## Development Commands

### Core Gleam Commands
- `gleam format` - Format Gleam source code
- `gleam check` - Type check the project

### Lustre Development
- `cd example &&gleam run -m lustre/dev start` - Start development server with live reload - CLAUDE, you do not have to do this, this will always be running in the background so the human developer can test in the browser
- `cd example &&gleam run -m lustre/dev build` - Build and bundle the application for production


## Project Structure

The app uses Lustre's element-based architecture where the UI is defined as a tree of HTML elements with attributes and event handlers. The main application (e.g. `examples/src/example.gleam`) creates a static element and mounts it to the DOM.

Key dependencies:
- `lustre` - Core UI framework
- `lustre_dev_tools` - Development server and build tools
- `gleam_stdlib` - Standard library

## Development Notes

- The project is configured for browser deployment (JavaScript target)
- TailwindCSS is integrated via Lustre dev tools
- Static assets are served from `priv/static/`
- The main application mounts to `#app` element in index.html
- Running `gleam run` directly requires a browser environment and will fail in CLI
- The lustre framework is very heavily influenced by The Elm Architecture (TEA)
