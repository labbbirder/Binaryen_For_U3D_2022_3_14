;; NOTE: Assertions have been generated by update_lit_checks.py --all-items and should not be edited.
;; RUN: foreach %s %t wasm-opt --nominal --gto -all -S -o - | filecheck %s
;; (remove-unused-names is added to test fallthrough values without a block
;; name getting in the way)

(module
  ;; The struct here has three fields, and the second of them has no struct.set
  ;; which means we can make it immutable.

  ;; CHECK:      (type $struct (struct_subtype (field (mut funcref)) (field funcref) (field (mut funcref)) data))
  (type $struct (struct (field (mut funcref)) (field (mut funcref)) (field (mut funcref))))

  ;; CHECK:      (type $two-params (func_subtype (param (ref $struct) (ref $struct)) func))
  (type $two-params (func (param (ref $struct)) (param (ref $struct))))

  ;; Test that we update tag types properly.
  (table 0 funcref)

  ;; CHECK:      (type $ref|$struct|_=>_none (func_subtype (param (ref $struct)) func))

  ;; CHECK:      (type $none_=>_ref?|$struct| (func_subtype (result (ref null $struct)) func))

  ;; CHECK:      (type $none_=>_none (func_subtype func))

  ;; CHECK:      (table $0 0 funcref)

  ;; CHECK:      (elem declare func $func-two-params)

  ;; CHECK:      (tag $tag (param (ref $struct)))
  (tag $tag (param (ref $struct)))

  ;; CHECK:      (func $func (type $ref|$struct|_=>_none) (param $x (ref $struct))
  ;; CHECK-NEXT:  (local $temp (ref null $struct))
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.new $struct
  ;; CHECK-NEXT:    (ref.null func)
  ;; CHECK-NEXT:    (ref.null func)
  ;; CHECK-NEXT:    (ref.null func)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (struct.set $struct 0
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (ref.null func)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (struct.set $struct 2
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (ref.null func)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (local.set $temp
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $struct 0
  ;; CHECK-NEXT:    (local.get $x)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $struct 1
  ;; CHECK-NEXT:    (local.get $x)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func (param $x (ref $struct))
    (local $temp (ref null $struct))
    ;; The presence of a struct.new does not prevent this optimization: we just
    ;; care about writes using struct.set.
    (drop
      (struct.new $struct
        (ref.null func)
        (ref.null func)
        (ref.null func)
      )
    )
    (struct.set $struct 0
      (local.get $x)
      (ref.null func)
    )
    (struct.set $struct 2
      (local.get $x)
      (ref.null func)
    )
    ;; Test that local types remain valid after our work (otherwise, we'd get a
    ;; validation error).
    (local.set $temp
      (local.get $x)
    )
    ;; Test that struct.get types remain valid after our work.
    (drop
      (struct.get $struct 0
        (local.get $x)
      )
    )
    (drop
      (struct.get $struct 1
        (local.get $x)
      )
    )
  )

  ;; CHECK:      (func $foo (type $none_=>_ref?|$struct|) (result (ref null $struct))
  ;; CHECK-NEXT:  (try $try
  ;; CHECK-NEXT:   (do
  ;; CHECK-NEXT:    (nop)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:   (catch $tag
  ;; CHECK-NEXT:    (return
  ;; CHECK-NEXT:     (pop (ref $struct))
  ;; CHECK-NEXT:    )
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (ref.null $struct)
  ;; CHECK-NEXT: )
  (func $foo (result (ref null $struct))
    ;; Use a tag so that we test proper updating of its type after making
    ;; changes.
    (try
      (do
        (nop)
      )
      (catch $tag
        (return
          (pop (ref $struct))
        )
      )
    )
    (ref.null $struct)
  )

  ;; CHECK:      (func $func-two-params (type $two-params) (param $x (ref $struct)) (param $y (ref $struct))
  ;; CHECK-NEXT:  (local $z (ref null $two-params))
  ;; CHECK-NEXT:  (local.set $z
  ;; CHECK-NEXT:   (ref.func $func-two-params)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (call_indirect $0 (type $two-params)
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (local.get $y)
  ;; CHECK-NEXT:   (i32.const 0)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func-two-params (param $x (ref $struct)) (param $y (ref $struct))
    ;; This function has two params, which means a tuple type is used for its
    ;; signature, which we must also update. To verify the update is correct,
    ;; assign it to a local.
    (local $z (ref null $two-params))
    (local.set $z
      (ref.func $func-two-params)
    )
    ;; Also check that a call_indirect still validates after the rewriting.
    (call_indirect (type $two-params)
     (local.get $x)
     (local.get $y)
     (i32.const 0)
    )
  )

  ;; CHECK:      (func $field-keepalive (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $struct 2
  ;; CHECK-NEXT:    (ref.null $struct)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $field-keepalive
    ;; --gto will remove fields that are not read from, so add reads to any
    ;; that don't already have them.
    (drop (struct.get $struct 2 (ref.null $struct)))
  )
)

(module
  ;; Test recursion between structs where we only modify one. Specifically $B
  ;; has no writes to either of its fields.

  ;; CHECK:      (type $A (struct_subtype (field (mut (ref null $B))) (field (mut i32)) data))
  (type $A (struct (field (mut (ref null $B))) (field (mut i32)) ))
  ;; CHECK:      (type $B (struct_subtype (field (ref null $A)) (field f64) data))
  (type $B (struct (field (mut (ref null $A))) (field (mut f64)) ))

  ;; CHECK:      (type $ref|$A|_=>_none (func_subtype (param (ref $A)) func))

  ;; CHECK:      (type $none_=>_none (func_subtype func))

  ;; CHECK:      (func $func (type $ref|$A|_=>_none) (param $x (ref $A))
  ;; CHECK-NEXT:  (struct.set $A 0
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (ref.null $B)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (struct.set $A 1
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (i32.const 20)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func (param $x (ref $A))
    (struct.set $A 0
      (local.get $x)
      (ref.null $B)
    )
    (struct.set $A 1
      (local.get $x)
      (i32.const 20)
    )
  )

  ;; CHECK:      (func $field-keepalive (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $A 0
  ;; CHECK-NEXT:    (ref.null $A)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $A 1
  ;; CHECK-NEXT:    (ref.null $A)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $B 0
  ;; CHECK-NEXT:    (ref.null $B)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $B 1
  ;; CHECK-NEXT:    (ref.null $B)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $field-keepalive
    (drop (struct.get $A 0 (ref.null $A)))
    (drop (struct.get $A 1 (ref.null $A)))
    (drop (struct.get $B 0 (ref.null $B)))
    (drop (struct.get $B 1 (ref.null $B)))
  )
)

(module
  ;; As before, but flipped so that $A's fields can become immutable.

  ;; CHECK:      (type $B (struct_subtype (field (mut (ref null $A))) (field (mut f64)) data))
  (type $B (struct (field (mut (ref null $A))) (field (mut f64)) ))

  ;; CHECK:      (type $A (struct_subtype (field (ref null $B)) (field i32) data))
  (type $A (struct (field (mut (ref null $B))) (field (mut i32)) ))

  ;; CHECK:      (type $ref|$B|_=>_none (func_subtype (param (ref $B)) func))

  ;; CHECK:      (type $none_=>_none (func_subtype func))

  ;; CHECK:      (func $func (type $ref|$B|_=>_none) (param $x (ref $B))
  ;; CHECK-NEXT:  (struct.set $B 0
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (ref.null $A)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (struct.set $B 1
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (f64.const 3.14159)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func (param $x (ref $B))
    (struct.set $B 0
      (local.get $x)
      (ref.null $A)
    )
    (struct.set $B 1
      (local.get $x)
      (f64.const 3.14159)
    )
  )

  ;; CHECK:      (func $field-keepalive (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $A 0
  ;; CHECK-NEXT:    (ref.null $A)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $A 1
  ;; CHECK-NEXT:    (ref.null $A)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $B 0
  ;; CHECK-NEXT:    (ref.null $B)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $B 1
  ;; CHECK-NEXT:    (ref.null $B)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $field-keepalive
    (drop (struct.get $A 0 (ref.null $A)))
    (drop (struct.get $A 1 (ref.null $A)))
    (drop (struct.get $B 0 (ref.null $B)))
    (drop (struct.get $B 1 (ref.null $B)))
  )
)

(module
  ;; As before, but now one field in each can become immutable.

  ;; CHECK:      (type $B (struct_subtype (field (ref null $A)) (field (mut f64)) data))
  (type $B (struct (field (mut (ref null $A))) (field (mut f64)) ))

  ;; CHECK:      (type $A (struct_subtype (field (mut (ref null $B))) (field i32) data))
  (type $A (struct (field (mut (ref null $B))) (field (mut i32)) ))

  ;; CHECK:      (type $ref|$A|_ref|$B|_=>_none (func_subtype (param (ref $A) (ref $B)) func))

  ;; CHECK:      (type $none_=>_none (func_subtype func))

  ;; CHECK:      (func $func (type $ref|$A|_ref|$B|_=>_none) (param $x (ref $A)) (param $y (ref $B))
  ;; CHECK-NEXT:  (struct.set $A 0
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (ref.null $B)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (struct.set $B 1
  ;; CHECK-NEXT:   (local.get $y)
  ;; CHECK-NEXT:   (f64.const 3.14159)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func (param $x (ref $A)) (param $y (ref $B))
    (struct.set $A 0
      (local.get $x)
      (ref.null $B)
    )
    (struct.set $B 1
      (local.get $y)
      (f64.const 3.14159)
    )
  )

  ;; CHECK:      (func $field-keepalive (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $A 0
  ;; CHECK-NEXT:    (ref.null $A)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $A 1
  ;; CHECK-NEXT:    (ref.null $A)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $B 0
  ;; CHECK-NEXT:    (ref.null $B)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $B 1
  ;; CHECK-NEXT:    (ref.null $B)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $field-keepalive
    (drop (struct.get $A 0 (ref.null $A)))
    (drop (struct.get $A 1 (ref.null $A)))
    (drop (struct.get $B 0 (ref.null $B)))
    (drop (struct.get $B 1 (ref.null $B)))
  )
)

(module
  ;; Field #0 is already immutable.
  ;; Field #1 is mutable and can become so.
  ;; Field #2 is mutable and must remain so.

  ;; CHECK:      (type $struct (struct_subtype (field i32) (field i32) (field (mut i32)) data))
  (type $struct (struct (field i32) (field (mut i32)) (field (mut i32))))

  ;; CHECK:      (type $ref|$struct|_=>_none (func_subtype (param (ref $struct)) func))

  ;; CHECK:      (type $none_=>_none (func_subtype func))

  ;; CHECK:      (func $func (type $ref|$struct|_=>_none) (param $x (ref $struct))
  ;; CHECK-NEXT:  (struct.set $struct 2
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (i32.const 1)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func (param $x (ref $struct))
    (struct.set $struct 2
      (local.get $x)
      (i32.const 1)
    )
  )

  ;; CHECK:      (func $field-keepalive (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $struct 0
  ;; CHECK-NEXT:    (ref.null $struct)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $struct 1
  ;; CHECK-NEXT:    (ref.null $struct)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $struct 2
  ;; CHECK-NEXT:    (ref.null $struct)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $field-keepalive
    (drop (struct.get $struct 0 (ref.null $struct)))
    (drop (struct.get $struct 1 (ref.null $struct)))
    (drop (struct.get $struct 2 (ref.null $struct)))
  )
)

(module
  ;; Subtyping. Without a write in either supertype or subtype, we can
  ;; optimize the field to be immutable.

  ;; CHECK:      (type $super (struct_subtype (field i32) data))
  (type $super (struct (field (mut i32))))
  ;; CHECK:      (type $sub (struct_subtype (field i32) $super))
  (type $sub (struct_subtype (field (mut i32)) $super))

  ;; CHECK:      (type $none_=>_none (func_subtype func))

  ;; CHECK:      (func $func (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.new $super
  ;; CHECK-NEXT:    (i32.const 1)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.new $sub
  ;; CHECK-NEXT:    (i32.const 1)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func
    ;; The presence of struct.new do not prevent us optimizing
    (drop
      (struct.new $super
        (i32.const 1)
      )
    )
    (drop
      (struct.new $sub
        (i32.const 1)
      )
    )
  )

  ;; CHECK:      (func $field-keepalive (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $super 0
  ;; CHECK-NEXT:    (ref.null $super)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $sub 0
  ;; CHECK-NEXT:    (ref.null $sub)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $field-keepalive
    (drop (struct.get $super 0 (ref.null $super)))
    (drop (struct.get $sub 0 (ref.null $sub)))
  )
)

(module
  ;; As above, but add a write in the super, which prevents optimization.

  ;; CHECK:      (type $super (struct_subtype (field (mut i32)) data))
  (type $super (struct (field (mut i32))))
  ;; CHECK:      (type $sub (struct_subtype (field (mut i32)) $super))
  (type $sub (struct_subtype (field (mut i32)) $super))

  ;; CHECK:      (type $ref|$super|_=>_none (func_subtype (param (ref $super)) func))

  ;; CHECK:      (type $none_=>_none (func_subtype func))

  ;; CHECK:      (func $func (type $ref|$super|_=>_none) (param $x (ref $super))
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.new $super
  ;; CHECK-NEXT:    (i32.const 1)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.new $sub
  ;; CHECK-NEXT:    (i32.const 1)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (struct.set $super 0
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (i32.const 2)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func (param $x (ref $super))
    ;; The presence of struct.new do not prevent us optimizing
    (drop
      (struct.new $super
        (i32.const 1)
      )
    )
    (drop
      (struct.new $sub
        (i32.const 1)
      )
    )
    (struct.set $super 0
      (local.get $x)
      (i32.const 2)
    )
  )

  ;; CHECK:      (func $field-keepalive (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $super 0
  ;; CHECK-NEXT:    (ref.null $super)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $sub 0
  ;; CHECK-NEXT:    (ref.null $sub)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $field-keepalive
    (drop (struct.get $super 0 (ref.null $super)))
    (drop (struct.get $sub 0 (ref.null $sub)))
  )
)

(module
  ;; As above, but add a write in the sub, which prevents optimization.


  ;; CHECK:      (type $sub (struct_subtype (field (mut i32)) $super))

  ;; CHECK:      (type $super (struct_subtype (field (mut i32)) data))
  (type $super (struct (field (mut i32))))
  (type $sub (struct_subtype (field (mut i32)) $super))

  ;; CHECK:      (type $ref|$sub|_=>_none (func_subtype (param (ref $sub)) func))

  ;; CHECK:      (type $none_=>_none (func_subtype func))

  ;; CHECK:      (func $func (type $ref|$sub|_=>_none) (param $x (ref $sub))
  ;; CHECK-NEXT:  (struct.set $sub 0
  ;; CHECK-NEXT:   (local.get $x)
  ;; CHECK-NEXT:   (i32.const 2)
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $func (param $x (ref $sub))
    (struct.set $sub 0
      (local.get $x)
      (i32.const 2)
    )
  )

  ;; CHECK:      (func $field-keepalive (type $none_=>_none)
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $super 0
  ;; CHECK-NEXT:    (ref.null $super)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT:  (drop
  ;; CHECK-NEXT:   (struct.get $sub 0
  ;; CHECK-NEXT:    (ref.null $sub)
  ;; CHECK-NEXT:   )
  ;; CHECK-NEXT:  )
  ;; CHECK-NEXT: )
  (func $field-keepalive
    (drop (struct.get $super 0 (ref.null $super)))
    (drop (struct.get $sub 0 (ref.null $sub)))
  )
)
