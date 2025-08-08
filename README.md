# Gleam Drag and Drop Library

A drag-and-drop library for Gleam applications built with the Lustre web framework. This library is a **direct port of the [Elm dnd-list](https://package.elm-lang.org/packages/annaghi/dnd-list/latest/) package** by [Anna Bansaghi](https://github.com/annaghi), bringing the same functionality to the Gleam ecosystem.

**Original Elm package**: https://annaghi.github.io/dnd-list/

This library provides both basic drag-and-drop functionality and advanced group-based operations, allowing you to create rich interactive interfaces with precise control over item movement and organization.

## Features

While dragging and dropping a list item, the mouse events, the ghost element's positioning and the list sorting are handled internally by this library. Here are the key capabilities:

- **Complete drag-and-drop system**: Handle mouse events, ghost element positioning, and list sorting automatically
- **Flexible configuration**: Choose from multiple operations (insert, rotate, swap) and listen modes (on drag vs on drop)
- **Movement constraints**: Support for free, horizontal, or vertical movement
- **Visual feedback**: Ghost element follows cursor with customizable styling
- **Detailed state information**: Access drag source, drop target, positions, and DOM elements during operations
- **Type-safe API**: Full Gleam type safety with phantom types for your data models
- **Groups support**: Advanced functionality for transferring items between logical groups with different operations for same-group vs cross-group movements

## Architecture

The library is split into two main modules:

- **`dnd.gleam`**: Core drag-and-drop functionality for single lists
- **`groups.gleam`**: Extended functionality for group-based operations

Both modules follow The Elm Architecture (TEA) pattern with:
- **Model**: Internal drag state management
- **Update**: Message handling and state transitions
- **View**: Event bindings and styling helpers

## Installation

```sh
gleam add dnd
```

## Basic Usage

Here's a simple example of drag-and-drop with list reordering:

```gleam
import dnd
import lustre
import lustre/element/html
import lustre/attribute

type Model {
  Model(system: dnd.System(String, Msg), items: List(String))
}

type Msg {
  DndMsg(dnd.DndMsg)
}

fn init(_flags) -> Model {
  let config = dnd.Config(
    before_update: fn(_, _, list) { list },
    listen: dnd.OnDrag,
    operation: dnd.Rotate,
  )

  let system = dnd.create(config, DndMsg)
  Model(system: system, items: ["A", "B", "C", "D"])
}

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    DndMsg(dnd_msg) -> {
      let #(new_dnd, new_items) =
        model.system.update(dnd_msg, model.system.model, model.items)
      let updated_system = dnd.System(..model.system, model: new_dnd)
      Model(system: updated_system, items: new_items)
    }
  }
}

fn view(model: Model) -> element.Element(Msg) {
  html.div(
    [
      // Global mouse events when dragging
      case model.system.info(model.system.model) {
        Some(_) -> event.on("mousemove", decode_drag_event)
        None -> attribute.none()
      }
    ],
    list.index_map(model.items, fn(item, index) {
      html.div(
        [
          attribute.id("item-" <> int.to_string(index)),
          ..model.system.drag_events(index, "item-" <> int.to_string(index))
        ],
        [html.text(item)]
      )
    })
  )
}
```

## Groups Usage

For more complex scenarios with multiple groups:

```gleam
import dnd/groups

type Group {
  Left
  Right
}

type Item {
  Item(group: Group, value: String)
}

fn init(_flags) -> Model {
  let config = groups.Config(
    before_update: fn(_, _, list) { list },
    listen: groups.OnDrag,
    operation: groups.Rotate,  // Same-group operation
    groups: groups.GroupsConfig(
      listen: groups.OnDrag,
      operation: groups.InsertBefore,  // Cross-group operation
      comparator: fn(a, b) { a.group == b.group },
      setter: fn(target_item, drag_item) {
        Item(..drag_item, group: target_item.group)
      },
    ),
  )

  let system = groups.create(config, DndMsg)
  Model(system: system, items: [
    Item(Left, "A"), Item(Left, "B"),
    Item(Right, "1"), Item(Right, "2")
  ])
}
```

## Operations

### Basic Operations
- **`InsertAfter`**: Move dragged item after the drop target
- **`InsertBefore`**: Move dragged item before the drop target
- **`Rotate`**: Circular shift of items between drag and drop positions
- **`Swap`**: Exchange positions of dragged and drop target items
- **`Unaltered`**: No list modification (useful for custom logic)

### Listen Modes
- **`OnDrag`**: Updates happen continuously while dragging
- **`OnDrop`**: Updates happen only when item is dropped

## Examples

This repository includes two complete examples:

### Basic Example (`src/example.gleam`)
A simple sortable list demonstrating:
- Basic drag and drop with visual feedback
- Multiple operation types (InsertBefore, Rotate, Swap)
- Ghost element styling
- Cross-browser compatibility

**Run with:**
```sh
cd example
gleam run -m lustre/dev start
```

### Groups Example (`groupsexample/src/example.gleam`)
An advanced two-column interface showing:
- Items organized in Left and Right groups
- Cross-group item transfers
- Same-group reordering
- Footer drop zones for group transfers
- Conditional drop logic based on group membership

**Run with:**
```sh
cd groupsexample
gleam run -m lustre/dev start
```

## Technical Details

### Mouse Event Handling
The library uses precise mouse coordinate tracking:
- `clientX` and `clientY` for accurate positioning
- Custom event decoders for Lustre integration
- Automatic text selection prevention during drag

### Ghost Element
- Positioned using `position: fixed` for viewport-relative positioning

### Cross-Browser Support
- Tested on Chrome and Safari

## Development

```sh
gleam format     # Format code
gleam check      # Type check
```

For development with live reload:
```sh
cd groupsexample && gleam run -m lustre/dev start  # Groups example
```

## API Reference

### Core Types
- `System(a, msg)`: Main system containing model, update, and view functions
- `Model`: Internal drag state (opaque type)
- `Config(a)`: Configuration for drag operations
- `Info`: Current drag information (indices, positions, elements)

### Groups Types
- `GroupsConfig(a)`: Extended configuration for group operations
- `Operation`: Available list operations
- `Listen`: When to trigger operations (OnDrag vs OnDrop)

The library provides a clean, type-safe API that integrates seamlessly with Lustre applications while offering the flexibility to handle complex drag-and-drop scenarios.

## Development

File bug reports or feature requests at the [issue tracker](https://todo.sr.ht/~tpjg/dnd).
To send patches configure git [sendemail](https://git-send-email.io) and send your patches.

```sh
git config sendemail.to "~tpjg/dnd-dev@lists.sr.ht"

git commit -m "..."
git send-email HEAD^
```

Or to send just once:

```sh
git commit
git send-email --to "~tpjg/dnd-dev@lists.sr.ht" HEAD^
```
