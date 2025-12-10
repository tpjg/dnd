import dnd
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/javascript/promise
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
pub type InputMode {
  MouseOnly
  TouchOnly
  Auto
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
/// - `mode`: Input mode for the system (MouseOnly, TouchOnly, or Auto). Default: MouseOnly
/// - `touch_timeout_ms`: Milliseconds before touch selection auto-cancels. Default: 5000. Set to 0 to disable.
/// - `touch_scroll_threshold`: Distance in pixels to distinguish tap from scroll. Default: 10.
/// - `touch_hold_duration_ms`: Minimum milliseconds to hold before touch selection activates. Default: 200.
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
///   movement: groups.Free,
///   listen: groups.OnDrag,
///   operation: groups.Rotate,
///   groups: groups.GroupsConfig(
///     listen: groups.OnDrag,
///     operation: groups.InsertBefore,
///     comparator: fn(a, b) { a.group == b.group },
///     setter: fn(target, drag) { Item(..drag, group: target.group) },
///   ),
///   mode: groups.MouseOnly,
///   touch_timeout_ms: 5000,
///   touch_scroll_threshold: 10,
///   touch_hold_duration_ms: 200,
/// )
/// ```
pub type Config(a) {
  Config(
    before_update: fn(Int, Int, List(a)) -> List(a),
    movement: Movement,
    listen: Listen,
    operation: Operation,
    groups: GroupsConfig(a),
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
pub type InteractionState {
  Idle
  MouseDragging(State)
  TouchPending(TouchPendingState)
  TouchSelecting(TouchState)
}

pub type Model {
  Model(interaction: InteractionState, touch_generation: Int)
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
///
/// ## Touch Support
///
/// For touch-enabled modes, use the additional fields:
/// - `update_with_effect`, `touch_grip_events`, `touch_drop_zone_events`, etc.
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
  // Mouse messages
  DragStart(Int, String, Position)
  Drag(Position)
  DragOver(Int, String)
  DragEnter(Int)
  DragLeave
  DragEnd
  // Touch messages
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
      // DragStart: Only start if idle
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

      // DragEnter: Group-aware processing
      DragEnter(drop_index), MouseDragging(state) -> {
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
                  Model(..model, interaction: MouseDragging(updated_state)),
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
                  Model(..model, interaction: MouseDragging(updated_state)),
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
                #(
                  Model(..model, interaction: MouseDragging(updated_state)),
                  list,
                )
              }
            }
          }
          False -> #(model, list)
        }
      }

      // DragLeave: Only process if mouse dragging
      DragLeave, MouseDragging(state) -> {
        let updated_state = State(..state, drop_index: state.drag_index)
        #(Model(..model, interaction: MouseDragging(updated_state)), list)
      }

      // DragEnd: Group-aware processing
      DragEnd, MouseDragging(state) -> {
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
                  Model(..model, interaction: Idle),
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
                  Model(..model, interaction: Idle),
                  config.before_update(
                    state.drag_index,
                    state.drop_index,
                    updated_list,
                  ),
                )
              }
              // No operation for other cases
              _, _, _ -> #(Model(..model, interaction: Idle), list)
            }
          }
          False -> #(Model(..model, interaction: Idle), list)
        }
      }

      // === TOUCH MESSAGES ===
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

      // TouchDrop: Group-aware processing for touch (only if drop enabled AND within distance)
      TouchDrop(drop_index, end_position), TouchSelecting(touch_state) -> {
        case touch_state.drop_enabled, touch_state.drop_touch_start {
          False, _ ->
            // Cooldown not elapsed - ignore drop
            #(model, list)
          True, None ->
            // No start position recorded - ignore
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
                    let equal_groups =
                      groups_equal(
                        config.groups.comparator,
                        touch_state.selected_index,
                        drop_index,
                        list,
                      )

                    // Use OnDrop-style behavior for touch (single operation)
                    case equal_groups {
                      True -> {
                        // Same group: use main operation
                        let updated_list =
                          sublist_update(
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
                      False -> {
                        // Cross group: use groups operation with setter
                        let updated_list =
                          groups_list_update(
                            config.groups.operation,
                            config.groups.comparator,
                            config.groups.setter,
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
                    }
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

// Schedule hold duration timer for touch selection
fn schedule_hold_duration(
  duration_ms: Int,
  generation: Int,
  step_msg: fn(DndMsg) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    promise.wait(duration_ms)
    |> promise.tap(fn(_) { dispatch(step_msg(TouchDurationMet(generation))) })
    Nil
  })
}

// Schedule drop cooldown timer - enables drops after layout settles
fn schedule_drop_cooldown(
  cooldown_ms: Int,
  generation: Int,
  step_msg: fn(DndMsg) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    promise.wait(cooldown_ms)
    |> promise.tap(fn(_) {
      dispatch(step_msg(TouchDropCooldownComplete(generation)))
    })
    Nil
  })
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
      // touchstart with preventDefault to stop mousedown synthesis
      event.advanced("touchstart", {
        use position <- decode.then(decode_touch_position())
        decode.success(event.handler(
          dispatch: step_msg(TouchStart(index, element_id, position)),
          prevent_default: True,
          stop_propagation: False,
        ))
      }),
      // touchmove - track movement to detect scrolling (no preventDefault to allow scrolling)
      event.on("touchmove", {
        use position <- decode.then(decode_touch_position())
        decode.success(step_msg(TouchMove(position)))
      }),
      // touchend
      event.on("touchend", {
        use position <- decode.then(decode_touch_position())
        decode.success(step_msg(TouchEnd(position)))
      }),
    ]
  }
}

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
/// Touch cancellation is handled via timeout (touch_timeout_ms config).
fn cancel_events(_step_msg: fn(DndMsg) -> msg) -> fn() -> List(Attribute(msg)) {
  fn() -> List(Attribute(msg)) { [] }
}

// GHOST STYLES ---------------------------------------------------------------

fn ghost_styles(movement: Movement) -> fn(Model) -> List(Attribute(msg)) {
  fn(model: Model) -> List(Attribute(msg)) {
    case model.interaction {
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

fn get_info(model: Model) -> Option(Info) {
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

pub fn is_touch_selecting(model: Model) -> Bool {
  case model.interaction {
    TouchSelecting(_) -> True
    _ -> False
  }
}

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
