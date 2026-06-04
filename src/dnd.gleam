import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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
/// - `touch_scroll_threshold`: Distance in pixels to distinguish tap from scroll. Default: 10.
///   If the user moves more than this distance between touchstart and touchend, it's treated
///   as a scroll gesture and the touch selection is cancelled.
/// - `touch_hold_duration_ms`: Minimum milliseconds to hold before touch selection activates. Default: 200.
///   This prevents accidental selection when quickly tapping. Set to 0 to disable.
/// - `touch_drop_cooldown_ms`: Milliseconds after pop before drops are accepted. Default: 500.
///   This prevents accidental drops when the layout shifts and drop zones appear under the finger.
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
///   touch_scroll_threshold: 10,
///   touch_hold_duration_ms: 200,
///   touch_drop_cooldown_ms: 500,
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
///   touch_scroll_threshold: 10,
///   touch_hold_duration_ms: 200,
///   touch_drop_cooldown_ms: 500,
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
    touch_scroll_threshold: Int,
    touch_hold_duration_ms: Int,
    touch_drop_cooldown_ms: Int,
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
/// The scroll_start field tracks when user begins a potential scroll gesture
/// while in selection mode, allowing us to reset the timeout on scroll.
pub type TouchState {
  TouchState(
    selected_index: Int,
    selected_id: String,
    scroll_start: Option(Position),
    drop_enabled: Bool,
    drop_touch_start: Option(Position),
  )
}

/// Touch pending state - awaiting touchend to determine if tap or scroll.
/// The duration_met field tracks whether the minimum hold duration has elapsed.
pub type TouchPendingState {
  TouchPendingState(
    index: Int,
    element_id: String,
    start_position: Position,
    duration_met: Bool,
  )
}

/// Interaction state - tracks whether we're idle, mouse dragging, or touch selecting.
/// This is used internally by the Model type.
pub type InteractionState {
  Idle
  MouseDragging(State)
  TouchPending(TouchPendingState)
  TouchSelecting(TouchState)
}

pub type Model {
  Model(
    interaction: InteractionState,
    touch_generation: Int,
    /// Blocks synthesized mouse events after touch interactions
    mouse_blocked: Bool,
  )
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
/// - `touch_selected_styles`: Returns pop animation styles for the selected item
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
    update_with_effect: fn(DndMsg, Model, List(a)) ->
      #(Model, List(a), Effect(msg)),
    touch_grip_events: fn(Int, String) -> List(Attribute(msg)),
    touch_drop_zone_events: fn(Int) -> List(Attribute(msg)),
    cancel_events: fn() -> List(Attribute(msg)),
    is_touch_selecting: fn(Model) -> Bool,
    selected_index: fn(Model) -> Option(Int),
    touch_selected_styles: fn(Model, Int) -> List(Attribute(msg)),
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
  TouchStart(Int, String, Position)
  TouchMove(Position)
  TouchEnd(Position)
  TouchSelect(Int, String)
  TouchDropStart(Position)
  TouchDrop(Int, Position)
  TouchCancel
  TouchTimeout(Int)
  TouchDurationMet(Int)
  TouchDropCooldownComplete(Int)
}

// SYSTEM CREATION -------------------------------------------------------------

pub fn create(config: Config(a), step_msg: fn(DndMsg) -> msg) -> System(a, msg) {
  System(
    model: Model(interaction: Idle, touch_generation: 0, mouse_blocked: False),
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
    touch_selected_styles: touch_selected_styles,
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
      // Also ignore if mouse_blocked (synthesized event after touch)
      DragStart(_, _, _), Idle if model.mouse_blocked -> {
        // Consume the synthesized mousedown, clear the block
        #(Model(..model, mouse_blocked: False), list)
      }
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
                  config.before_update(
                    state.drag_index,
                    drop_index,
                    updated_list,
                  ),
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
      // TouchStart during pending: second finger added (pinch), cancel
      TouchStart(_, _, _), TouchPending(_) -> {
        #(Model(..model, interaction: Idle), list)
      }

      // TouchStart: Begin pending state, waiting for hold duration
      TouchStart(index, id, position), Idle -> {
        // If hold duration is 0, we'll enter selection on TouchEnd (immediate mode)
        // If hold duration > 0, we'll enter selection on TouchDurationMet (hold mode)
        let duration_met = config.touch_hold_duration_ms == 0
        let pending_state =
          TouchPendingState(
            index: index,
            element_id: id,
            start_position: position,
            duration_met: duration_met,
          )
        // Increment generation for the hold duration timer
        let new_gen = model.touch_generation + 1
        #(
          Model(
            interaction: TouchPending(pending_state),
            touch_generation: new_gen,
            // Block synthesized mouse events until we see one
            mouse_blocked: True,
          ),
          list,
        )
      }

      // TouchMove during pending: check if user is scrolling
      TouchMove(position), TouchPending(pending) -> {
        case
          is_within_threshold(
            pending.start_position,
            position,
            config.touch_scroll_threshold,
          )
        {
          True -> {
            // Still within threshold - stay pending
            #(model, list)
          }
          False -> {
            // Moved too far - user is scrolling, cancel pending
            #(Model(..model, interaction: Idle), list)
          }
        }
      }

      // TouchDurationMet: Hold duration elapsed - enter selection mode immediately!
      // This is the "pop" moment - drag is now active, user can release
      TouchDurationMet(gen), TouchPending(pending)
        if gen == model.touch_generation
      -> {
        let touch_state =
          TouchState(
            selected_index: pending.index,
            selected_id: pending.element_id,
            scroll_start: None,
            drop_enabled: False,
            drop_touch_start: None,
          )
        let new_gen = model.touch_generation + 1
        #(
          Model(
            ..model,
            interaction: TouchSelecting(touch_state),
            touch_generation: new_gen,
          ),
          list,
        )
      }

      // Stale duration timer - ignore
      TouchDurationMet(_), _ -> #(model, list)

      // TouchDropCooldownComplete: Enable drops after cooldown period
      TouchDropCooldownComplete(gen), TouchSelecting(touch_state)
        if gen == model.touch_generation
      -> {
        let updated_touch_state = TouchState(..touch_state, drop_enabled: True)
        #(
          Model(..model, interaction: TouchSelecting(updated_touch_state)),
          list,
        )
      }

      // Stale cooldown timer - ignore
      TouchDropCooldownComplete(_), _ -> #(model, list)

      // TouchEnd during pending: behavior depends on mode
      TouchEnd(end_position), TouchPending(pending) -> {
        case pending.duration_met {
          True -> {
            // Immediate mode (duration was 0): check distance, enter selection if OK
            let within_distance =
              is_within_threshold(
                pending.start_position,
                end_position,
                config.touch_scroll_threshold,
              )
            case within_distance {
              True -> {
                // Immediate mode: drop enabled immediately (finger already lifted)
                let touch_state =
                  TouchState(
                    selected_index: pending.index,
                    selected_id: pending.element_id,
                    scroll_start: None,
                    drop_enabled: True,
                    drop_touch_start: None,
                  )
                let new_gen = model.touch_generation + 1
                #(
                  Model(
                    ..model,
                    interaction: TouchSelecting(touch_state),
                    touch_generation: new_gen,
                  ),
                  list,
                )
              }
              False -> {
                // Moved too far - was scrolling
                #(Model(..model, interaction: Idle), list)
              }
            }
          }
          False -> {
            // Hold mode: user released before duration elapsed - cancel
            #(Model(..model, interaction: Idle), list)
          }
        }
      }

      // TouchStart while selecting: track position for scroll detection
      // If user scrolls while selecting, we'll reset the timeout
      TouchStart(_, _, position), TouchSelecting(touch_state) -> {
        let updated_touch_state =
          TouchState(..touch_state, scroll_start: Some(position))
        #(
          Model(..model, interaction: TouchSelecting(updated_touch_state)),
          list,
        )
      }

      // TouchEnd while selecting: check if it was a scroll gesture
      // If scroll distance is large, reset the timer by incrementing generation
      TouchEnd(end_position), TouchSelecting(touch_state) -> {
        case touch_state.scroll_start {
          Some(start_pos) -> {
            case
              is_within_threshold(
                start_pos,
                end_position,
                config.touch_scroll_threshold,
              )
            {
              True -> {
                // Small distance - user tapped, clear scroll_start
                let updated_touch_state =
                  TouchState(..touch_state, scroll_start: None)
                #(
                  Model(
                    ..model,
                    interaction: TouchSelecting(updated_touch_state),
                  ),
                  list,
                )
              }
              False -> {
                // Large distance - user scrolled, reset timer by incrementing generation
                let updated_touch_state =
                  TouchState(..touch_state, scroll_start: None)
                let new_gen = model.touch_generation + 1
                #(
                  Model(
                    ..model,
                    interaction: TouchSelecting(updated_touch_state),
                    touch_generation: new_gen,
                  ),
                  list,
                )
              }
            }
          }
          None -> #(model, list)
        }
      }

      // TouchSelect: Direct selection (backwards compatibility / programmatic use)
      // Increment generation so old timeouts are ignored
      TouchSelect(index, id), Idle -> {
        let touch_state =
          TouchState(
            selected_index: index,
            selected_id: id,
            scroll_start: None,
            drop_enabled: True,
            drop_touch_start: None,
          )
        let new_gen = model.touch_generation + 1
        #(
          Model(
            ..model,
            interaction: TouchSelecting(touch_state),
            touch_generation: new_gen,
          ),
          list,
        )
      }

      // TouchDropStart: Record start position when touching a drop zone
      TouchDropStart(position), TouchSelecting(touch_state) -> {
        let updated_touch_state =
          TouchState(..touch_state, drop_touch_start: Some(position))
        #(
          Model(..model, interaction: TouchSelecting(updated_touch_state)),
          list,
        )
      }

      // TouchDropStart when not selecting - ignore
      TouchDropStart(_), _ -> #(model, list)

      // TouchDrop: Only process if touch selecting AND drop is enabled AND within distance
      TouchDrop(drop_index, end_position), TouchSelecting(touch_state) -> {
        case touch_state.drop_enabled, touch_state.drop_touch_start {
          False, _ ->
            // Cooldown not elapsed - ignore drop
            #(model, list)
          True, None ->
            // No start position recorded - ignore (shouldn't happen)
            #(model, list)
          True, Some(start_position) -> {
            // Check if this was a tap (small distance) vs scroll (large distance)
            let within_distance =
              is_within_threshold(
                start_position,
                end_position,
                config.touch_scroll_threshold,
              )
            case within_distance {
              False -> {
                // User scrolled - clear drop_touch_start, don't drop
                let updated_touch_state =
                  TouchState(..touch_state, drop_touch_start: None)
                #(
                  Model(
                    ..model,
                    interaction: TouchSelecting(updated_touch_state),
                  ),
                  list,
                )
              }
              True ->
                case touch_state.selected_index != drop_index {
                  True -> {
                    // Perform the drop
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
          }
        }
      }

      // TouchCancel: Process if touch pending or selecting
      TouchCancel, TouchPending(_) -> #(Model(..model, interaction: Idle), list)
      TouchCancel, TouchSelecting(_) -> #(
        Model(..model, interaction: Idle),
        list,
      )

      // TouchTimeout: Only process if generation matches current
      TouchTimeout(gen), TouchSelecting(_) if gen == model.touch_generation -> #(
        Model(..model, interaction: Idle),
        list,
      )

      // Stale timeout (generation mismatch) - ignore
      TouchTimeout(_), _ -> #(model, list)

      // === CROSS-MODE INTERACTIONS ===
      // Touch events cancel mouse dragging (mutex behavior)
      TouchStart(_, _, _), MouseDragging(_) -> #(
        Model(..model, interaction: Idle),
        list,
      )
      TouchMove(_), MouseDragging(_) -> #(
        Model(..model, interaction: Idle),
        list,
      )
      TouchEnd(_), MouseDragging(_) -> #(
        Model(..model, interaction: Idle),
        list,
      )
      TouchSelect(_, _), MouseDragging(_) -> #(
        Model(..model, interaction: Idle),
        list,
      )
      TouchDrop(_, _), MouseDragging(_) -> #(
        Model(..model, interaction: Idle),
        list,
      )
      TouchCancel, MouseDragging(_) -> #(
        Model(..model, interaction: Idle),
        list,
      )

      // Mouse events are ignored during touch pending
      DragStart(_, _, _), TouchPending(_) -> #(model, list)
      Drag(_), TouchPending(_) -> #(model, list)
      DragOver(_, _), TouchPending(_) -> #(model, list)
      DragEnter(_), TouchPending(_) -> #(model, list)
      DragLeave, TouchPending(_) -> #(model, list)
      DragEnd, TouchPending(_) -> #(model, list)

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

// System update with effect (for touch timers)
fn system_update_with_effect(
  config: Config(a),
  step_msg: fn(DndMsg) -> msg,
) -> fn(DndMsg, Model, List(a)) -> #(Model, List(a), Effect(msg)) {
  let base_update = system_update(config)

  fn(msg: DndMsg, model: Model, list: List(a)) -> #(Model, List(a), Effect(msg)) {
    let #(new_model, new_list) = base_update(msg, model, list)

    let generation_changed =
      new_model.touch_generation != model.touch_generation

    // Schedule hold duration timer when entering TouchPending
    let hold_effect = case new_model.interaction, generation_changed {
      TouchPending(_), True if config.touch_hold_duration_ms > 0 ->
        schedule_hold_duration(
          config.touch_hold_duration_ms,
          new_model.touch_generation,
          step_msg,
        )
      _, _ -> effect.none()
    }

    // Schedule selection timeout when entering TouchSelecting
    let timeout_effect = case new_model.interaction, generation_changed {
      TouchSelecting(_), True if config.touch_timeout_ms > 0 ->
        schedule_timeout(
          config.touch_timeout_ms,
          new_model.touch_generation,
          step_msg,
        )
      _, _ -> effect.none()
    }

    // Schedule drop cooldown when entering TouchSelecting with drop_enabled=False
    let cooldown_effect = case new_model.interaction, generation_changed {
      TouchSelecting(touch_state), True
        if !touch_state.drop_enabled && config.touch_drop_cooldown_ms > 0
      ->
        schedule_drop_cooldown(
          config.touch_drop_cooldown_ms,
          new_model.touch_generation,
          step_msg,
        )
      _, _ -> effect.none()
    }

    #(
      new_model,
      new_list,
      effect.batch([hold_effect, timeout_effect, cooldown_effect]),
    )
  }
}

@external(erlang, "timer_ffi", "set_timeout")
@external(javascript, "./dnd/timer_ffi.mjs", "set_timeout")
fn set_timeout(_ms: Int, _callback: fn() -> Nil) -> Nil {
  Nil
}

fn schedule_hold_duration(
  duration_ms: Int,
  generation: Int,
  step_msg: fn(DndMsg) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    set_timeout(duration_ms, fn() {
      dispatch(step_msg(TouchDurationMet(generation)))
    })
  })
}

fn schedule_drop_cooldown(
  cooldown_ms: Int,
  generation: Int,
  step_msg: fn(DndMsg) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    set_timeout(cooldown_ms, fn() {
      dispatch(step_msg(TouchDropCooldownComplete(generation)))
    })
  })
}

fn schedule_timeout(
  timeout_ms: Int,
  generation: Int,
  step_msg: fn(DndMsg) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    set_timeout(timeout_ms, fn() {
      dispatch(step_msg(TouchTimeout(generation)))
    })
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

/// Decoder for touch position from touch events.
/// Extracts clientX/clientY from the first touch in changedTouches.
fn decode_touch_position() -> decode.Decoder(Position) {
  use x <- decode.subfield(["changedTouches", "0", "clientX"], decode.float)
  use y <- decode.subfield(["changedTouches", "0", "clientY"], decode.float)
  decode.success(Position(x, y))
}

/// Touch grip events - touchstart captures position, touchmove tracks movement,
/// touchend validates tap vs scroll. Apply to the grip handle or the entire draggable item.
/// Uses preventDefault on touchstart to stop browser from synthesizing mouse events.
fn touch_grip_events(
  step_msg: fn(DndMsg) -> msg,
) -> fn(Int, String) -> List(Attribute(msg)) {
  fn(index: Int, element_id: String) -> List(Attribute(msg)) {
    [
      // touchstart - no preventDefault to allow scrolling during hold
      event.on("touchstart", {
        use position <- decode.then(decode_touch_position())
        decode.success(step_msg(TouchStart(index, element_id, position)))
      }),
      // touchmove - track movement to detect scrolling
      event.on("touchmove", {
        use position <- decode.then(decode_touch_position())
        decode.success(step_msg(TouchMove(position)))
      }),
      // touchend
      event.on("touchend", {
        use position <- decode.then(decode_touch_position())
        decode.success(step_msg(TouchEnd(position)))
      }),
      // touchcancel - iOS/system aborts the touch (scroll handoff, incoming
      // notification, system gesture). Reset now instead of waiting for
      // touch_timeout_ms, otherwise the item stays stuck in selecting mode.
      event.on("touchcancel", decode.success(step_msg(TouchCancel))),
    ]
  }
}

/// Touch drop zone events - touchstart records position, touchend validates distance.
/// Apply to drop zone elements rendered between items.
fn touch_drop_zone_events(
  step_msg: fn(DndMsg) -> msg,
) -> fn(Int) -> List(Attribute(msg)) {
  fn(drop_index: Int) -> List(Attribute(msg)) {
    [
      // touchstart - record start position for distance check
      event.on("touchstart", {
        use position <- decode.then(decode_touch_position())
        decode.success(step_msg(TouchDropStart(position)))
      }),
      // touchend - send drop with end position for distance validation
      event.on("touchend", {
        use position <- decode.then(decode_touch_position())
        decode.success(step_msg(TouchDrop(drop_index, position)))
      }),
    ]
  }
}

/// Cancel events - currently returns empty list.
/// Browser-initiated cancellation is handled by the `touchcancel` listener in
/// `touch_grip_events`; `touch_timeout_ms` remains a backstop. This hook is for
/// an optional explicit cancel affordance (e.g. a button) that sends TouchCancel.
/// Note: container-level touchstart/touchend would interfere with grip/drop
/// events due to event bubbling, so this stays empty by default.
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
      TouchPending(_) -> []
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
    TouchPending(_) -> None
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

/// Returns pop animation styles for the selected item in touch mode.
/// Apply these styles to the item element at the given index.
/// Returns empty list if the index doesn't match the selected item.
///
/// The animation uses CSS keyframes which must be defined in your stylesheet:
/// ```css
/// @keyframes dnd-pop {
///   50% { transform: scale(1.2); }
/// }
/// ```
pub fn touch_selected_styles(model: Model, index: Int) -> List(Attribute(msg)) {
  case model.interaction {
    TouchSelecting(touch_state) if touch_state.selected_index == index -> [
      attribute.style("animation", "dnd-pop 0.2s ease-out"),
    ]
    _ -> []
  }
}

// DISTANCE HELPERS ------------------------------------------------------------

/// Calculate the distance between two positions.
fn distance(p1: Position, p2: Position) -> Float {
  let dx = p2.x -. p1.x
  let dy = p2.y -. p1.y
  float.square_root(dx *. dx +. dy *. dy)
  |> result.unwrap(0.0)
}

/// Check if the distance between two positions is within a threshold.
fn is_within_threshold(p1: Position, p2: Position, threshold: Int) -> Bool {
  distance(p1, p2) <. int.to_float(threshold)
}
