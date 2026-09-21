///|
// Explicit trait-method promotion declarations. The `Color` and `Model` trait
// methods are used as direct methods on the concrete color types (e.g.
// `c.rgba()`, `c.model()`), and the standard traits are promoted as described
// in the package-level `extends.mbt`. `impl Show for &Color` and
// `impl Eq for &Color` promote onto the `&Color` trait-object type itself.

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend &Color with Show::{output}

///|
pub extend &Color with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend &Color with Eq::{not_equal}

///|
pub extend RGBA with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend RGBA with Eq::{not_equal}

///|
pub extend RGBA with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend RGBA with Show::{output}

///|
pub extend RGBA with Color::{model, raw, rgba}

///|
pub extend RGBA64 with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend RGBA64 with Eq::{not_equal}

///|
pub extend RGBA64 with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend RGBA64 with Show::{output}

///|
pub extend RGBA64 with Color::{model, raw, rgba}

///|
pub extend NRGBA with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NRGBA with Eq::{not_equal}

///|
pub extend NRGBA with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend NRGBA with Show::{output}

///|
pub extend NRGBA with Color::{model, raw, rgba}

///|
pub extend NRGBA64 with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NRGBA64 with Eq::{not_equal}

///|
pub extend NRGBA64 with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend NRGBA64 with Show::{output}

///|
pub extend NRGBA64 with Color::{model, raw, rgba}

///|
pub extend Alpha with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Alpha with Eq::{not_equal}

///|
pub extend Alpha with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend Alpha with Show::{output}

///|
pub extend Alpha with Color::{model, raw, rgba}

///|
pub extend Alpha16 with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Alpha16 with Eq::{not_equal}

///|
pub extend Alpha16 with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend Alpha16 with Show::{output}

///|
pub extend Alpha16 with Color::{model, raw, rgba}

///|
pub extend Gray with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Gray with Eq::{not_equal}

///|
pub extend Gray with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend Gray with Show::{output}

///|
pub extend Gray with Color::{model, raw, rgba}

///|
pub extend Gray16 with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Gray16 with Eq::{not_equal}

///|
pub extend Gray16 with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend Gray16 with Show::{output}

///|
pub extend Gray16 with Color::{model, raw, rgba}

///|
pub extend ModelFunc with Model::{name, convert, get_palette}

///|
pub extend Palette with Model::{name, convert, get_palette}

///|
pub extend YCbCr with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend YCbCr with Eq::{not_equal}

///|
pub extend YCbCr with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend YCbCr with Show::{output}

///|
pub extend YCbCr with Color::{model, raw, rgba}

///|
pub extend NYCbCrA with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NYCbCrA with Eq::{not_equal}

///|
pub extend NYCbCrA with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend NYCbCrA with Show::{output}

///|
pub extend NYCbCrA with Color::{model, raw, rgba}

///|
pub extend CMYK with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend CMYK with Eq::{not_equal}

///|
pub extend CMYK with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend CMYK with Show::{output}

///|
pub extend CMYK with Color::{model, raw, rgba}
