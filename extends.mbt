///|
// Explicit trait-method promotion declarations. The `Image` trait methods
// below are used as direct methods on the concrete image types (e.g.
// `rgba.at(x, y)`, `rgba.set(x, y, c)`, `rgba.pix_offset(x, y)`). MoonBit now
// requires an explicit `extend` declaration for this promotion instead of
// the deprecated implicit form.

///|
pub extend RGBA with Image::{at, set, pix_offset}

///|
pub extend RGBA64 with Image::{at, set, pix_offset}

///|
pub extend NRGBA with Image::{at, set, pix_offset}

///|
pub extend NRGBA64 with Image::{at, set, pix_offset}

///|
pub extend Alpha with Image::{at, set, pix_offset}

///|
pub extend Alpha16 with Image::{at, set, pix_offset}

///|
pub extend Gray with Image::{at, set, pix_offset}

///|
pub extend Gray16 with Image::{at, set, pix_offset}

///|
pub extend CMYK with Image::{at, pix_offset}

///|
pub extend Paletted with Image::{at, set, pix_offset}

///|
pub extend YCbCr with Image::{pix_offset}
