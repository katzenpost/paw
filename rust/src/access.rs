// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! The accessibility tree Lean sends, as an AccessKit update. Bounds are in physical pixels of the
//! window. A password field's value never arrives from Lean, so it cannot be passed on.

use crate::events::AccessNode;
use crate::render::UNITS;
use accesskit::{Action, Node, NodeId, Rect, Role, Toggled, Tree, TreeUpdate};

fn role(r: u64) -> Role {
    match r {
        0 => Role::Label,
        1 => Role::Button,
        2 => Role::CheckBox,
        3 => Role::TextInput,
        4 => Role::PasswordInput,
        5 => Role::ScrollView,
        6 => Role::Window,
        7 => Role::Dialog,
        8 => Role::Image,
        _ => Role::GenericContainer,
    }
}

/// The update for `nodes`, the first of which is the window, at `scale` physical pixels per
/// logical pixel. `title` names the window when Lean gives it no name.
pub fn update(focus: u64, nodes: &[AccessNode], scale: f64, title: &str) -> TreeUpdate {
    let px = |u: i64| u as f64 / UNITS as f64 * scale;
    let built = nodes
        .iter()
        .map(|n| {
            let mut node = Node::new(role(n.role));
            let name = if n.name.is_empty() && n.role == 6 { title } else { &n.name };
            // AccessKit reads a label's text from its value; other roles are named by their label.
            if n.role == 0 {
                node.set_value(name);
            } else if !name.is_empty() {
                node.set_label(name);
            }
            if let Some(v) = &n.value {
                if n.role != 4 {
                    node.set_value(v.as_str());
                }
            }
            match n.checked {
                1 => node.set_toggled(Toggled::False),
                2 => node.set_toggled(Toggled::True),
                _ => {}
            }
            node.set_bounds(Rect { x0: px(n.bounds.x0), y0: px(n.bounds.y0), x1: px(n.bounds.x1), y1: px(n.bounds.y1) });
            node.set_children(n.children.iter().map(|c| NodeId(*c)).collect::<Vec<_>>());
            if n.focusable {
                node.add_action(Action::Focus);
            }
            if matches!(n.role, 1 | 2) {
                node.add_action(Action::Click);
            }
            if n.disabled {
                node.set_disabled();
            }
            // Paw's only dialogs are modal: nothing beneath one can be reached while it is open.
            if n.role == 7 {
                node.set_modal();
            }
            (NodeId(n.id), node)
        })
        .collect();
    let root = nodes.first().map(|n| n.id).unwrap_or(0);
    let focus = if nodes.iter().any(|n| n.id == focus) { focus } else { root };
    TreeUpdate { nodes: built, tree: Some(Tree::new(NodeId(root))), focus: NodeId(focus) }
}

/// An update with only the window, for when assistive technology asks before Lean has sent one.
pub fn empty(title: &str) -> TreeUpdate {
    let window = AccessNode {
        id: 0,
        role: 6,
        name: String::new(),
        value: None,
        checked: 0,
        focusable: false,
        disabled: false,
        bounds: crate::scene::Rect { x0: 0, y0: 0, x1: 0, y1: 0 },
        children: vec![],
    };
    update(0, &[window], 1.0, title)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn node(id: u64, role: u64, name: &str, value: Option<&str>, children: Vec<u64>) -> AccessNode {
        AccessNode {
            id,
            role,
            name: name.into(),
            value: value.map(Into::into),
            checked: 0,
            focusable: role != 6,
            disabled: false,
            bounds: crate::scene::Rect { x0: 0, y0: 0, x1: 6400, y1: 1280 },
            children,
        }
    }

    #[test]
    fn builds_an_update() {
        let nodes = vec![
            node(0, 6, "", None, vec![2, 3, 4]),
            node(2, 1, "Go", None, vec![]),
            node(3, 3, "name", Some("Ada"), vec![]),
            node(4, 4, "", Some("secret"), vec![]),
        ];
        let u = update(3, &nodes, 2.0, "Paw gallery");
        assert_eq!(u.nodes.len(), 4);
        assert_eq!(u.focus, NodeId(3));
        assert_eq!(u.tree.as_ref().map(|t| t.root), Some(NodeId(0)));
        let find = |id: u64| &u.nodes.iter().find(|(n, _)| *n == NodeId(id)).unwrap().1;
        assert_eq!(find(0).label(), Some("Paw gallery"));
        assert_eq!(find(2).role(), Role::Button);
        assert!(find(2).supports_action(Action::Click));
        assert_eq!(find(3).value(), Some("Ada"));
        assert_eq!(find(4).value(), None, "a password's value is never passed on");
        assert_eq!(find(2).bounds().map(|b| b.x1), Some(200.0));
        assert_eq!(find(0).children(), &[NodeId(2), NodeId(3), NodeId(4)]);
        let label = update(0, &[node(0, 6, "", None, vec![5]), node(5, 0, "count: 1", None, vec![])], 1.0, "t");
        let l = &label.nodes.iter().find(|(n, _)| *n == NodeId(5)).unwrap().1;
        assert_eq!(l.value(), Some("count: 1"), "a label's text is its value");
        let dlg = update(0, &[node(0, 6, "", None, vec![6]), node(6, 7, "Clear the list?", None, vec![])], 1.0, "t");
        let d = &dlg.nodes.iter().find(|(n, _)| *n == NodeId(6)).unwrap().1;
        assert_eq!(d.role(), Role::Dialog);
        assert!(d.is_modal(), "a dialog is modal");
        assert_eq!(d.label(), Some("Clear the list?"));
    }

    #[test]
    fn unknown_focus_falls_back_to_the_window() {
        assert_eq!(update(99, &[node(0, 6, "", None, vec![])], 1.0, "t").focus, NodeId(0));
        assert_eq!(empty("t").nodes.len(), 1);
    }
}
