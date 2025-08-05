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

pub type Listen {
  OnDrag
  OnDrop
}

pub type Operation {
  InsertAfter
  InsertBefore
  Rotate
  Swap
  Unaltered
}

pub type Config(a) {
  Config(
    before_update: fn(Int, Int, List(a)) -> List(a),
    movement: Movement,
    listen: Listen,
    operation: Operation,
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
        case model, config.listen {
          Model(Some(state)), OnDrag -> {
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
                  Model(Some(updated_state)),
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
          _, _ -> {
            case model {
              Model(Some(state)) -> {
                let updated_state = State(..state, drag_counter: 0)
                #(Model(Some(updated_state)), list)
              }
              Model(None) -> #(model, list)
            }
          }
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
        case model, config.listen {
          Model(Some(state)), OnDrop -> {
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
                  Model(None),
                  config.before_update(
                    state.drag_index,
                    state.drop_index,
                    updated_list,
                  ),
                )
              }
              False -> #(Model(None), list)
            }
          }
          _, _ -> #(Model(None), list)
        }
      }
    }
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
fn split_at(index: Int, list: List(a)) -> #(List(a), List(a)) {
  #(list.take(list, index), list.drop(list, index))
}

// InsertAfter operation
fn insert_after(drag_index: Int, drop_index: Int, list: List(a)) -> List(a) {
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
fn insert_before(drag_index: Int, drop_index: Int, list: List(a)) -> List(a) {
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
fn rotate_items(drag_index: Int, drop_index: Int, list: List(a)) -> List(a) {
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
fn swap_items(drag_index: Int, drop_index: Int, list: List(a)) -> List(a) {
  case drag_index != drop_index {
    True -> swap_at(drag_index, drop_index, list)
    False -> list
  }
}

// Helper functions for different movement directions
fn after_backward(i: Int, j: Int, list: List(a)) -> List(a) {
  let #(beginning, rest) = split_at(j + 1, list)
  let #(middle, end) = split_at(i - j - 1, rest)
  let #(head, tail) = split_at(1, end)

  list.append(list.append(list.append(beginning, head), middle), tail)
}

fn after_forward(i: Int, j: Int, list: List(a)) -> List(a) {
  let #(beginning, rest) = split_at(i, list)
  let #(middle, end) = split_at(j - i + 1, rest)
  let #(head, tail) = split_at(1, middle)

  list.append(list.append(list.append(beginning, tail), head), end)
}

fn before_backward(i: Int, j: Int, list: List(a)) -> List(a) {
  let #(beginning, rest) = split_at(j, list)
  let #(middle, end) = split_at(i - j, rest)
  let #(head, tail) = split_at(1, end)

  list.append(list.append(list.append(beginning, head), middle), tail)
}

fn before_forward(i: Int, j: Int, list: List(a)) -> List(a) {
  let #(beginning, rest) = split_at(i, list)
  let #(middle, end) = split_at(j - i, rest)
  let #(head, tail) = split_at(1, middle)

  list.append(list.append(list.append(beginning, tail), head), end)
}

fn swap_at(i: Int, j: Int, list: List(a)) -> List(a) {
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
