import dnd
import gleam/dynamic/decode
import gleam/float
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{type Attribute}
import lustre/event

// TYPES -----------------------------------------------------------------------

pub type Position {
  Position(x: Float, y: Float)
}

pub type Movement {
  Free
  Horizontal
  Vertical
}

/// Determines when list modifications should be applied during drag operations.
///
/// This controls the timing of when your list gets updated - either continuously
/// while dragging for real-time visual feedback, or only when the item is dropped
/// for final placement. In the groups module, this applies to both same-group
/// and cross-group operations independently.
///
/// ## Variants
///
/// - `OnDrag`: Apply list changes immediately as the item is dragged over drop targets.
///   Provides real-time visual feedback but triggers more frequent updates.
/// - `OnDrop`: Apply list changes only when the drag operation completes.
///   More performant for complex lists but less visual feedback during dragging.
///
/// ## Group Context
///
/// You can configure different listen modes for same-group vs cross-group operations:
/// - Main `listen`: Controls when same-group operations are applied
/// - `groups.listen`: Controls when cross-group operations are applied
///
/// ## Example
///
/// ```gleam
/// let config = groups.Config(
///   listen: groups.OnDrag,        // Same-group: immediate updates
///   groups: groups.GroupsConfig(
///     listen: groups.OnDrop,      // Cross-group: only on drop
///     // ... other group options
///   ),
///   // ... other options
/// )
/// ```
pub type Listen {
  OnDrag
  OnDrop
}

/// Defines how the list should be modified when an item is dragged and dropped.
///
/// Each operation provides a different way of rearranging items in the list,
/// affecting how the dragged item and other items are repositioned. In the context
/// of groups, operations work differently for same-group vs cross-group transfers.
///
/// ## Variants
///
/// - `InsertAfter`: Move the dragged item to the position immediately after the drop target
/// - `InsertBefore`: Move the dragged item to the position immediately before the drop target
/// - `Rotate`: Perform a circular shift of all items between the drag and drop positions (includes both endpoints)
/// - `Swap`: Exchange the positions of the dragged item and the drop target item
/// - `Unaltered`: Do not modify the list (useful for custom logic or visual feedback only)
///
/// ## Group Behavior
///
/// For **same-group** operations, this behaves identically to the basic dnd module.
/// For **cross-group** operations, the dragged item's group membership is updated using
/// the `setter` function before applying the positional change.
///
/// ## Examples
///
/// Given items with groups `[A₁, B₁, C₂, D₂, E₁]` (subscript = group) and dragging `C₂` to `E₁`:
///
/// - `InsertAfter`: `[A₁, B₁, D₂, E₁, C₁]` - C changes to group 1 and moves after E
/// - `InsertBefore`: `[A₁, B₁, D₂, C₁, E₁]` - C changes to group 1 and moves before E
/// - `Rotate`: Group-aware rotation with group membership updates
/// - `Swap`: `[A₁, B₁, E₂, D₂, C₁]` - C and E exchange both positions and groups
pub type Operation {
  InsertAfter
  InsertBefore
  Rotate
  Swap
  Unaltered
}

/// Configuration for cross-group drag-and-drop operations.
///
/// This type defines how items should behave when dragged between different logical groups.
/// It works alongside the main Config to provide different behaviors for same-group vs
/// cross-group transfers.
///
/// ## Fields
///
/// - `listen`: When to apply cross-group changes (OnDrag for real-time, OnDrop for final placement)
/// - `operation`: What operation to perform when transferring between groups (InsertAfter, InsertBefore, Rotate, Swap, or Unaltered)
/// - `comparator`: Function to determine if two items belong to the same group. Return `True` if items are in the same group.
/// - `setter`: Function to update the dragged item when it's moved to a different group. Receives (target_item, drag_item) and returns the updated drag_item.
///
/// ## Example
///
/// ```gleam
/// type Group { Left | Right }
/// type Item { Item(group: Group, value: String) }
///
/// let groups_config = groups.GroupsConfig(
///   listen: groups.OnDrag,
///   operation: groups.InsertBefore,
///   comparator: fn(a, b) { a.group == b.group },  // Same group if group field matches
///   setter: fn(target, drag) { Item(..drag, group: target.group) },  // Update group membership
/// )
/// ```
pub type GroupsConfig(a) {
  GroupsConfig(
    listen: Listen,
    operation: Operation,
    comparator: fn(a, a) -> Bool,
    setter: fn(a, a) -> a,
  )
}

/// Configuration for group-aware drag-and-drop behavior.
///
/// This extends the basic drag-and-drop configuration to support items organized in logical groups.
/// It defines separate behaviors for same-group operations (using the main config) and
/// cross-group operations (using the groups config).
///
/// ## Fields
///
/// - `before_update`: A callback function that allows you to modify the list before any operation is applied
/// - `movement`: Constrains how the ghost element can move (Free, Horizontal, or Vertical)
/// - `listen`: When to apply same-group changes (OnDrag for real-time, OnDrop for final placement)
/// - `operation`: What operation to perform for same-group transfers
/// - `groups`: Configuration for cross-group operations (see GroupsConfig)
///
/// ## Behavior
///
/// - When dragging within the same group: uses `listen` and `operation`
/// - When dragging between different groups: uses `groups.listen` and `groups.operation`
/// - The `groups.comparator` determines whether items are in the same group
/// - The `groups.setter` updates the item when it changes groups
///
/// ## Example
///
/// ```gleam
/// let config = groups.Config(
///   before_update: fn(_, _, list) { list },
///   movement: groups.Free,        // Allow movement in any direction
///   listen: groups.OnDrag,        // Same-group: update while dragging
///   operation: groups.Rotate,     // Same-group: rotate items
///   groups: groups.GroupsConfig(
///     listen: groups.OnDrag,      // Cross-group: update while dragging
///     operation: groups.InsertBefore,  // Cross-group: insert before target
///     comparator: fn(a, b) { a.group == b.group },
///     setter: fn(target, drag) { Item(..drag, group: target.group) },
///   ),
/// )
/// ```
pub type Config(a) {
  Config(
    before_update: fn(Int, Int, List(a)) -> List(a),
    movement: Movement,
    listen: Listen,
    operation: Operation,
    groups: GroupsConfig(a),
  )
}

pub type State {
  State(
    drag_index: Int,
    drop_index: Int,
    drag_counter: Int,
    start_position: Position,
    current_position: Position,
    drag_element_id: String,
    drop_element_id: String,
  )
}

pub type Model {
  Model(Option(State))
}

/// Information about the current drag operation when an item is being dragged.
///
/// This type provides access to all relevant details about an active drag operation,
/// including positions, indices, and element identifiers. In the groups context,
/// this information applies regardless of whether the drag is within the same group
/// or between different groups.
///
/// ## Fields
///
/// - `drag_index`: List index of the item being dragged (original position)
/// - `drop_index`: List index of the current drop target (where it would be placed)
/// - `drag_element_id`: DOM element ID of the dragged item
/// - `drop_element_id`: DOM element ID of the current drop target
/// - `start_position`: Mouse coordinates where the drag began
/// - `current_position`: Current mouse coordinates during drag
///
/// ## Group Operations
///
/// The indices provided here are absolute positions in the full list, regardless
/// of group membership. The system internally handles group logic using the
/// comparator function to determine same-group vs cross-group behavior.
///
/// ## Usage
///
/// ```gleam
/// // Check if currently dragging and get info
/// case model.system.info(model.system.model) {
///   Some(info) -> {
///     // Currently dragging - can access both drag and drop information
///     let drag_item = list.drop(model.items, info.drag_index) |> list.take(1)
///     let drop_item = list.drop(model.items, info.drop_index) |> list.take(1)
///     // Use for group-aware styling, validation, etc.
///   }
///   None -> {
///     // Not currently dragging
///   }
/// }
/// ```
///
/// ## Availability
///
/// This information is only available during active drag operations (returns `Some(Info)`).
/// When no drag is in progress, `system.info()` returns `None`.
pub type Info {
  Info(
    drag_index: Int,
    drop_index: Int,
    drag_element_id: String,
    drop_element_id: String,
    start_position: Position,
    current_position: Position,
  )
}

/// The group-aware drag-and-drop system containing all necessary functions and state.
///
/// This type extends the basic drag-and-drop system to support items organized in logical groups.
/// It provides intelligent behavior for same-group vs cross-group operations.
/// Create it using `groups.create()` and integrate it into your Lustre application.
///
/// ## Type Parameters
///
/// - `a`: The type of items in your draggable list (must support group operations)
/// - `msg`: Your application's message type
///
/// ## Fields
///
/// - `model`: Internal drag state (opaque - use `info()` to access current state)
/// - `update`: Function to handle drag messages with group-aware logic for both same-group and cross-group operations
/// - `drag_events`: Function to generate mouse event attributes for draggable elements
/// - `drop_events`: Function to generate mouse event attributes for drop targets
/// - `ghost_styles`: Function to generate CSS styling for the ghost element
/// - `info`: Function to extract current drag information (positions, indices, etc.)
///
/// ## Group Behavior
///
/// The system automatically detects whether a drag operation is within the same group
/// or between different groups, and applies the appropriate configuration:
/// - Same group: Uses main `operation` and `listen` settings
/// - Cross group: Uses `groups.operation` and `groups.listen` settings, plus `setter` to update group membership
///
/// ## Usage
///
/// ```gleam
/// // In your update function:
/// DndMsg(dnd_msg) -> {
///   let #(new_dnd, new_items) =
///     model.system.update(dnd_msg, model.system.model, model.items)
///   let updated_system = groups.System(..model.system, model: new_dnd)
///   Model(system: updated_system, items: new_items)
/// }
///
/// // In your view function:
/// html.div(
///   [..model.system.drag_events(index, element_id)],
///   [html.text(item.value)]
/// )
/// ```
pub type System(a, msg) {
  System(
    model: Model,
    update: fn(DndMsg, Model, List(a)) -> #(Model, List(a)),
    drag_events: fn(Int, String) -> List(Attribute(msg)),
    drop_events: fn(Int, String) -> List(Attribute(msg)),
    ghost_styles: fn(Model) -> List(Attribute(msg)),
    info: fn(Model) -> Option(Info),
  )
}

pub type DndMsg {
  DragStart(Int, String, Position)
  Drag(Position)
  DragOver(Int, String)
  DragEnter(Int)
  DragLeave
  DragEnd
}

// SYSTEM CREATION -------------------------------------------------------------

pub fn create(config: Config(a), step_msg: fn(DndMsg) -> msg) -> System(a, msg) {
  System(
    model: Model(None),
    update: system_update(config),
    drag_events: drag_events(step_msg),
    drop_events: drop_events(step_msg),
    ghost_styles: ghost_styles(config.movement),
    info: get_info,
  )
}

// SYSTEM UPDATE ---------------------------------------------------------------

fn system_update(
  config: Config(a),
) -> fn(DndMsg, Model, List(a)) -> #(Model, List(a)) {
  fn(msg: DndMsg, model: Model, list: List(a)) -> #(Model, List(a)) {
    case msg {
      DragStart(drag_index, drag_element_id, position) -> {
        let new_state =
          State(
            drag_index: drag_index,
            drop_index: drag_index,
            drag_counter: 0,
            start_position: position,
            current_position: position,
            drag_element_id: drag_element_id,
            drop_element_id: drag_element_id,
          )
        #(Model(Some(new_state)), list)
      }

      Drag(position) -> {
        case model {
          Model(Some(state)) -> {
            let updated_state =
              State(
                ..state,
                current_position: position,
                drag_counter: state.drag_counter + 1,
              )
            #(Model(Some(updated_state)), list)
          }
          Model(None) -> #(model, list)
        }
      }

      DragOver(drop_index, drop_element_id) -> {
        case model {
          Model(Some(state)) -> {
            let updated_state =
              State(
                ..state,
                drop_index: drop_index,
                drop_element_id: drop_element_id,
              )
            #(Model(Some(updated_state)), list)
          }
          Model(None) -> #(model, list)
        }
      }

      DragEnter(drop_index) -> {
        case model {
          Model(Some(state)) -> {
            case state.drag_counter > 1 && state.drag_index != drop_index {
              True -> {
                let equal_groups =
                  groups_equal(
                    config.groups.comparator,
                    state.drag_index,
                    drop_index,
                    list,
                  )

                case equal_groups, config.listen, config.groups.listen {
                  // Same group operations
                  True, OnDrag, _ -> {
                    let updated_state =
                      update_state_for_operation(
                        config.operation,
                        drop_index,
                        state,
                      )
                    let updated_list =
                      sublist_update(
                        config.operation,
                        state.drag_index,
                        drop_index,
                        list,
                      )
                    #(
                      Model(Some(updated_state)),
                      config.before_update(
                        state.drag_index,
                        drop_index,
                        updated_list,
                      ),
                    )
                  }
                  // Different group operations
                  False, _, OnDrag -> {
                    let updated_state =
                      update_state_for_operation(
                        config.groups.operation,
                        drop_index,
                        state,
                      )
                    let updated_list =
                      groups_list_update(
                        config.groups.operation,
                        config.groups.comparator,
                        config.groups.setter,
                        state.drag_index,
                        drop_index,
                        list,
                      )
                    #(
                      Model(Some(updated_state)),
                      config.before_update(
                        state.drag_index,
                        drop_index,
                        updated_list,
                      ),
                    )
                  }
                  // Reset drag counter for other cases
                  _, _, _ -> {
                    let updated_state = State(..state, drag_counter: 0)
                    #(Model(Some(updated_state)), list)
                  }
                }
              }
              False -> #(model, list)
            }
          }
          Model(None) -> #(model, list)
        }
      }

      DragLeave -> {
        case model {
          Model(Some(state)) -> {
            let updated_state = State(..state, drop_index: state.drag_index)
            #(Model(Some(updated_state)), list)
          }
          Model(None) -> #(model, list)
        }
      }

      DragEnd -> {
        case model {
          Model(Some(state)) -> {
            case state.drag_index != state.drop_index {
              True -> {
                let equal_groups =
                  groups_equal(
                    config.groups.comparator,
                    state.drag_index,
                    state.drop_index,
                    list,
                  )

                case equal_groups, config.listen, config.groups.listen {
                  // Same group operations
                  True, OnDrop, _ -> {
                    let updated_list =
                      sublist_update(
                        config.operation,
                        state.drag_index,
                        state.drop_index,
                        list,
                      )
                    #(
                      Model(None),
                      config.before_update(
                        state.drag_index,
                        state.drop_index,
                        updated_list,
                      ),
                    )
                  }
                  // Different group operations
                  False, _, OnDrop -> {
                    let updated_list =
                      groups_list_update(
                        config.groups.operation,
                        config.groups.comparator,
                        config.groups.setter,
                        state.drag_index,
                        state.drop_index,
                        list,
                      )
                    #(
                      Model(None),
                      config.before_update(
                        state.drag_index,
                        state.drop_index,
                        updated_list,
                      ),
                    )
                  }
                  // No operation for other cases
                  _, _, _ -> #(Model(None), list)
                }
              }
              False -> #(Model(None), list)
            }
          }
          Model(None) -> #(Model(None), list)
        }
      }
    }
  }
}

// GROUP HELPERS ---------------------------------------------------------------

fn groups_equal(
  comparator: fn(a, a) -> Bool,
  drag_index: Int,
  drop_index: Int,
  list: List(a),
) -> Bool {
  let drag_items = get_items_at_index(drag_index, list)
  let drop_items = get_items_at_index(drop_index, list)

  case drag_items, drop_items {
    [drag_item], [drop_item] -> comparator(drag_item, drop_item)
    _, _ -> False
  }
}

fn get_items_at_index(index: Int, list: List(a)) -> List(a) {
  list |> list.drop(index) |> list.take(1)
}

fn drag_group_update(
  setter: fn(a, a) -> a,
  drag_index: Int,
  drop_index: Int,
  list: List(a),
) -> List(a) {
  let drop_items = get_items_at_index(drop_index, list)

  list.index_map(list, fn(item, index) {
    case index == drag_index {
      True -> {
        case drop_items {
          [drop_item] -> [setter(drop_item, item)]
          _ -> [item]
        }
      }
      False -> [item]
    }
  })
  |> list.flatten()
}

fn drag_and_drop_group_update(
  setter: fn(a, a) -> a,
  drag_index: Int,
  drop_index: Int,
  list: List(a),
) -> List(a) {
  let drag_items = get_items_at_index(drag_index, list)
  let drop_items = get_items_at_index(drop_index, list)

  list.index_map(list, fn(item, index) {
    case index {
      i if i == drag_index -> {
        case drop_items {
          [drop_item] -> [setter(drop_item, item)]
          _ -> [item]
        }
      }
      i if i == drop_index -> {
        case drag_items {
          [drag_item] -> [setter(drag_item, item)]
          _ -> [item]
        }
      }
      _ -> [item]
    }
  })
  |> list.flatten()
}

fn all_group_update(
  fn_transform: fn(List(a)) -> List(a),
  start_index: Int,
  end_index: Int,
  list: List(a),
) -> List(a) {
  let beginning = list.take(list, start_index)
  let middle =
    list |> list.drop(start_index) |> list.take(end_index - start_index + 1)
  let end = list.drop(list, end_index + 1)

  list.append(list.append(beginning, fn_transform(middle)), end)
}

fn bubble_group_recursive(
  comparator: fn(a, a) -> Bool,
  setter: fn(a, a) -> a,
  items: List(a),
) -> List(a) {
  case items {
    [] -> []
    [x] -> [x]
    [x, ..xs] -> {
      let sublist = sublist_by_first_item(comparator, items)
      case sublist {
        [] -> [x, ..xs]
        _ -> {
          let sublist_length = list.length(sublist)
          let reversed_tail = sublist |> list.drop(1) |> list.reverse()
          let first_sublist = list.take(sublist, 1)
          let next_item = xs |> list.drop(sublist_length - 1) |> list.take(1)

          case first_sublist, next_item {
            [first], [next] -> {
              let updated_first = setter(next, first)
              let updated_next = setter(first, next)
              let remaining = list.drop(xs, sublist_length)

              list.append(
                list.append(reversed_tail, [updated_first]),
                bubble_group_recursive(
                  comparator,
                  setter,
                  list.append([updated_next], remaining),
                ),
              )
            }
            _, _ -> [x, ..xs]
          }
        }
      }
    }
  }
}

fn sublist_by_first_item(
  comparator: fn(a, a) -> Bool,
  items: List(a),
) -> List(a) {
  case items {
    [] -> []
    [first, ..] -> list.filter(items, fn(item) { comparator(first, item) })
  }
}

// STATE AND LIST UPDATE HELPERS ----------------------------------------------

fn update_state_for_operation(
  operation: Operation,
  drop_index: Int,
  state: State,
) -> State {
  case operation {
    InsertAfter -> {
      let new_drag_index = case drop_index < state.drag_index {
        True -> drop_index + 1
        False -> drop_index
      }
      State(..state, drag_index: new_drag_index, drag_counter: 0)
    }
    InsertBefore -> {
      let new_drag_index = case state.drag_index < drop_index {
        True -> drop_index - 1
        False -> drop_index
      }
      State(..state, drag_index: new_drag_index, drag_counter: 0)
    }
    Rotate -> State(..state, drag_index: drop_index, drag_counter: 0)
    Swap -> State(..state, drag_index: drop_index, drag_counter: 0)
    Unaltered -> State(..state, drag_counter: 0)
  }
}

// Reuse the operations from dnd.gleam for same-group operations
fn sublist_update(
  operation: Operation,
  drag_index: Int,
  drop_index: Int,
  list: List(a),
) -> List(a) {
  case operation {
    InsertAfter -> dnd.insert_after(drag_index, drop_index, list)
    InsertBefore -> dnd.insert_before(drag_index, drop_index, list)
    Rotate -> dnd.rotate_items(drag_index, drop_index, list)
    Swap -> dnd.swap_items(drag_index, drop_index, list)
    Unaltered -> list
  }
}

// Group-specific list operations for cross-group transfers
fn groups_list_update(
  operation: Operation,
  comparator: fn(a, a) -> Bool,
  setter: fn(a, a) -> a,
  drag_index: Int,
  drop_index: Int,
  list: List(a),
) -> List(a) {
  case operation {
    InsertAfter -> {
      let updated_list = drag_group_update(setter, drag_index, drop_index, list)
      dnd.insert_after(drag_index, drop_index, updated_list)
    }
    InsertBefore -> {
      let updated_list = drag_group_update(setter, drag_index, drop_index, list)
      dnd.insert_before(drag_index, drop_index, updated_list)
    }
    Rotate -> {
      case drag_index < drop_index {
        True -> {
          let transform_fn = fn(items) {
            let reversed = list.reverse(items)
            let bubbled = bubble_group_recursive(comparator, setter, reversed)
            list.reverse(bubbled)
          }
          let updated_list =
            all_group_update(transform_fn, drag_index, drop_index, list)
          dnd.rotate_items(drag_index, drop_index, updated_list)
        }
        False -> {
          let transform_fn = fn(items) {
            bubble_group_recursive(comparator, setter, items)
          }
          let updated_list =
            all_group_update(transform_fn, drop_index, drag_index, list)
          dnd.rotate_items(drag_index, drop_index, updated_list)
        }
      }
    }
    Swap -> {
      let updated_list =
        drag_and_drop_group_update(setter, drag_index, drop_index, list)
      dnd.swap_items(drag_index, drop_index, updated_list)
    }
    Unaltered -> list
  }
}

// EVENT HANDLERS --------------------------------------------------------------

fn drag_events(
  step_msg: fn(DndMsg) -> msg,
) -> fn(Int, String) -> List(Attribute(msg)) {
  fn(drag_index: Int, drag_element_id: String) -> List(Attribute(msg)) {
    [
      event.on("mousedown", {
        use client_x <- decode.field("clientX", decode.float)
        use client_y <- decode.field("clientY", decode.float)
        decode.success(
          step_msg(DragStart(
            drag_index,
            drag_element_id,
            Position(client_x, client_y),
          )),
        )
      }),
    ]
  }
}

fn drop_events(
  step_msg: fn(DndMsg) -> msg,
) -> fn(Int, String) -> List(Attribute(msg)) {
  fn(drop_index: Int, drop_element_id: String) -> List(Attribute(msg)) {
    [
      event.on(
        "mouseover",
        decode.success(step_msg(DragOver(drop_index, drop_element_id))),
      ),
      event.on("mouseenter", decode.success(step_msg(DragEnter(drop_index)))),
      event.on("mouseleave", decode.success(step_msg(DragLeave))),
    ]
  }
}

// GHOST STYLES ---------------------------------------------------------------

fn ghost_styles(movement: Movement) -> fn(Model) -> List(Attribute(msg)) {
  fn(model: Model) -> List(Attribute(msg)) {
    case model {
      Model(Some(state)) -> {
        let essential_styles = [
          attribute.style("position", "fixed"),
          attribute.style("pointer-events", "none"),
          attribute.style("z-index", "1000"),
          attribute.style("user-select", "none"),
          attribute.style("-webkit-user-select", "none"),
        ]

        let position_styles = case movement {
          Free -> [
            attribute.style(
              "left",
              float.to_string(state.current_position.x) <> "px",
            ),
            attribute.style(
              "top",
              float.to_string(state.current_position.y) <> "px",
            ),
          ]
          Horizontal -> [
            attribute.style(
              "left",
              float.to_string(state.current_position.x) <> "px",
            ),
            attribute.style(
              "top",
              float.to_string(state.start_position.y) <> "px",
            ),
          ]
          Vertical -> [
            attribute.style(
              "left",
              float.to_string(state.start_position.x) <> "px",
            ),
            attribute.style(
              "top",
              float.to_string(state.current_position.y) <> "px",
            ),
          ]
        }

        list.append(essential_styles, position_styles)
      }
      Model(None) -> []
    }
  }
}

// INFO EXTRACTION -------------------------------------------------------------

fn get_info(model: Model) -> Option(Info) {
  case model {
    Model(Some(state)) -> {
      Some(Info(
        drag_index: state.drag_index,
        drop_index: state.drop_index,
        drag_element_id: state.drag_element_id,
        drop_element_id: state.drop_element_id,
        start_position: state.start_position,
        current_position: state.current_position,
      ))
    }
    Model(None) -> None
  }
}
