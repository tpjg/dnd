import dnd
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre
import lustre/attribute
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
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// INITIALIZATION --------------------------------------------------------------

fn init(_flags) -> Model {
  let config =
    dnd.Config(
      before_update: fn(_, _, list) { list },
      movement: dnd.Free,
      listen: dnd.OnDrag,
      operation: dnd.Rotate,
    )

  let system = dnd.create(config, DndMsg)
  let initial_items = ["Apple", "Banana", "Cherry", "Date", "Elderberry"]

  Model(system: system, items: initial_items)
}

// UPDATE ----------------------------------------------------------------------

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

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("min-h-screen bg-gray-50 p-8"),
      attribute.style("user-select", "none"),
      attribute.style("-webkit-user-select", "none"),
      // Global mouse events for dragging
      case model.system.info(model.system.model) {
        Some(_) -> {
          event.on("mousemove", {
            use client_x <- decode.field("clientX", decode.float)
            use client_y <- decode.field("clientY", decode.float)
            decode.success(DndMsg(dnd.Drag(dnd.Position(client_x, client_y))))
          })
        }
        None -> attribute.none()
      },
      case model.system.info(model.system.model) {
        Some(_) -> event.on("mouseup", decode.success(DndMsg(dnd.DragEnd)))
        None -> attribute.none()
      },
    ],
    [
      html.div([attribute.class("max-w-md mx-auto")], [
        html.h1([attribute.class("text-2xl font-bold mb-6 text-center")], [
          html.text("Drag and Drop List"),
        ]),
        html.div(
          [attribute.class("space-y-2")],
          list.index_map(model.items, fn(item, index) {
            item_view(model.system, model.system.model, index, item)
          }),
        ),
        ghost_view(model.system, model.system.model, model.items),
      ]),
    ],
  )
}

fn item_view(
  system: dnd.System(String, Msg),
  dnd_model: dnd.Model,
  index: Int,
  item: String,
) -> Element(Msg) {
  let item_id = "item-" <> int.to_string(index)

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
      // Normal state
      html.div(
        [
          attribute.id(item_id),
          attribute.class(
            "h-12 bg-white border border-gray-200 rounded-lg shadow-sm hover:shadow-md transition-shadow cursor-move flex items-center px-4",
          ),
          attribute.style("user-select", "none"),
          attribute.style("-webkit-user-select", "none"),
          ..system.drag_events(index, item_id)
        ],
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
