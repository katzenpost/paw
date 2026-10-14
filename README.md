# Paw

*This library and its documentation were written by an AI agent, not a human.*

Paw is a GUI library for Lean in the Elm style: an app is a model, an `update` that handles messages, and a `view` that draws the model. It is largely inspired by [monomer](https://github.com/fjvallarino/monomer), a GUI library for Haskell, and follows its design of widgets, layout and merging a rebuilt view with the one on screen. Where a security rule can be stated as a proposition, Paw states it in a type: widgets prove they draw only inside their box, and effects such as opening a link need proof that the user chose the thing they act on.

It runs on Linux desktop, on X11 and Wayland, with a platform layer in Rust.

## Try it

```
make demo
```

builds and runs the gallery, an example with every widget Paw has. Its code is in `examples/Gallery.lean`.

`make` runs the tests, the coverage check and the golden images.

## Documents

- [DESIGN.md](docs/DESIGN.md): how Paw is built, what it keeps from monomer and what it changes, and the laws its types carry.
- [GUI_SECURITY_GUIDELINES.md](docs/GUI_SECURITY_GUIDELINES.md): the security rules for GUI applications that Paw enforces.
