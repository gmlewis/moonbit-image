///|
// Explicit trait-method promotion declarations.
//
// `Component::default` is promoted because `derive(Default)` promotes it
// implicitly, which is deprecated; the promotion is deprecated and hidden
// because `Default::default()` via the trait, or an explicit struct literal,
// is clearer than a promoted `Component::default()`.

///|
#deprecated("Use `Default::default()` via the trait instead", skip_current_package=true)
#doc(hidden)
pub extend Component with Default::{default}
