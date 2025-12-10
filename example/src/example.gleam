import dnd
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// APPLICATION MODEL AND MSG --------------------------------------------------

type Model {
  Model(system: dnd.System(String, Msg), items: List(String))
}

type Msg {
  DndMsg(dnd.DndMsg)
}

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// INITIALIZATION --------------------------------------------------------------

fn init(_flags) -> #(Model, Effect(Msg)) {
  let config =
    dnd.Config(
      before_update: fn(_, _, list) { list },
      movement: dnd.Vertical,
      listen: dnd.OnDrag,
      operation: dnd.Rotate,
      // Enable Auto mode for both mouse and touch support
      mode: dnd.Auto,
      // Auto-cancel touch selection after 5 seconds
      touch_timeout_ms: 5000,
    )

  let system = dnd.create(config, DndMsg)
  let initial_items = ["Apple", "Banana", "Cherry", "Date", "Elderberry"]

  #(Model(system: system, items: initial_items), effect.none())
}

// UPDATE ----------------------------------------------------------------------

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    DndMsg(dnd_msg) -> {
      // Use update_with_effect for touch timeout support
      let #(new_dnd, new_items, dnd_effect) =
        model.system.update_with_effect(
          dnd_msg,
          model.system.model,
          model.items,
        )

      let updated_system = dnd.System(..model.system, model: new_dnd)

      // The effect is already typed as Effect(Msg) since the system
      // was created with the DndMsg wrapper
      #(Model(system: updated_system, items: new_items), dnd_effect)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let system = model.system
  let dnd_model = system.model
  let is_selecting = system.is_touch_selecting(dnd_model)

  html.div(
    list.flatten([
      [
        attribute.class("min-h-screen bg-gray-50 p-8"),
        attribute.style("user-select", "none"),
        attribute.style("-webkit-user-select", "none"),
      ],
      // Global mouse events for dragging
      case system.info(dnd_model) {
        Some(_) -> [
          event.on("mousemove", {
            use client_x <- decode.field("clientX", decode.float)
            use client_y <- decode.field("clientY", decode.float)
            decode.success(DndMsg(dnd.Drag(dnd.Position(client_x, client_y))))
          }),
          event.on("mouseup", decode.success(DndMsg(dnd.DragEnd))),
          event.on("mouseleave", decode.success(DndMsg(dnd.DragEnd))),
        ]
        None -> []
      },
      // Touch cancel events - tapping outside during selection cancels it
      system.cancel_events(),
    ]),
    [
      html.div([attribute.class("max-w-md mx-auto")], [
        html.h1([attribute.class("text-2xl font-bold mb-6 text-center")], [
          html.text("Drag and Drop List"),
        ]),
        html.p([attribute.class("text-sm text-gray-500 mb-4 text-center")], [
          html.text(
            "Mouse: drag items. Touch: tap item to select, tap drop zone to move.",
          ),
        ]),
        // Show selection indicator when touch-selecting
        case is_selecting {
          True ->
            html.div(
              [
                attribute.class(
                  "mb-4 p-2 bg-blue-100 border border-blue-300 rounded text-blue-700 text-sm text-center",
                ),
              ],
              [
                html.text(
                  "Touch selection mode - tap a drop zone or tap elsewhere to cancel",
                ),
              ],
            )
          False -> html.text("")
        },
        html.div(
          [attribute.class("space-y-2")],
          render_items_with_drop_zones(model),
        ),
        ghost_view(system, dnd_model, model.items),
      ]),
    ],
  )
}

// Render items with interleaved drop zones when touch-selecting
fn render_items_with_drop_zones(model: Model) -> List(Element(Msg)) {
  let system = model.system
  let dnd_model = system.model
  let is_selecting = system.is_touch_selecting(dnd_model)

  let items_with_zones =
    list.index_map(model.items, fn(item, index) {
      let item_el = item_view(system, dnd_model, index, item)
      case is_selecting {
        True -> [drop_zone_view(system, index), item_el]
        False -> [item_el]
      }
    })
    |> list.flatten

  // Add final drop zone after last item when selecting
  case is_selecting {
    True ->
      list.append(items_with_zones, [
        drop_zone_view(system, list.length(model.items)),
      ])
    False -> items_with_zones
  }
}

// Drop zone view - shown between items during touch selection
fn drop_zone_view(system: dnd.System(String, Msg), index: Int) -> Element(Msg) {
  html.div(
    list.flatten([
      [
        attribute.class(
          "h-11 my-1 mx-2 border-2 border-dashed border-blue-300 rounded-lg flex items-center justify-center text-blue-400 text-sm hover:bg-blue-50 transition-colors cursor-pointer",
        ),
      ],
      system.touch_drop_zone_events(index),
    ]),
    [html.text("Drop here")],
  )
}

fn item_view(
  system: dnd.System(String, Msg),
  dnd_model: dnd.Model,
  index: Int,
  item: String,
) -> Element(Msg) {
  let item_id = "item-" <> int.to_string(index)
  let is_selecting = system.is_touch_selecting(dnd_model)
  let selected_index = system.selected_index(dnd_model)

  // Check if this item is currently selected (touch mode)
  let is_selected = case selected_index {
    Some(i) -> i == index
    None -> False
  }

  case system.info(dnd_model) {
    Some(info) -> {
      case info.drag_index == index {
        True -> {
          // Dragged item - show placeholder
          html.div(
            [
              attribute.id(item_id),
              attribute.class(
                "h-12 border-2 border-dashed border-gray-300 rounded-lg flex items-center justify-center",
              ),
              attribute.style("user-select", "none"),
              attribute.style("-webkit-user-select", "none"),
            ],
            [html.text("[---------]")],
          )
        }
        False -> {
          // Drop target
          html.div(
            [
              attribute.id(item_id),
              attribute.class(
                "h-12 bg-white border border-gray-200 rounded-lg shadow-sm hover:shadow-md transition-shadow cursor-move flex items-center px-4",
              ),
              attribute.style("user-select", "none"),
              attribute.style("-webkit-user-select", "none"),
              ..system.drop_events(index, item_id)
            ],
            [html.text(item)],
          )
        }
      }
    }
    None -> {
      // Normal state - combine mouse drag events and touch grip events
      let base_class =
        "h-12 bg-white border rounded-lg shadow-sm hover:shadow-md transition-shadow cursor-move flex items-center px-4"
      let selected_class = case is_selected {
        True -> " border-blue-500 border-2 ring-2 ring-blue-200"
        False -> " border-gray-200"
      }

      html.div(
        list.flatten([
          [
            attribute.id(item_id),
            attribute.class(base_class <> selected_class),
            attribute.style("user-select", "none"),
            attribute.style("-webkit-user-select", "none"),
          ],
          // Mouse drag events (ignored during touch selection due to mutex)
          case is_selecting {
            True -> []
            False -> system.drag_events(index, item_id)
          },
          // Touch grip events - tap to select
          system.touch_grip_events(index, item_id),
        ]),
        [html.text(item)],
      )
    }
  }
}

fn ghost_view(
  system: dnd.System(String, Msg),
  dnd_model: dnd.Model,
  items: List(String),
) -> Element(Msg) {
  case system.info(dnd_model) {
    Some(info) -> {
      case list.drop(items, info.drag_index) |> list.first() {
        Ok(item) -> {
          html.div(
            list.append(system.ghost_styles(dnd_model), [
              // Visual styling for the ghost element
              attribute.style("height", "40px"),
              attribute.style("width", "200px"),
              attribute.style("background-color", "#f3f4f6"),
              attribute.style("border", "1px solid #d1d5db"),
              attribute.style("border-radius", "4px"),
              attribute.style("display", "flex"),
              attribute.style("align-items", "center"),
              attribute.style("padding", "8px"),
            ]),
            [html.text(item)],
          )
        }
        Error(_) -> html.text("")
      }
    }
    None -> html.text("")
  }
}
