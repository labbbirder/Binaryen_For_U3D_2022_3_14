;; NOTE: Assertions have been generated by update_lit_checks.py and should not be edited.
;; RUN: wasm-opt %s -all --nominal -S -o - | filecheck %s
;; RUN: wasm-opt %s -all --nominal --roundtrip -S -o - | filecheck %s

;; Check that intermediate types in subtype chains are also included in the
;; output module, even if there are no other references to those intermediate
;; types.

(module
  ;; CHECK:      (type $leaf (struct_subtype (field i32) (field i64) (field f32) (field f64) $twig))
  (type $leaf (struct_subtype i32 i64 f32 f64 $twig))

  ;; CHECK:      (type $root (struct_subtype  data))

  ;; CHECK:      (type $twig (struct_subtype (field i32) (field i64) (field f32) $branch))
  (type $twig (struct_subtype i32 i64 f32 $branch))

  ;; CHECK:      (type $branch (struct_subtype (field i32) (field i64) $trunk))
  (type $branch (struct_subtype i32 i64 $trunk))

  ;; CHECK:      (type $trunk (struct_subtype (field i32) $root))
  (type $trunk (struct_subtype i32 $root))

  (type $root (struct))

  ;; CHECK:      (func $make-root (type $none_=>_ref?|$root|) (result (ref null $root))
  ;; CHECK-NEXT:  (ref.null $leaf)
  ;; CHECK-NEXT: )
  (func $make-root (result (ref null $root))
    (ref.null $leaf)
  )
)
