import gleam/dynamic/decode
import gleam/float
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
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

/// Determines which input mode the drag-and-drop system should use.
///
/// ## Variants
///
/// - `MouseOnly`: Traditional continuous drag behavior using mouse events.
///   This is the default and provides the classic drag-and-drop experience.
/// - `TouchOnly`: Two-tap selection pattern optimized for touch devices.
///   Tap to select an item, then tap a drop zone to move it.
/// - `Auto`: Automatically detects the input type per-interaction.
///   Uses mouse behavior for mousedown events, touch behavior for touch events.
///   Best for hybrid devices like tablets with keyboards.
pub type InputMode {
  MouseOnly
  TouchOnly
  Auto
}

/// Determines when list modifications should be applied during drag operations.
///
/// This controls the timing of when your list gets updated - either continuously
/// while dragging for real-time visual feedback, or only when the item is dropped
/// for final placement.
///
/// ## Variants
///
/// - `OnDrag`: Apply list changes immediately as the item is dragged over drop targets.
///   Provides real-time visual feedback but triggers more frequent updates.
/// - `OnDrop`: Apply list changes only when the drag operation completes.
///   More performant for complex lists but less visual feedback during dragging.
///
/// ## Use Cases
///
/// - **OnDrag**: Best for simple lists where you want immediate visual feedback
/// - **OnDrop**: Better for performance-sensitive applications or when you need to validate the drop
///
/// ## Example
///
/// ```gleam
/// // Real-time updates while dragging
/// let live_config = dnd.Config(
///   listen: dnd.OnDrag,
///   // ... other options
/// )
///
/// // Updates only on final drop
/// let batch_config = dnd.Config(
///   listen: dnd.OnDrop,
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
/// affecting how the dragged item and other items are repositioned.
///
/// ## Variants
///
/// - `InsertAfter`: Move the dragged item to the position immediately after the drop target
/// - `InsertBefore`: Move the dragged item to the position immediately before the drop target
/// - `Rotate`: Perform a circular shift of all items between the drag and drop positions (includes both endpoints)
/// - `Swap`: Exchange the positions of the dragged item and the drop target item
/// - `Unaltered`: Do not modify the list (useful for custom logic or visual feedback only)
pub type Operation {
  InsertAfter
  InsertBefore
  Rotate
  Swap
  Unaltered
}

/// Configuration for drag-and-drop behavior.
///
/// This type defines how the drag-and-drop system should behave, including
/// when to apply changes, how items should move, and what operation to perform.
///
/// ## Fields
///
/// - `before_update`: A callback function that allows you to modify the list
///   before the drag-and-drop operation is applied. Receives the drag index,
///   drop index, and the updated list. Return the final list to use.
/// - `movement`: Constrains how the ghost element can move (Free, Horizontal, or Vertical)
/// - `listen`: When to apply list changes (OnDrag for real-time updates, OnDrop for final placement)
/// - `operation`: What list operation to perform (InsertAfter, InsertBefore, Rotate, Swap, or Unaltered)
/// - `mode`: Input mode for the system (MouseOnly, TouchOnly, or Auto). Default: MouseOnly
/// - `touch_timeout_ms`: Milliseconds before touch selection auto-cancels. Default: 5000. Set to 0 to disable.
///
/// ## Example
///
/// ```gleam
/// // Mouse-only (default, backward compatible)
/// let config = dnd.Config(
///   before_update: fn(_, _, list) { list },
///   movement: dnd.Free,
///   listen: dnd.OnDrag,
///   operation: dnd.Rotate,
///   mode: dnd.MouseOnly,
///   touch_timeout_ms: 5000,
/// )
///
/// // Auto mode for hybrid devices
/// let touch_config = dnd.Config(
///   before_update: fn(_, _, list) { list },
///   movement: dnd.Vertical,
///   listen: dnd.OnDrag,
///   operation: dnd.Rotate,
///   mode: dnd.Auto,
///   touch_timeout_ms: 5000,
/// )
/// ```
pub type Config(a) {
  Config(
    before_update: fn(Int, Int, List(a)) -> List(a),
    movement: Movement,
    listen: Listen,
    operation: Operation,
    mode: InputMode,
    touch_timeout_ms: Int,
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

/// Touch selection state for the two-tap pattern.
pub type TouchState {
  TouchState(selected_index: Int, selected_id: String)
}

/// Interaction state - tracks whether we're idle, mouse dragging, or touch selecting.
/// This is used internally by the Model type.
pub type InteractionState {
  Idle
  MouseDragging(State)
  TouchSelecting(TouchState)
}

pub type Model {
  Model(interaction: InteractionState, touch_generation: Int)
}

/// Information about the current drag operation when an item is being dragged.
///
/// This type provides access to all relevant details about an active drag operation,
/// including positions, indices, and element identifiers. Use `system.info(model)`
/// to extract this information when a drag is in progress.
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
/// ## Usage
///
/// ```gleam
/// // Check if currently dragging and get info
/// case model.system.info(model.system.model) {
///   Some(info) -> {
///     // Currently dragging - can use info for styling, ghost positioning, etc.
///     html.div([
///       attribute.style("transform", "translate("
///         <> float.to_string(info.current_position.x) <> "px, "
///         <> float.to_string(info.current_position.y) <> "px)")
///     ], [html.text("Ghost element")])
///   }
///   None -> {
///     // Not currently dragging
///     html.text("")
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

/// The main drag-and-drop system containing all necessary functions and state.
///
/// This type encapsulates the complete drag-and-drop functionality and provides
/// the interface between your application and the drag-and-drop behavior.
/// Create it using `dnd.create()` and integrate it into your Lustre application.
///
/// ## Type Parameters
///
/// - `a`: The type of items in your draggable list
/// - `msg`: Your application's message type
///
/// ## Fields
///
/// - `model`: Internal drag state (opaque - use `info()` to access current state)
/// - `update`: Function to handle drag messages and update both the model and your list
/// - `drag_events`: Function to generate mouse event attributes for draggable elements
/// - `drop_events`: Function to generate mouse event attributes for drop targets
/// - `ghost_styles`: Function to generate CSS styling for the ghost element
/// - `info`: Function to extract current drag information (positions, indices, etc.)
///
/// ## Usage
///
/// ```gleam
/// // In your update function:
/// DndMsg(dnd_msg) -> {
///   let #(new_dnd, new_items) =
///     model.system.update(dnd_msg, model.system.model, model.items)
///   let updated_system = dnd.System(..model.system, model: new_dnd)
///   Model(system: updated_system, items: new_items)
/// }
///
/// // In your view function:
/// html.div(
///   [..model.system.drag_events(index, element_id)],
///   [html.text(item)]
/// )
/// ```
///
/// ## Touch Support (new)
///
/// For touch-enabled modes (TouchOnly or Auto), use these additional fields:
///
/// - `update_with_effect`: Like update, but returns an Effect for timeout scheduling
/// - `touch_grip_events`: Click handler for entering touch selection mode
/// - `touch_drop_zone_events`: Click handler for drop zones in touch mode
/// - `cancel_events`: Event handler for canceling touch selection
/// - `is_touch_selecting`: Check if currently in touch selection mode
/// - `selected_index`: Get the index of the selected item (if any)
pub type System(a, msg) {
  System(
    model: Model,
    // Existing (mouse-compatible)
    update: fn(DndMsg, Model, List(a)) -> #(Model, List(a)),
    drag_events: fn(Int, String) -> List(Attribute(msg)),
    drop_events: fn(Int, String) -> List(Attribute(msg)),
    ghost_styles: fn(Model) -> List(Attribute(msg)),
    info: fn(Model) -> Option(Info),
    // New (touch support)
    update_with_effect: fn(DndMsg, Model, List(a)) -> #(Model, List(a), Effect(msg)),
    touch_grip_events: fn(Int, String) -> List(Attribute(msg)),
    touch_drop_zone_events: fn(Int) -> List(Attribute(msg)),
    cancel_events: fn() -> List(Attribute(msg)),
    is_touch_selecting: fn(Model) -> Bool,
    selected_index: fn(Model) -> Option(Int),
  )
}

pub type DndMsg {
  // Mouse messages (traditional drag-and-drop)
  DragStart(Int, String, Position)
  Drag(Position)
  DragOver(Int, String)
  DragEnter(Int)
  DragLeave
  DragEnd
  // Touch messages (two-tap selection pattern)
  TouchSelect(Int, String)
  TouchDrop(Int)
  TouchCancel
  TouchTimeout(Int)
}

// SYSTEM CREATION -------------------------------------------------------------

pub fn create(config: Config(a), step_msg: fn(DndMsg) -> msg) -> System(a, msg) {
  System(
    model: Model(interaction: Idle, touch_generation: 0),
    update: system_update(config),
    drag_events: drag_events(step_msg),
    drop_events: drop_events(step_msg),
    ghost_styles: ghost_styles(config.movement),
    info: get_info,
    // Touch support
    update_with_effect: system_update_with_effect(config, step_msg),
    touch_grip_events: touch_grip_events(step_msg),
    touch_drop_zone_events: touch_drop_zone_events(step_msg),
    cancel_events: cancel_events(step_msg),
    is_touch_selecting: is_touch_selecting,
    selected_index: get_selected_index,
  )
}

// SYSTEM UPDATE ---------------------------------------------------------------

fn system_update(
  config: Config(a),
) -> fn(DndMsg, Model, List(a)) -> #(Model, List(a)) {
  fn(msg: DndMsg, model: Model, list: List(a)) -> #(Model, List(a)) {
    case msg, model.interaction {
      // === MOUSE MESSAGES ===

      // DragStart: Only start if idle (mutex lock)
      DragStart(drag_index, drag_element_id, position), Idle -> {
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
        #(Model(..model, interaction: MouseDragging(new_state)), list)
      }

      // Drag: Only process if mouse dragging
      Drag(position), MouseDragging(state) -> {
        let updated_state =
          State(
            ..state,
            current_position: position,
            drag_counter: state.drag_counter + 1,
          )
        #(Model(..model, interaction: MouseDragging(updated_state)), list)
      }

      // DragOver: Only process if mouse dragging
      DragOver(drop_index, drop_element_id), MouseDragging(state) -> {
        let updated_state =
          State(
            ..state,
            drop_index: drop_index,
            drop_element_id: drop_element_id,
          )
        #(Model(..model, interaction: MouseDragging(updated_state)), list)
      }

      // DragEnter: Only process if mouse dragging
      DragEnter(drop_index), MouseDragging(state) -> {
        case config.listen {
          OnDrag -> {
            case state.drag_counter > 1 && state.drag_index != drop_index {
              True -> {
                let updated_state =
                  update_state_for_operation(
                    config.operation,
                    drop_index,
                    state,
                  )
                let updated_list =
                  update_list_for_operation(
                    config.operation,
                    state.drag_index,
                    drop_index,
                    list,
                  )
                #(
                  Model(..model, interaction: MouseDragging(updated_state)),
                  config.before_update(state.drag_index, drop_index, updated_list),
                )
              }
              False -> #(model, list)
            }
          }
          OnDrop -> {
            let updated_state = State(..state, drag_counter: 0)
            #(Model(..model, interaction: MouseDragging(updated_state)), list)
          }
        }
      }

      // DragLeave: Only process if mouse dragging
      DragLeave, MouseDragging(state) -> {
        let updated_state = State(..state, drop_index: state.drag_index)
        #(Model(..model, interaction: MouseDragging(updated_state)), list)
      }

      // DragEnd: Only process if mouse dragging
      DragEnd, MouseDragging(state) -> {
        case config.listen {
          OnDrop -> {
            case state.drag_index != state.drop_index {
              True -> {
                let updated_list =
                  update_list_for_operation(
                    config.operation,
                    state.drag_index,
                    state.drop_index,
                    list,
                  )
                #(
                  Model(..model, interaction: Idle),
                  config.before_update(
                    state.drag_index,
                    state.drop_index,
                    updated_list,
                  ),
                )
              }
              False -> #(Model(..model, interaction: Idle), list)
            }
          }
          OnDrag -> #(Model(..model, interaction: Idle), list)
        }
      }

      // === TOUCH MESSAGES ===

      // TouchSelect: Only start if idle (mutex lock)
      // Increment generation so old timeouts are ignored
      TouchSelect(index, id), Idle -> {
        let touch_state = TouchState(selected_index: index, selected_id: id)
        let new_gen = model.touch_generation + 1
        #(
          Model(interaction: TouchSelecting(touch_state), touch_generation: new_gen),
          list,
        )
      }

      // TouchDrop: Only process if touch selecting
      TouchDrop(drop_index), TouchSelecting(touch_state) -> {
        case touch_state.selected_index != drop_index {
          True -> {
            // Always use OnDrop-style behavior for touch (single operation)
            let updated_list =
              update_list_for_operation(
                config.operation,
                touch_state.selected_index,
                drop_index,
                list,
              )
            #(
              Model(..model, interaction: Idle),
              config.before_update(
                touch_state.selected_index,
                drop_index,
                updated_list,
              ),
            )
          }
          False -> #(Model(..model, interaction: Idle), list)
        }
      }

      // TouchCancel: Only process if touch selecting
      TouchCancel, TouchSelecting(_) -> #(Model(..model, interaction: Idle), list)

      // TouchTimeout: Only process if generation matches current
      TouchTimeout(gen), TouchSelecting(_) if gen == model.touch_generation ->
        #(Model(..model, interaction: Idle), list)

      // Stale timeout (generation mismatch) - ignore
      TouchTimeout(_), _ -> #(model, list)

      // === CROSS-MODE INTERACTIONS ===

      // Touch events cancel mouse dragging (mutex behavior)
      TouchSelect(_, _), MouseDragging(_) ->
        #(Model(..model, interaction: Idle), list)
      TouchDrop(_), MouseDragging(_) -> #(Model(..model, interaction: Idle), list)
      TouchCancel, MouseDragging(_) -> #(Model(..model, interaction: Idle), list)

      // Mouse events are ignored during touch selecting
      DragStart(_, _, _), TouchSelecting(_) -> #(model, list)
      Drag(_), TouchSelecting(_) -> #(model, list)
      DragOver(_, _), TouchSelecting(_) -> #(model, list)
      DragEnter(_), TouchSelecting(_) -> #(model, list)
      DragLeave, TouchSelecting(_) -> #(model, list)
      DragEnd, TouchSelecting(_) -> #(model, list)

      // === FALLBACK ===

      // Ignore all other combinations (e.g., mouse events when idle)
      _, _ -> #(model, list)
    }
  }
}

// System update with effect (for touch timeout)
fn system_update_with_effect(
  config: Config(a),
  step_msg: fn(DndMsg) -> msg,
) -> fn(DndMsg, Model, List(a)) -> #(Model, List(a), Effect(msg)) {
  let base_update = system_update(config)

  fn(msg: DndMsg, model: Model, list: List(a)) -> #(Model, List(a), Effect(msg)) {
    let #(new_model, new_list) = base_update(msg, model, list)

    // Schedule timeout effect when entering touch selection mode
    // Pass the generation so stale timeouts are ignored
    let eff = case msg, new_model.interaction, config.touch_timeout_ms {
      TouchSelect(_, _), TouchSelecting(_), timeout_ms if timeout_ms > 0 ->
        schedule_timeout(timeout_ms, new_model.touch_generation, step_msg)
      _, _, _ -> effect.none()
    }

    #(new_model, new_list, eff)
  }
}

// Schedule timeout for touch auto-cancel
fn schedule_timeout(
  timeout_ms: Int,
  generation: Int,
  step_msg: fn(DndMsg) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    promise.wait(timeout_ms)
    |> promise.tap(fn(_) { dispatch(step_msg(TouchTimeout(generation))) })
    Nil
  })
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

fn update_list_for_operation(
  operation: Operation,
  drag_index: Int,
  drop_index: Int,
  list: List(a),
) -> List(a) {
  case operation {
    InsertAfter -> insert_after(drag_index, drop_index, list)
    InsertBefore -> insert_before(drag_index, drop_index, list)
    Rotate -> rotate_items(drag_index, drop_index, list)
    Swap -> swap_items(drag_index, drop_index, list)
    Unaltered -> list
  }
}

// Helper function to split a list at a given index
pub fn split_at(index: Int, list: List(a)) -> #(List(a), List(a)) {
  #(list.take(list, index), list.drop(list, index))
}

// InsertAfter operation
pub fn insert_after(drag_index: Int, drop_index: Int, list: List(a)) -> List(a) {
  case drag_index < drop_index {
    True -> after_forward(drag_index, drop_index, list)
    False ->
      case drop_index < drag_index {
        True -> after_backward(drag_index, drop_index, list)
        False -> list
      }
  }
}

// InsertBefore operation
pub fn insert_before(drag_index: Int, drop_index: Int, list: List(a)) -> List(a) {
  case drag_index < drop_index {
    True -> before_forward(drag_index, drop_index, list)
    False ->
      case drop_index < drag_index {
        True -> before_backward(drag_index, drop_index, list)
        False -> list
      }
  }
}

// Rotate operation
pub fn rotate_items(drag_index: Int, drop_index: Int, list: List(a)) -> List(a) {
  case drag_index < drop_index {
    True -> after_forward(drag_index, drop_index, list)
    False ->
      case drop_index < drag_index {
        True -> before_backward(drag_index, drop_index, list)
        False -> list
      }
  }
}

// Swap operation
pub fn swap_items(drag_index: Int, drop_index: Int, list: List(a)) -> List(a) {
  case drag_index != drop_index {
    True -> swap_at(drag_index, drop_index, list)
    False -> list
  }
}

// Helper functions for different movement directions
pub fn after_backward(i: Int, j: Int, list: List(a)) -> List(a) {
  let #(beginning, rest) = split_at(j + 1, list)
  let #(middle, end) = split_at(i - j - 1, rest)
  let #(head, tail) = split_at(1, end)

  list.append(list.append(list.append(beginning, head), middle), tail)
}

pub fn after_forward(i: Int, j: Int, list: List(a)) -> List(a) {
  let #(beginning, rest) = split_at(i, list)
  let #(middle, end) = split_at(j - i + 1, rest)
  let #(head, tail) = split_at(1, middle)

  list.append(list.append(list.append(beginning, tail), head), end)
}

pub fn before_backward(i: Int, j: Int, list: List(a)) -> List(a) {
  let #(beginning, rest) = split_at(j, list)
  let #(middle, end) = split_at(i - j, rest)
  let #(head, tail) = split_at(1, end)

  list.append(list.append(list.append(beginning, head), middle), tail)
}

pub fn before_forward(i: Int, j: Int, list: List(a)) -> List(a) {
  let #(beginning, rest) = split_at(i, list)
  let #(middle, end) = split_at(j - i, rest)
  let #(head, tail) = split_at(1, middle)

  list.append(list.append(list.append(beginning, tail), head), end)
}

pub fn swap_at(i: Int, j: Int, list: List(a)) -> List(a) {
  let item_i = list.drop(list, i) |> list.take(1)
  let item_j = list.drop(list, j) |> list.take(1)

  list.index_map(list, fn(item, index) {
    case index {
      idx if idx == i -> item_j
      idx if idx == j -> item_i
      _ -> [item]
    }
  })
  |> list.flatten()
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

// TOUCH EVENT HANDLERS --------------------------------------------------------

/// Touch grip events - touchend handler for entering touch selection mode.
/// Apply to the grip handle or the entire draggable item.
/// Uses touchend for immediate response on mobile (no 300ms click delay).
fn touch_grip_events(
  step_msg: fn(DndMsg) -> msg,
) -> fn(Int, String) -> List(Attribute(msg)) {
  fn(index: Int, element_id: String) -> List(Attribute(msg)) {
    [
      event.on(
        "touchend",
        decode.success(step_msg(TouchSelect(index, element_id))),
      ),
    ]
  }
}

/// Touch drop zone events - touchend handler for drop zones in touch mode.
/// Apply to drop zone elements rendered between items.
fn touch_drop_zone_events(
  step_msg: fn(DndMsg) -> msg,
) -> fn(Int) -> List(Attribute(msg)) {
  fn(drop_index: Int) -> List(Attribute(msg)) {
    [event.on("touchend", decode.success(step_msg(TouchDrop(drop_index))))]
  }
}

/// Cancel events - currently returns empty list.
/// Touch cancellation is handled via timeout (touch_timeout_ms config).
/// Note: Container-level touchstart/touchend would interfere with grip/drop
/// events due to event bubbling. Users can add an explicit cancel button
/// that sends TouchCancel if needed.
fn cancel_events(_step_msg: fn(DndMsg) -> msg) -> fn() -> List(Attribute(msg)) {
  fn() -> List(Attribute(msg)) { [] }
}

// GHOST STYLES ---------------------------------------------------------------

fn ghost_styles(movement: Movement) -> fn(Model) -> List(Attribute(msg)) {
  fn(model: Model) -> List(Attribute(msg)) {
    case model.interaction {
      // Ghost element only shown during mouse dragging
      MouseDragging(state) -> {
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
      // No ghost for touch mode or idle state
      TouchSelecting(_) -> []
      Idle -> []
    }
  }
}

// INFO EXTRACTION -------------------------------------------------------------

pub fn get_info(model: Model) -> Option(Info) {
  case model.interaction {
    MouseDragging(state) -> {
      Some(Info(
        drag_index: state.drag_index,
        drop_index: state.drop_index,
        drag_element_id: state.drag_element_id,
        drop_element_id: state.drop_element_id,
        start_position: state.start_position,
        current_position: state.current_position,
      ))
    }
    TouchSelecting(_) -> None
    Idle -> None
  }
}

// TOUCH STATE HELPERS ---------------------------------------------------------

/// Check if the system is currently in touch selection mode.
pub fn is_touch_selecting(model: Model) -> Bool {
  case model.interaction {
    TouchSelecting(_) -> True
    _ -> False
  }
}

/// Get the index of the currently selected item in touch mode.
/// Returns None if not in touch selection mode.
pub fn get_selected_index(model: Model) -> Option(Int) {
  case model.interaction {
    TouchSelecting(touch_state) -> Some(touch_state.selected_index)
    _ -> None
  }
}
