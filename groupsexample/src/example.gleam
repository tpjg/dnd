import dnd/groups
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
  let app = lustre.application(init, update, view)
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

fn init(_flags) -> #(Model, Effect(Msg)) {
  let config =
    groups.Config(
      before_update: fn(_, _, list) { list },
      movement: groups.Free,
      listen: groups.OnDrag,
      operation: groups.Rotate,
      groups: groups.GroupsConfig(
        listen: groups.OnDrag,
        operation: groups.InsertBefore,
        comparator: comparator,
        setter: setter,
      ),
      // Enable Auto mode for both mouse and touch support
      mode: groups.Auto,
      // Auto-cancel touch selection after 5 seconds
      touch_timeout_ms: 5000,
    )

  let system = groups.create(config, DndMsg)
  let initial_items = prepared_data()

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

      let updated_system = groups.System(..model.system, model: new_dnd)

      #(Model(system: updated_system, items: new_items), dnd_effect)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let system = model.system
  let dnd_model = system.model
  let is_selecting = system.is_touch_selecting(dnd_model)

  html.section(
    list.flatten([
      [
        attribute.style("display", "flex"),
        attribute.style("align-items", "top"),
        attribute.style("justify-content", "center"),
        attribute.style("align-items", "flex-start"),
        attribute.style("padding-top", "2rem"),
        attribute.style("height", "41rem"),
        attribute.style("user-select", "none"),
        attribute.style("-webkit-user-select", "none"),
      ],
      // Global mouse events for dragging
      case system.info(dnd_model) {
        Some(_) -> [
          event.on("mousemove", {
            use client_x <- decode.field("clientX", decode.float)
            use client_y <- decode.field("clientY", decode.float)
            decode.success(
              DndMsg(groups.Drag(groups.Position(client_x, client_y))),
            )
          }),
          event.on("mouseup", decode.success(DndMsg(groups.DragEnd))),
          event.on("mouseleave", decode.success(DndMsg(groups.DragEnd))),
        ]
        None -> []
      },
      // Touch cancel events
      system.cancel_events(),
    ]),
    [
      // Touch mode indicator
      case is_selecting {
        True ->
          html.div(
            [
              attribute.style("position", "fixed"),
              attribute.style("top", "0.5rem"),
              attribute.style("left", "50%"),
              attribute.style("transform", "translateX(-50%)"),
              attribute.style("padding", "0.5rem 1rem"),
              attribute.style("background-color", "#dbeafe"),
              attribute.style("border", "1px solid #93c5fd"),
              attribute.style("border-radius", "0.5rem"),
              attribute.style("color", "#1d4ed8"),
              attribute.style("font-size", "0.875rem"),
              attribute.style("z-index", "100"),
            ],
            [html.text("Touch mode: tap a drop zone")],
          )
        False -> html.text("")
      },
      group_view(model, Left, light_red()),
      group_view(model, Right, light_blue()),
      ghost_view(model.system, model.system.model, model.items),
    ],
  )
}

fn group_view(model: Model, group: Group, color: String) -> Element(Msg) {
  let system = model.system
  let dnd_model = system.model
  let is_selecting = system.is_touch_selecting(dnd_model)
  let selected_index = system.selected_index(dnd_model)

  let group_items = list.filter(model.items, fn(item) { item.group == group })
  let offset = calculate_offset(0, group, model.items)

  // Get selected item's group if selecting
  let selected_group = case selected_index {
    Some(idx) ->
      case list.drop(model.items, idx) |> list.first() {
        Ok(item) -> Some(item.group)
        Error(_) -> None
      }
    None -> None
  }

  html.div(
    [
      attribute.style("display", "flex"),
      attribute.style("flex-direction", "column"),
      attribute.style("background-color", color),
      attribute.style("padding-top", "2rem"),
      attribute.style("min-height", "19rem"),
    ],
    render_group_items_with_drop_zones(
      model,
      group,
      group_items,
      offset,
      is_selecting,
      selected_group,
    ),
  )
}

fn render_group_items_with_drop_zones(
  model: Model,
  group: Group,
  group_items: List(Item),
  offset: Int,
  is_selecting: Bool,
  selected_group: option.Option(Group),
) -> List(Element(Msg)) {
  let system = model.system
  let selected_idx = system.selected_index(system.model)

  // Show drop zones in all groups when selecting (for both same-group reorder
  // and cross-group transfer)
  let show_drop_zones = is_selecting

  let items_with_zones =
    list.index_map(group_items, fn(item, local_index) {
      let global_index = offset + local_index
      let item_el = item_view(model, offset, local_index, item)

      // Don't show drop zone right before or at the selected item (no-op positions)
      let is_adjacent_to_selected = case selected_idx {
        Some(sel_idx) -> global_index == sel_idx || global_index == sel_idx + 1
        None -> False
      }

      case show_drop_zones, item.value != "footer", is_adjacent_to_selected {
        True, True, False -> [
          touch_drop_zone_view(system, global_index, group, selected_group),
          item_el,
        ]
        _, _, _ -> [item_el]
      }
    })
    |> list.flatten

  // Add final drop zone after last non-footer item
  case show_drop_zones, selected_idx {
    True, Some(sel_idx) -> {
      let footer_index = offset + list.length(group_items) - 1
      // Don't show if selected item is at the end of this group
      case footer_index != sel_idx && footer_index != sel_idx + 1 {
        True ->
          list.append(items_with_zones, [
            touch_drop_zone_view(system, footer_index, group, selected_group),
          ])
        False -> items_with_zones
      }
    }
    True, None -> {
      let footer_index = offset + list.length(group_items) - 1
      list.append(items_with_zones, [
        touch_drop_zone_view(system, footer_index, group, selected_group),
      ])
    }
    False, _ -> items_with_zones
  }
}

fn touch_drop_zone_view(
  system: groups.System(Item, Msg),
  index: Int,
  current_group: Group,
  selected_group: option.Option(Group),
) -> Element(Msg) {
  // Use different colors for same-group vs cross-group drop zones
  let is_cross_group = case selected_group {
    Some(sel_group) -> sel_group != current_group
    None -> False
  }

  let #(border_color, bg_color, text_color) = case is_cross_group {
    // Orange for cross-group
    True -> #("#f97316", "rgba(255, 237, 213, 0.5)", "#ea580c")
    // Blue for same-group
    False -> #("#93c5fd", "rgba(219, 234, 254, 0.5)", "#60a5fa")
  }

  html.div(
    list.flatten([
      [
        attribute.style("height", "2.5rem"),
        attribute.style("margin", "0.25rem 0.5rem"),
        attribute.style("border", "2px dashed " <> border_color),
        attribute.style("border-radius", "0.5rem"),
        attribute.style("display", "flex"),
        attribute.style("align-items", "center"),
        attribute.style("justify-content", "center"),
        attribute.style("color", text_color),
        attribute.style("font-size", "0.75rem"),
        attribute.style("cursor", "pointer"),
        attribute.style("background-color", bg_color),
      ],
      system.touch_drop_zone_events(index),
    ]),
    [
      html.text(case is_cross_group {
        True -> "Move here"
        False -> "Reorder"
      }),
    ],
  )
}

fn item_view(
  model: Model,
  offset: Int,
  local_index: Int,
  item: Item,
) -> Element(Msg) {
  let system = model.system
  let dnd_model = system.model
  let global_index = offset + local_index
  let item_id = "id-" <> int.to_string(global_index)
  let is_selecting = system.is_touch_selecting(dnd_model)
  let selected_index = system.selected_index(dnd_model)

  // Check if this item is currently selected (touch mode)
  let is_selected = case selected_index {
    Some(i) -> i == global_index
    None -> False
  }

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
      // No dragging - normal view with touch support
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
          let base_styles = item_styles(item.color)
          let selected_styles = case is_selected {
            True -> [
              attribute.style("outline", "3px solid #3b82f6"),
              attribute.style("outline-offset", "2px"),
            ]
            False -> []
          }

          html.div(
            list.flatten([
              [attribute.id(item_id)],
              base_styles,
              selected_styles,
              [
                attribute.style("user-select", "none"),
                attribute.style("-webkit-user-select", "none"),
              ],
              // Mouse drag events (ignored during touch selection)
              case is_selecting {
                True -> []
                False -> model.system.drag_events(global_index, item_id)
              },
              // Touch grip events
              model.system.touch_grip_events(global_index, item_id),
            ]),
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
