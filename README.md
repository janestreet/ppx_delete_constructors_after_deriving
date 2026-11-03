# ppx_delete_constructors_after_deriving

# Overview

`ppx_delete_constructors_after_deriving` erases the constructors of type declarations
annotated with `[@@delete_constructors_after_deriving]` after derivers run.

For example, it changes the declaration in

```ocaml
type 'a t = 'a option = None | Some of 'a
[@@deriving compare] [@@delete_constructors_after_deriving]
```

to just

```ocaml
type 'a t = 'a option
```

More precisely, tagging a type declaration with `[@@delete_constructors_after_deriving]`
makes the ppx replace its type kind with an abstract one. This "deletes" the part of a
declaration that defines variant constructors or record fields, but not the part of the
declaration that indicates the type aliases another. Derivers see the constructors, but
the compiler does not.

# Motivation

This ppx supports changing the parameter kinds of types like `option` to `any`. When we
change the parameter of `option` to `any`, the below becomes an error because a re-export
of a constructor that narrows its kind from `any` is a type error. (Eventually, it won't
be, but this is necessary today for soundness because sometimes the `any` version gets a
"less specialized" representation.)

```ocaml
type nonrec ('a : k) t = 'a option =
  | None
  | Some of 'a
[@@kind k = all_ks_non_value]
[@@deriving compare ~localize]
```

However, we still want to generate templated versions of the type and derivers. Thus, we
want ppx derivers to see the constructors, but we want the compiler to eventually see
just the following for the type declaration (for each instance of `k`).

```ocaml
type nonrec ('a : k) t = 'a option
```

Annotating the declaration with `[@@delete_constructors_after_deriving]` lets derivers
see the constructors of a declaration whose kind the compiler would reject.

# Use with `[%%rederive]`

In practice, uses of this ppx often appear inside
[`[%%rederive]`](../ppx_shorthand/README.md#rederive) (from `ppx_shorthand`).
The declaration annotated with `[@@delete_constructors_after_deriving]` usually exists
only for the sake of the derivers: the type itself is already defined elsewhere, so the
re-export with constructors is wrapped in `[%%rederive]` to avoid redefining it. For
example, `Core.Option` extends the templated option types from `Base` with `bin_io`:

```ocaml
include%template struct
  [@@@kind.default k = all_ks_non_value]

  [%%rederive.portable
    type nonrec ('a : k) t = ('a Constructors.t[@kind k]) =
      | None
      | Some of 'a
    [@@kind k] [@@delete_constructors_after_deriving] [@@deriving bin_io ~localize]]
end
```

Both ppxes are needed here, and they solve different problems:

- `[%%rederive]` keeps the declaration from redefining the existing type: it expands to
  `include (struct ... end : sig ... end with type 'a t := 'a t)`, exporting only the
  derived values.
- The declaration still appears inside the struct that `[%%rederive]` generates, so the
  compiler would still reject its kind-narrowing constructor re-export.
  `[@@delete_constructors_after_deriving]` erases the constructors from that inner
  declaration once the derivers have seen them.

The two compose correctly because `[%%rederive]` is expanded during the driver's
context-free pass, while this ppx runs after context-free preprocessors, so it sees the
annotated declaration produced by `[%%rederive]`'s expansion.
