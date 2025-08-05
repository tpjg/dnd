import dnd/groups
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// DATA TYPES ------------------------------------------------------------------

pub type Group {
  Left
  Right
}

pub type Item {
  Item(group: Group, value: String, color: String)
}

// APPLICATION MODEL AND MSG --------------------------------------------------

type Model {
  Model(system: groups.System(Item, Msg), items: List(Item))
}

type Msg {
  DndMsg(groups.DndMsg)
}

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// DATA PREPARATION ------------------------------------------------------------

fn prepared_data() -> List(Item) {
  [
    Item(Left, "C", blue()),
    Item(Left, "2", red()),
    Item(Left, "A", blue()),
    Item(Left, "footer", transparent()),
    Item(Right, "3", red()),
    Item(Right, "1", red()),
    Item(Right, "B", blue()),
    Item(Right, "footer", transparent()),
  ]
}

// SYSTEM CONFIGURATION -------------------------------------------------------

fn comparator(item1: Item, item2: Item) -> Bool {
  item1.group == item2.group
}

fn setter(item1: Item, item2: Item) -> Item {
  Item(..item2, group: item1.group)
}

// INITIALIZATION --------------------------------------------------------------

fn init(_flags) -> Model {
  let config =
    groups.Config(
      before_update: fn(_, _, list) { list },
      listen: groups.OnDrag,
      operation: groups.Rotate,
      groups: groups.GroupsConfig(
        listen: groups.OnDrag,
        operation: groups.InsertBefore,
        comparator: comparator,
        setter: setter,
      ),
    )

  let system = groups.create(config, DndMsg)
  let initial_items = prepared_data()

  Model(system: system, items: initial_items)
}

// UPDATE ----------------------------------------------------------------------

fn update(model: Model, msg: Msg) -> Model {
  case msg {
    DndMsg(dnd_msg) -> {
      let #(new_dnd, new_items) =
        model.system.update(dnd_msg, model.system.model, model.items)

      let updated_system = groups.System(..model.system, model: new_dnd)

      Model(system: updated_system, items: new_items)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.section(
    [
      attribute.style("display", "flex"),
      attribute.style("align-items", "top"),
      attribute.style("justify-content", "center"),
      attribute.style("align-items", "flex-start"),
      attribute.style("padding-top", "2rem"),
      attribute.style("height", "41rem"),
      attribute.style("user-select", "none"),
      attribute.style("-webkit-user-select", "none"),
      // Global mouse events for dragging
      case model.system.info(model.system.model) {
        Some(_) -> {
          event.on("mousemove", {
            use client_x <- decode.field("clientX", decode.float)
            use client_y <- decode.field("clientY", decode.float)
            decode.success(
              DndMsg(groups.Drag(groups.Position(client_x, client_y))),
            )
          })
        }
        None -> attribute.none()
      },
      case model.system.info(model.system.model) {
        Some(_) -> event.on("mouseup", decode.success(DndMsg(groups.DragEnd)))
        None -> attribute.none()
      },
    ],
    [
      group_view(model, Left, light_red()),
      group_view(model, Right, light_blue()),
      ghost_view(model.system, model.system.model, model.items),
    ],
  )
}

fn group_view(model: Model, group: Group, color: String) -> Element(Msg) {
  let group_items = list.filter(model.items, fn(item) { item.group == group })
  let offset = calculate_offset(0, group, model.items)

  html.div(
    [
      attribute.style("display", "flex"),
      attribute.style("flex-direction", "column"),
      attribute.style("background-color", color),
      attribute.style("padding-top", "2rem"),
      attribute.style("min-height", "19rem"),
    ],
    list.index_map(group_items, fn(item, local_index) {
      item_view(model, offset, local_index, item)
    }),
  )
}

fn item_view(
  model: Model,
  offset: Int,
  local_index: Int,
  item: Item,
) -> Element(Msg) {
  let global_index = offset + local_index
  let item_id = "id-" <> int.to_string(global_index)

  case
    model.system.info(model.system.model),
    maybe_drag_item(model.system, model.system.model, model.items)
  {
    Some(info), Some(drag_item) -> {
      case
        item.color == transparent()
        && item.value == "footer"
        && drag_item.group != item.group
      {
        // Footer that can accept drops from different groups
        True -> {
          html.div(
            [
              attribute.id(item_id),
              attribute.style("flex-grow", "1"),
              attribute.style("height", "auto"),
              attribute.style("min-height", "1rem"),
              attribute.style("width", "8rem"),
              attribute.style("user-select", "none"),
              attribute.style("-webkit-user-select", "none"),
              ..model.system.drop_events(global_index, item_id)
            ],
            [],
          )
        }
        False -> {
          case
            item.color == transparent()
            && item.value == "footer"
            && drag_item.group == item.group
          {
            // Footer from same group - no drop events
            True -> {
              html.div(
                [
                  attribute.id(item_id),
                  attribute.style("flex-grow", "1"),
                  attribute.style("height", "auto"),
                  attribute.style("min-height", "1rem"),
                  attribute.style("width", "8rem"),
                  attribute.style("user-select", "none"),
                  attribute.style("-webkit-user-select", "none"),
                ],
                [],
              )
            }
            False -> {
              case info.drag_index != global_index {
                // Regular item that can accept drops
                True -> {
                  html.div(
                    [
                      attribute.id(item_id),
                      ..list.append(item_styles(item.color), [
                        attribute.style("user-select", "none"),
                        attribute.style("-webkit-user-select", "none"),
                        ..model.system.drop_events(global_index, item_id)
                      ])
                    ],
                    [html.text(item.value)],
                  )
                }
                // Currently dragged item - show placeholder
                False -> {
                  html.div(
                    [
                      attribute.id(item_id),
                      ..list.append(item_styles(gray()), [
                        attribute.style("user-select", "none"),
                        attribute.style("-webkit-user-select", "none"),
                      ])
                    ],
                    [],
                  )
                }
              }
            }
          }
        }
      }
    }
    _, _ -> {
      // No dragging - normal view
      case item.color == transparent() && item.value == "footer" {
        True -> {
          html.div(
            [
              attribute.id(item_id),
              attribute.style("flex-grow", "1"),
              attribute.style("height", "auto"),
              attribute.style("min-height", "1rem"),
              attribute.style("width", "8rem"),
              attribute.style("user-select", "none"),
              attribute.style("-webkit-user-select", "none"),
            ],
            [],
          )
        }
        False -> {
          html.div(
            [
              attribute.id(item_id),
              ..list.append(item_styles(item.color), [
                attribute.style("user-select", "none"),
                attribute.style("-webkit-user-select", "none"),
                ..model.system.drag_events(global_index, item_id)
              ])
            ],
            [html.text(item.value)],
          )
        }
      }
    }
  }
}

fn ghost_view(
  system: groups.System(Item, Msg),
  dnd_model: groups.Model,
  items: List(Item),
) -> Element(Msg) {
  case maybe_drag_item(system, dnd_model, items) {
    Some(item) -> {
      html.div(
        list.append(
          system.ghost_styles(dnd_model),
          list.append(item_styles(item.color), [
            // Additional ghost styling
            attribute.style("color", "#ffffff"),
          ]),
        ),
        [html.text(item.value)],
      )
    }
    None -> html.text("")
  }
}

// HELPER FUNCTIONS ------------------------------------------------------------

fn calculate_offset(index: Int, group: Group, items: List(Item)) -> Int {
  case items {
    [] -> 0
    [first, ..rest] -> {
      case first.group == group {
        True -> index
        False -> calculate_offset(index + 1, group, rest)
      }
    }
  }
}

fn maybe_drag_item(
  system: groups.System(Item, Msg),
  dnd_model: groups.Model,
  items: List(Item),
) -> option.Option(Item) {
  case system.info(dnd_model) {
    Some(info) -> {
      case items |> list.drop(info.drag_index) |> list.first() {
        Ok(item) -> Some(item)
        Error(_) -> None
      }
    }
    None -> None
  }
}

// COLORS ----------------------------------------------------------------------

fn red() -> String {
  "#dc2626"
}

fn blue() -> String {
  "#2563eb"
}

fn light_red() -> String {
  "#fecaca"
}

fn light_blue() -> String {
  "#bfdbfe"
}

fn gray() -> String {
  "#6b7280"
}

fn transparent() -> String {
  "transparent"
}

// STYLES ----------------------------------------------------------------------

fn item_styles(color: String) -> List(attribute.Attribute(msg)) {
  [
    attribute.style("width", "5rem"),
    attribute.style("height", "5rem"),
    attribute.style("background-color", color),
    attribute.style("border-radius", "8px"),
    attribute.style("color", "#ffffff"),
    attribute.style("cursor", "pointer"),
    attribute.style("margin", "0 auto 1rem auto"),
    attribute.style("display", "flex"),
    attribute.style("align-items", "center"),
    attribute.style("justify-content", "center"),
    attribute.style("font-weight", "bold"),
    attribute.style("font-size", "1.25rem"),
  ]
}
