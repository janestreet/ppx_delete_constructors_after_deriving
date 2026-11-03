open Ppxlib

let name = "delete_constructors_after_deriving"

let attribute =
  Attribute.declare name Attribute.Context.type_declaration Ast_pattern.(pstr nil) ()
;;

let remove_annotated_type_kinds =
  object
    inherit Ast_traverse.map as super

    method! type_declaration td =
      let td = super#type_declaration td in
      match Attribute.consume attribute td with
      | None -> td
      | Some (td, ()) ->
        (match td.ptype_private, td.ptype_manifest with
         | Private, _ ->
           (* Deleting the constructors of a private declaration would leave a private
              abbreviation, which means something different. *)
           Location.raise_errorf
             ~loc:td.ptype_loc
             "[@@@@%s] does not support private declarations"
             name
         | _, None ->
           (* Deleting the constructors of a type with no manifest would leave an abstract
              type, which will not interact with the derived code correctly *)
           Location.raise_errorf
             ~loc:td.ptype_loc
             "[@@@@%s] is only allowed on types that\n\
             \  (a) are declared equal to another type, and\n\
             \  (b) also declare constructors, e.g.:\n\
              [type 'a t = 'a option = None | Some of 'a]"
             name
         | Public, Some _ -> { td with ptype_kind = Ptype_abstract })
  end
;;

(* We register these as whole-file [impl] and [intf] rewrites so that they are guaranteed
   to run after all context-free transformations; this includes [ppx_shorthand]
   ([%%rederive]) and [[@@deriving]]. *)
let () =
  Driver.register_transformation
    ("ppx_" ^ name)
    ~impl:remove_annotated_type_kinds#structure
    ~intf:remove_annotated_type_kinds#signature
;;
