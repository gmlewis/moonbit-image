///|
// Explicit trait-method promotion declarations. The `Image` trait methods
// below are used as direct methods on the concrete image types (e.g.
// `rgba.at(x, y)`, `rgba.set(x, y, c)`, `rgba.pix_offset(x, y)`). MoonBit now
// requires an explicit `extend` declaration for this promotion instead of
// the deprecated implicit form.
//
// The standard-trait promotions are the same kind of declaration: the primary
// method of each trait is promoted, and the defaulted derivative that the
// operator or interpolation syntax already covers (`Show::output`,
// `Eq::not_equal`) is promoted as well but deprecated and hidden, since moonc
// would otherwise warn about its implicit promotion.

///|
pub extend RGBA with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend RGBA64 with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend NRGBA with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend NRGBA64 with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend Alpha with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend Alpha16 with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend Gray with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend Gray16 with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend CMYK with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend Paletted with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend YCbCr with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend Point with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Point with Eq::{not_equal}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend Point with Show::{output}

///|
pub extend Point with Add::{add}

///|
pub extend Point with Sub::{sub}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend Rectangle with Show::{output}

///|
pub extend Rectangle with Image::{
  color_model,
  bounds,
  at,
  opaque_,
  set,
  sub_image,
  as_ycbcr,
  raw_data,
  get_bytes_per_pixel,
  get_stride,
  pix_offset,
  color_index_at,
}

///|
pub extend Rectangle with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Rectangle with Eq::{not_equal}

///|
pub extend SizeError with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend SizeError with Eq::{not_equal}

///|
pub extend SizeError with Show::{to_string}

///|
#deprecated("Use `Show::output` via the trait or `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend SizeError with Show::{output}

///|
pub extend YCbCrSubsampling with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend YCbCrSubsampling with Eq::{not_equal}
