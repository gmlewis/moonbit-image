///|
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/image.go
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.
///
/// Package image implements a basic 2-D image library.
///
/// The fundamental trait is called [Image]. An [Image] contains colors, which
/// are described in the image/color package.
///
/// # Security Considerations
///
/// The image package can be used to parse arbitrarily large images, which can
/// cause resource exhaustion on machines which do not have enough memory to
/// store them. When operating on arbitrary images, [DecodeConfig] should be called
/// before [Decode], so that the program can decide whether the image, as defined
/// in the returned header, can be safely decoded with the available resources. A
/// call to [Decode] which produces an extremely large image, as defined in the
/// header returned by [DecodeConfig], is not considered a security issue,
/// regardless of whether the image is itself malformed or not. A call to
/// [DecodeConfig] which returns a header which does not match the image returned
/// by [Decode] may be considered a security issue, and should be reported per the
/// [Go Security Policy](https://go.dev/security/policy).
typealias @io.Slice

///|
/// Config holds an image's color model and dimensions.
pub(all) struct Config {
  color_model : &@color.Model
  width : Int
  height : Int
}

///|
pub fn Config::new_empty() -> Config {
  { color_model: @color.rgba_model, width: 0, height: 0 }
}

///|
/// Image is a finite rectangular grid of [color.Color] values taken from a color
/// model.
pub(open) trait Image {
  /// color_model returns the Image's color model.
  color_model(Self) -> &@color.Model
  /// bounds returns the domain for which At can return non-zero color.
  /// The bounds do not necessarily contain the point (0, 0).
  bounds(Self) -> Rectangle
  /// At returns the color of the pixel at (x, y).
  /// at(bounds().min.x, bounds().min.y) returns the upper-left pixel of the grid.
  /// at(bounds().max.x-1, bounds().max.y-1) returns the lower-right one.
  at(Self, Int, Int) -> &@color.Color

  // other available methods:
  opaque(Self) -> Bool
  set(Self, Int, Int, &@color.Color) -> Unit
  sub_image(Self, Rectangle) -> &Image

  // Because MoonBit does not have reflection, the following methods must
  // also be made available:
  raw_data(Self) -> Slice[Byte]
  get_bytes_per_pixel(Self) -> Int
  get_stride(Self) -> Int
  pix_offset(Self, Int, Int) -> Int
  /// color_index_at returns the palette index of the pixel at (x, y).
  /// It returns 0 for non-paletted images.
  color_index_at(Self, Int, Int) -> Byte
}

///|
pub fn &Image::new_empty() -> &Image {
  RGBA::new_empty()
}

///|
pub fn &Image::empty(self : &Image) -> Bool {
  self.bounds().empty()
}

///|
/// RGBA64Image is an [Image] whose pixels can be converted directly to a
/// color.RGBA64.
pub(open) trait RGBA64Image {
  /// rgba64_at returns the RGBA64 color of the pixel at (x, y). It is
  /// equivalent to calling at(x, y).rgba() and converting the resulting
  /// 32-bit return values to a color.RGBA64, but it can avoid allocations
  /// from converting concrete color types to the color.Color trait type.
  rgba64_at(Self, Int, Int) -> @color.RGBA64
  /// Image trait:
  color_model(Self) -> &@color.Model
  bounds(Self) -> Rectangle
  at(Self, Int, Int) -> &@color.Color
}

///|
type! SizeError String derive(Show, Eq)

// pixel_buffer_length returns the length of the Slice[Byte] typed pix slice field
// for the Xxx::new functions. Conceptually, this is just (bpp * width * height),
// but this function panics if at least one of those is negative or if the
// computation would overflow the int type.
///|
fn pixel_buffer_length(
  bytes_per_pixel : Int,
  r : Rectangle,
  image_type_name : String
) -> Int!SizeError {
  let total_length = mul3_non_neg(bytes_per_pixel, r.dx(), r.dy())
  if total_length < 0 {
    raise SizeError(
      "image: \{image_type_name}::new Rectangle has huge or negative dimensions",
    )
  }
  return total_length
}

///|
/// RGBA is an in-memory image whose At method returns [color.RGBA] values.
pub(all) struct RGBA {
  // pix holds the image's pixels, in R, G, B, A order. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*4].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `RGBA` satisfies the `Image` trait.
let _RGBA : &Image = RGBA::new_empty()

///|
pub fn RGBA::new_empty() -> RGBA {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for RGBA with raw_data(self) {
  self.pix
}

///|
pub impl Image for RGBA with get_bytes_per_pixel(_self) {
  4
}

///|
pub impl Image for RGBA with get_stride(self) {
  self.stride
}

///|
pub impl Image for RGBA with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for RGBA with color_model(_self) {
  @color.rgba_model
}

///|
pub impl Image for RGBA with bounds(self) {
  self.rect
}

///|
pub fn RGBA::op_get(self : RGBA, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for RGBA with at(self, x, y) {
  self.rgba_at(x, y)
}

///|
pub fn RGBA::rgba64_at(self : RGBA, x : Int, y : Int) -> @color.RGBA64 {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.RGBA64::new(0, 0, 0, 0)
  }
  let i = self.pix_offset(x, y)
  let r = self.pix[i + 0].to_uint()
  let g = self.pix[i + 1].to_uint()
  let b = self.pix[i + 2].to_uint()
  let a = self.pix[i + 3].to_uint()
  let r = (r << 8) | r
  let g = (g << 8) | g
  let b = (b << 8) | b
  let a = (a << 8) | a
  @color.RGBA64::new(r, g, b, a)
}

///|
pub fn rgba_at(self : RGBA, x : Int, y : Int) -> @color.RGBA {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.RGBA::new(0, 0, 0, 0)
  }
  let i = self.pix_offset(x, y)
  @color.RGBA::new(
    self.pix[i + 0],
    self.pix[i + 1],
    self.pix[i + 2],
    self.pix[i + 3],
  )
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for RGBA with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 4
}

///|
pub fn RGBA::op_set(self : RGBA, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for RGBA with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let (r, g, b, a) = @color.rgba_model.convert(c).rgba()
  self.pix[i + 0] = (r >> 8).to_byte()
  self.pix[i + 1] = (g >> 8).to_byte()
  self.pix[i + 2] = (b >> 8).to_byte()
  self.pix[i + 3] = (a >> 8).to_byte()
}

///|
pub fn RGBA::set_rgba64(
  self : RGBA,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (c.r >> 8).to_byte()
  self.pix[i + 1] = (c.g >> 8).to_byte()
  self.pix[i + 2] = (c.b >> 8).to_byte()
  self.pix[i + 3] = (c.a >> 8).to_byte()
}

///|
pub fn set_rgba(self : RGBA, x : Int, y : Int, c : @color.RGBA) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = c.r
  self.pix[i + 1] = c.g
  self.pix[i + 2] = c.b
  self.pix[i + 3] = c.a
}

///|
/// sub_image returns an image representing the portion of the image p visible
/// through r. The returned value shares pixels with the original image.
pub impl Image for RGBA with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return RGBA::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  RGBA::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for RGBA with opaque(self) {
  if self.rect.empty() {
    return true
  }
  let mut i0 = 3
  let mut i1 = self.rect.dx() * 4
  for y = self.rect.min.y; y < self.rect.max.y; y = y + 1 {
    for i = i0; i < i1; i = i + 4 {
      if self.pix[i] != 0xff {
        return false
      }
    }
    i0 += self.stride
    i1 += self.stride
  }
  true
}

// RGBA::new returns a new [RGBA] image with the given bounds.
///|
pub fn RGBA::new(r : Rectangle) -> RGBA!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(4, r, "RGBA"), b'\x00')),
    stride: 4 * r.dx(),
    rect: r,
  }
}

// RGBA64 is an in-memory image whose At method returns [color.RGBA64] values.
///|
pub(all) struct RGBA64 {
  // pix holds the image's pixels, in R, G, B, A order and big-endian format. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*8].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `RGBA64` satisfies the `Image` trait.
let _RGBA64 : &Image = RGBA64::new_empty()

///|
pub fn RGBA64::new_empty() -> RGBA64 {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for RGBA64 with raw_data(self) {
  self.pix
}

///|
pub impl Image for RGBA64 with get_bytes_per_pixel(_self) {
  8
}

///|
pub impl Image for RGBA64 with get_stride(self) {
  self.stride
}

///|
pub impl Image for RGBA64 with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for RGBA64 with color_model(_self) {
  @color.rgba64_model
}

///|
pub impl Image for RGBA64 with bounds(self) {
  self.rect
}

///|
pub fn RGBA64::op_get(self : RGBA64, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for RGBA64 with at(self, x, y) {
  self.rgba64_at(x, y)
}

///|
pub fn RGBA64::rgba64_at(self : RGBA64, x : Int, y : Int) -> @color.RGBA64 {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.RGBA64::new(0, 0, 0, 0)
  }
  let i = self.pix_offset(x, y)
  let r = (self.pix[i + 0].to_uint() << 8) | self.pix[i + 1].to_uint()
  let g = (self.pix[i + 2].to_uint() << 8) | self.pix[i + 3].to_uint()
  let b = (self.pix[i + 4].to_uint() << 8) | self.pix[i + 5].to_uint()
  let a = (self.pix[i + 6].to_uint() << 8) | self.pix[i + 7].to_uint()
  { r, g, b, a }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for RGBA64 with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 8
}

///|
pub fn RGBA64::op_set(self : RGBA64, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for RGBA64 with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { r, g, b, a } = @color.RGBA64::from(c)
  self.pix[i + 0] = (r >> 8).to_byte()
  self.pix[i + 1] = r.to_byte()
  self.pix[i + 2] = (g >> 8).to_byte()
  self.pix[i + 3] = g.to_byte()
  self.pix[i + 4] = (b >> 8).to_byte()
  self.pix[i + 5] = b.to_byte()
  self.pix[i + 6] = (a >> 8).to_byte()
  self.pix[i + 7] = a.to_byte()
}

///|
pub fn RGBA64::set_rgba64(
  self : RGBA64,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (c.r >> 8).to_byte()
  self.pix[i + 1] = c.r.to_byte()
  self.pix[i + 2] = (c.g >> 8).to_byte()
  self.pix[i + 3] = c.g.to_byte()
  self.pix[i + 4] = (c.b >> 8).to_byte()
  self.pix[i + 5] = c.b.to_byte()
  self.pix[i + 6] = (c.a >> 8).to_byte()
  self.pix[i + 7] = c.a.to_byte()
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for RGBA64 with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return RGBA64::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  RGBA64::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for RGBA64 with opaque(self) {
  if self.rect.empty() {
    return true
  }
  let mut i0 = 6
  let mut i1 = self.rect.dx() * 8
  for y = self.rect.min.y; y < self.rect.max.y; y = y + 1 {
    for i = i0; i < i1; i = i + 8 {
      if self.pix[i + 0] != 0xff || self.pix[i + 1] != 0xff {
        return false
      }
    }
    i0 += self.stride
    i1 += self.stride
  }
  true
}

// RGBA64::new returns a new [RGBA64] image with the given bounds.
///|
pub fn RGBA64::new(r : Rectangle) -> RGBA64!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(8, r, "RGBA64"), b'\x00')),
    stride: 8 * r.dx(),
    rect: r,
  }
}

// NRGBA is an in-memory image whose At method returns [color.NRGBA] values.
///|
pub(all) struct NRGBA {
  // pix holds the image's pixels, in R, G, B, A order. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*4].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `NRGBA` satisfies the `Image` trait.
let _NRGBA : &Image = NRGBA::new_empty()

///|
pub fn NRGBA::new_empty() -> NRGBA {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for NRGBA with raw_data(self) {
  self.pix
}

///|
pub impl Image for NRGBA with get_bytes_per_pixel(_self) {
  4
}

///|
pub impl Image for NRGBA with get_stride(self) {
  self.stride
}

///|
pub impl Image for NRGBA with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for NRGBA with color_model(_self) {
  @color.nrgba_model
}

///|
pub impl Image for NRGBA with bounds(self) {
  self.rect
}

///|
pub fn NRGBA::op_get(self : NRGBA, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for NRGBA with at(self, x, y) {
  self.nrgba_at(x, y)
}

///|
pub fn NRGBA::rgba64_at(self : NRGBA, x : Int, y : Int) -> @color.RGBA64 {
  let (r, g, b, a) = self.nrgba_at(x, y).rgba()
  @color.RGBA64::new(r, g, b, a)
}

///|
pub fn nrgba_at(self : NRGBA, x : Int, y : Int) -> @color.NRGBA {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.NRGBA::new(0, 0, 0, 0)
  }
  let i = self.pix_offset(x, y)
  @color.NRGBA::new(
    self.pix[i + 0],
    self.pix[i + 1],
    self.pix[i + 2],
    self.pix[i + 3],
  )
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for NRGBA with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 4
}

///|
pub fn NRGBA::op_set(self : NRGBA, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for NRGBA with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { r, g, b, a } = @color.NRGBA::from(c)
  self.pix[i + 0] = r
  self.pix[i + 1] = g
  self.pix[i + 2] = b
  self.pix[i + 3] = a
}

///|
pub fn NRGBA::set_rgba64(
  self : NRGBA,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let mut r = c.r
  let mut g = c.g
  let mut b = c.b
  if c.a != 0 && c.a != 0xffff {
    r = r * 0xffff / c.a
    g = g * 0xffff / c.a
    b = b * 0xffff / c.a
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (r >> 8).to_byte()
  self.pix[i + 1] = (g >> 8).to_byte()
  self.pix[i + 2] = (b >> 8).to_byte()
  self.pix[i + 3] = (c.a >> 8).to_byte()
}

///|
pub fn set_nrgba(self : NRGBA, x : Int, y : Int, c : @color.NRGBA) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = c.r
  self.pix[i + 1] = c.g
  self.pix[i + 2] = c.b
  self.pix[i + 3] = c.a
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for NRGBA with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return NRGBA::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  NRGBA::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for NRGBA with opaque(self) {
  if self.rect.empty() {
    return true
  }
  let mut i0 = 3
  let mut i1 = self.rect.dx() * 4
  for y = self.rect.min.y; y < self.rect.max.y; y = y + 1 {
    for i = i0; i < i1; i = i + 4 {
      if self.pix[i] != 0xff {
        return false
      }
    }
    i0 += self.stride
    i1 += self.stride
  }
  true
}

// NRGBA::new returns a new [NRGBA] image with the given bounds.
///|
pub fn NRGBA::new(r : Rectangle) -> NRGBA!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(4, r, "NRGBA"), b'\x00')),
    stride: 4 * r.dx(),
    rect: r,
  }
}

// NRGBA64 is an in-memory image whose At method returns [color.NRGBA64] values.
///|
pub(all) struct NRGBA64 {
  // pix holds the image's pixels, in R, G, B, A order and big-endian format. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*8].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `NRGBA64` satisfies the `Image` trait.
let _NRGBA64 : &Image = NRGBA64::new_empty()

///|
pub fn NRGBA64::new_empty() -> NRGBA64 {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for NRGBA64 with raw_data(self) {
  self.pix
}

///|
pub impl Image for NRGBA64 with get_bytes_per_pixel(_self) {
  8
}

///|
pub impl Image for NRGBA64 with get_stride(self) {
  self.stride
}

///|
pub impl Image for NRGBA64 with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for NRGBA64 with color_model(_self) {
  @color.nrgba64_model
}

///|
pub impl Image for NRGBA64 with bounds(self) {
  self.rect
}

///|
pub fn NRGBA64::op_get(self : NRGBA64, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for NRGBA64 with at(self, x, y) {
  self.nrgba64_at(x, y)
}

///|
pub fn NRGBA64::rgba64_at(self : NRGBA64, x : Int, y : Int) -> @color.RGBA64 {
  let (r, g, b, a) = self.nrgba64_at(x, y).rgba()
  @color.RGBA64::new(r, g, b, a)
}

///|
pub fn nrgba64_at(self : NRGBA64, x : Int, y : Int) -> @color.NRGBA64 {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.NRGBA64::new(0, 0, 0, 0)
  }
  let i = self.pix_offset(x, y)
  let r = (self.pix[i + 0].to_uint() << 8) | self.pix[i + 1].to_uint()
  let g = (self.pix[i + 2].to_uint() << 8) | self.pix[i + 3].to_uint()
  let b = (self.pix[i + 4].to_uint() << 8) | self.pix[i + 5].to_uint()
  let a = (self.pix[i + 6].to_uint() << 8) | self.pix[i + 7].to_uint()
  { r, g, b, a }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for NRGBA64 with pix_offset(self, x, y) {
  return (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 8
}

///|
pub fn NRGBA64::op_set(self : NRGBA64, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for NRGBA64 with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { r, g, b, a } = @color.NRGBA64::from(c)
  self.pix[i + 0] = (r >> 8).to_byte()
  self.pix[i + 1] = r.to_byte()
  self.pix[i + 2] = (g >> 8).to_byte()
  self.pix[i + 3] = g.to_byte()
  self.pix[i + 4] = (b >> 8).to_byte()
  self.pix[i + 5] = b.to_byte()
  self.pix[i + 6] = (a >> 8).to_byte()
  self.pix[i + 7] = a.to_byte()
}

///|
pub fn NRGBA64::set_rgba64(
  self : NRGBA64,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let mut r = c.r
  let mut g = c.g
  let mut b = c.b
  if c.a != 0 && c.a != 0xffff {
    r = r * 0xffff / c.a
    g = g * 0xffff / c.a
    b = b * 0xffff / c.a
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (r >> 8).to_byte()
  self.pix[i + 1] = r.to_byte()
  self.pix[i + 2] = (g >> 8).to_byte()
  self.pix[i + 3] = g.to_byte()
  self.pix[i + 4] = (b >> 8).to_byte()
  self.pix[i + 5] = b.to_byte()
  self.pix[i + 6] = (c.a >> 8).to_byte()
  self.pix[i + 7] = c.a.to_byte()
}

///|
pub fn set_nrgba64(
  self : NRGBA64,
  x : Int,
  y : Int,
  c : @color.NRGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (c.r >> 8).to_byte()
  self.pix[i + 1] = c.r.to_byte()
  self.pix[i + 2] = (c.g >> 8).to_byte()
  self.pix[i + 3] = c.g.to_byte()
  self.pix[i + 4] = (c.b >> 8).to_byte()
  self.pix[i + 5] = c.b.to_byte()
  self.pix[i + 6] = (c.a >> 8).to_byte()
  self.pix[i + 7] = c.a.to_byte()
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for NRGBA64 with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return NRGBA64::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  NRGBA64::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for NRGBA64 with opaque(self) {
  if self.rect.empty() {
    return true
  }
  let mut i0 = 6
  let mut i1 = self.rect.dx() * 8
  for y = self.rect.min.y; y < self.rect.max.y; y = y + 1 {
    for i = i0; i < i1; i = i + 8 {
      if self.pix[i + 0] != 0xff || self.pix[i + 1] != 0xff {
        return false
      }
    }
    i0 += self.stride
    i1 += self.stride
  }
  true
}

// NRGBA64::new returns a new [NRGBA64] image with the given bounds.
///|
pub fn NRGBA64::new(r : Rectangle) -> NRGBA64!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(8, r, "NRGBA64"), b'\x00')),
    stride: 8 * r.dx(),
    rect: r,
  }
}

// Alpha is an in-memory image whose At method returns [color.Alpha] values.
///|
pub(all) struct Alpha {
  // pix holds the image's pixels, as alpha values. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*1].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `Alpha` satisfies the `Image` trait.
let _Alpha : &Image = Alpha::new_empty()

///|
pub fn Alpha::new_empty() -> Alpha {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for Alpha with raw_data(self) {
  self.pix
}

///|
pub impl Image for Alpha with get_bytes_per_pixel(_self) {
  1
}

///|
pub impl Image for Alpha with get_stride(self) {
  self.stride
}

///|
pub impl Image for Alpha with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for Alpha with color_model(_self) {
  @color.alpha_model
}

///|
pub impl Image for Alpha with bounds(self) {
  self.rect
}

///|
pub fn Alpha::op_get(self : Alpha, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for Alpha with at(self, x, y) {
  self.alpha_at(x, y)
}

///|
pub fn Alpha::rgba64_at(self : Alpha, x : Int, y : Int) -> @color.RGBA64 {
  let mut a = self.alpha_at(x, y).a.to_uint()
  a = a | (a << 8)
  { r: a, g: a, b: a, a }
}

///|
pub fn alpha_at(self : Alpha, x : Int, y : Int) -> @color.Alpha {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.Alpha::new(0)
  }
  let i = self.pix_offset(x, y)
  { a: self.pix[i] }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for Alpha with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 1
}

///|
pub fn Alpha::op_set(self : Alpha, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for Alpha with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { a } = @color.Alpha::from(c)
  self.pix[i] = a
}

///|
pub fn Alpha::set_rgba64(
  self : Alpha,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = (c.a >> 8).to_byte()
}

///|
pub fn set_alpha(self : Alpha, x : Int, y : Int, c : @color.Alpha) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = c.a
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for Alpha with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Alpha::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Alpha::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for Alpha with opaque(self) {
  if self.rect.empty() {
    return true
  }
  let mut i0 = 0
  let mut i1 = self.rect.dx()
  for y = self.rect.min.y; y < self.rect.max.y; y = y + 1 {
    for i = i0; i < i1; i = i + 1 {
      if self.pix[i] != 0xff {
        return false
      }
    }
    i0 += self.stride
    i1 += self.stride
  }
  return true
}

// Alpha::new returns a new [Alpha] image with the given bounds.
///|
pub fn Alpha::new(r : Rectangle) -> Alpha!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(1, r, "Alpha"), b'\x00')),
    stride: 1 * r.dx(),
    rect: r,
  }
}

// Alpha16 is an in-memory image whose At method returns [color.Alpha16] values.
///|
pub(all) struct Alpha16 {
  // pix holds the image's pixels, as alpha values in big-endian format. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*2].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `Alpha16` satisfies the `Image` trait.
let _Alpha16 : &Image = Alpha16::new_empty()

///|
pub fn Alpha16::new_empty() -> Alpha16 {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for Alpha16 with raw_data(self) {
  self.pix
}

///|
pub impl Image for Alpha16 with get_bytes_per_pixel(_self) {
  2
}

///|
pub impl Image for Alpha16 with get_stride(self) {
  self.stride
}

///|
pub impl Image for Alpha16 with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for Alpha16 with color_model(_self) {
  @color.alpha16_model
}

///|
pub impl Image for Alpha16 with bounds(self) {
  self.rect
}

///|
pub fn Alpha16::op_get(self : Alpha16, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for Alpha16 with at(self, x, y) {
  self.alpha16_at(x, y)
}

///|
pub fn Alpha16::rgba64_at(self : Alpha16, x : Int, y : Int) -> @color.RGBA64 {
  let a = self.alpha16_at(x, y).a
  { r: a, g: a, b: a, a }
}

///|
pub fn alpha16_at(self : Alpha16, x : Int, y : Int) -> @color.Alpha16 {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.Alpha16::new(0)
  }
  let i = self.pix_offset(x, y)
  let a = (self.pix[i + 0].to_uint() << 8) | self.pix[i + 1].to_uint()
  { a, }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for Alpha16 with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 2
}

///|
pub fn Alpha16::op_set(self : Alpha16, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for Alpha16 with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { a } = @color.Alpha16::from(c)
  self.pix[i + 0] = (a >> 8).to_byte()
  self.pix[i + 1] = a.to_byte()
}

///|
pub fn Alpha16::set_rgba64(
  self : Alpha16,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (c.a >> 8).to_byte()
  self.pix[i + 1] = c.a.to_byte()
}

///|
pub fn set_alpha16(
  self : Alpha16,
  x : Int,
  y : Int,
  c : @color.Alpha16
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (c.a >> 8).to_byte()
  self.pix[i + 1] = c.a.to_byte()
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for Alpha16 with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Alpha16::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Alpha16::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for Alpha16 with opaque(self) {
  if self.rect.empty() {
    return true
  }
  let mut i0 = 0
  let mut i1 = self.rect.dx() * 2
  for y = self.rect.min.y; y < self.rect.max.y; y = y + 1 {
    for i = i0; i < i1; i = i + 2 {
      if self.pix[i + 0] != 0xff || self.pix[i + 1] != 0xff {
        return false
      }
    }
    i0 += self.stride
    i1 += self.stride
  }
  true
}

// Alpha16::new returns a new [Alpha16] image with the given bounds.
///|
pub fn Alpha16::new(r : Rectangle) -> Alpha16!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(2, r, "Alpha16"), b'\x00')),
    stride: 2 * r.dx(),
    rect: r,
  }
}

// Gray is an in-memory image whose At method returns [color.Gray] values.
///|
pub(all) struct Gray {
  // pix holds the image's pixels, as gray values. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*1].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `Gray` satisfies the `Image` trait.
let _Gray : &Image = Gray::new_empty()

///|
pub fn Gray::new_empty() -> Gray {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for Gray with raw_data(self) {
  self.pix
}

///|
pub impl Image for Gray with get_bytes_per_pixel(_self) {
  1
}

///|
pub impl Image for Gray with get_stride(self) {
  self.stride
}

///|
pub impl Image for Gray with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for Gray with color_model(_self) {
  @color.gray_model
}

///|
pub impl Image for Gray with bounds(self) {
  self.rect
}

///|
pub fn Gray::op_get(self : Gray, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for Gray with at(self, x, y) {
  self.gray_at(x, y)
}

///|
pub fn Gray::rgba64_at(self : Gray, x : Int, y : Int) -> @color.RGBA64 {
  let mut gray = self.gray_at(x, y).y.to_uint()
  gray = gray | (gray << 8)
  { r: gray, g: gray, b: gray, a: 0xffff }
}

///|
pub fn gray_at(self : Gray, x : Int, y : Int) -> @color.Gray {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.Gray::new(0)
  }
  let i = self.pix_offset(x, y)
  { y: self.pix[i] }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for Gray with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 1
}

///|
pub fn Gray::op_set(self : Gray, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for Gray with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { y } = @color.Gray::from(c)
  self.pix[i] = y
}

///|
pub fn Gray::set_rgba64(
  self : Gray,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  // This formula is the same as in color.grayModel.
  let gray = (19595U * c.r + 38470U * c.g + 7471U * c.b + (1U << 15)) >> 24
  let i = self.pix_offset(x, y)
  self.pix[i] = gray.to_byte()
}

///|
pub fn set_gray(self : Gray, x : Int, y : Int, c : @color.Gray) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = c.y
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for Gray with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Gray::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Gray::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for Gray with opaque(_self) {
  true
}

// Gray::new returns a new [Gray] image with the given bounds.
///|
pub fn Gray::new(r : Rectangle) -> Gray!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(1, r, "Gray"), b'\x00')),
    stride: 1 * r.dx(),
    rect: r,
  }
}

// Gray16 is an in-memory image whose At method returns [color.Gray16] values.
///|
pub(all) struct Gray16 {
  // pix holds the image's pixels, as gray values in big-endian format. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*2].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `Gray16` satisfies the `Image` trait.
let _Gray16 : &Image = Gray16::new_empty()

///|
pub fn Gray16::new_empty() -> Gray16 {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for Gray16 with raw_data(self) {
  self.pix
}

///|
pub impl Image for Gray16 with get_bytes_per_pixel(_self) {
  2
}

///|
pub impl Image for Gray16 with get_stride(self) {
  self.stride
}

///|
pub impl Image for Gray16 with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for Gray16 with color_model(_self) {
  @color.gray16_model
}

///|
pub impl Image for Gray16 with bounds(self) {
  self.rect
}

///|
pub fn Gray16::op_get(self : Gray16, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for Gray16 with at(self, x, y) {
  self.gray16_at(x, y)
}

///|
pub fn Gray16::rgba64_at(self : Gray16, x : Int, y : Int) -> @color.RGBA64 {
  let gray = self.gray16_at(x, y).y
  { r: gray, g: gray, b: gray, a: 0xffff }
}

///|
pub fn gray16_at(self : Gray16, x : Int, y : Int) -> @color.Gray16 {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.Gray16::new(0)
  }
  let i = self.pix_offset(x, y)
  let y = (self.pix[i + 0].to_uint() << 8) | self.pix[i + 1].to_uint()
  { y, }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for Gray16 with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 2
}

///|
pub fn Gray16::op_set(self : Gray16, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for Gray16 with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { y } = @color.Gray16::from(c)
  self.pix[i + 0] = (y >> 8).to_byte()
  self.pix[i + 1] = y.to_byte()
}

///|
pub fn Gray16::set_rgba64(
  self : Gray16,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  // This formula is the same as in color.gray16Model.
  let gray = (19595U * c.r + 38470U * c.g + 7471U * c.b + (1U << 15)) >> 16
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (gray >> 8).to_byte()
  self.pix[i + 1] = gray.to_byte()
}

///|
pub fn set_gray16(self : Gray16, x : Int, y : Int, c : @color.Gray16) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (c.y >> 8).to_byte()
  self.pix[i + 1] = c.y.to_byte()
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for Gray16 with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Gray16::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Gray16::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for Gray16 with opaque(_self) {
  true
}

// Gray16::new returns a new [Gray16] image with the given bounds.
///|
pub fn Gray16::new(r : Rectangle) -> Gray16!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(2, r, "Gray16"), b'\x00')),
    stride: 2 * r.dx(),
    rect: r,
  }
}

// CMYK is an in-memory image whose At method returns [color.CMYK] values.
///|
pub(all) struct CMYK {
  // pix holds the image's pixels, in C, M, Y, K order. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*4].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

///|
/// `CMYK` satisfies the `Image` trait.
let _CMYK : &Image = CMYK::new_empty()

///|
pub fn CMYK::new_empty() -> CMYK {
  { pix: Slice::new([]), stride: 0, rect: Rectangle::new() }
}

///|
pub impl Image for CMYK with raw_data(self) {
  self.pix
}

///|
pub impl Image for CMYK with get_bytes_per_pixel(_self) {
  4
}

///|
pub impl Image for CMYK with get_stride(self) {
  self.stride
}

///|
pub impl Image for CMYK with color_index_at(_self, _x, _y) {
  0
}

///|
pub impl Image for CMYK with color_model(_self) {
  @color.cmyk_model
}

///|
pub impl Image for CMYK with bounds(self) {
  self.rect
}

///|
pub fn CMYK::op_get(self : CMYK, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for CMYK with at(self, x, y) {
  self.cmyk_at(x, y)
}

///|
pub fn CMYK::rgba64_at(self : CMYK, x : Int, y : Int) -> @color.RGBA64 {
  let (r, g, b, a) = self.cmyk_at(x, y).rgba()
  { r, g, b, a }
}

///|
pub fn cmyk_at(self : CMYK, x : Int, y : Int) -> @color.CMYK {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.CMYK::new(0, 0, 0, 0)
  }
  let i = self.pix_offset(x, y)
  {
    c: self.pix[i + 0],
    m: self.pix[i + 1],
    y: self.pix[i + 2],
    k: self.pix[i + 3],
  }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for CMYK with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 4
}

///|
pub impl Image for CMYK with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { c, m, y, k } = @color.CMYK::from(c)
  self.pix[i + 0] = c
  self.pix[i + 1] = m
  self.pix[i + 2] = y
  self.pix[i + 3] = k
}

///|
pub fn CMYK::set_rgba64(
  self : CMYK,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let (cc, mm, yy, kk) = @color.rgb_to_cmyk(
    (c.r >> 8).to_byte(),
    (c.g >> 8).to_byte(),
    (c.b >> 8).to_byte(),
  )
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = cc
  self.pix[i + 1] = mm
  self.pix[i + 2] = yy
  self.pix[i + 3] = kk
}

///|
pub fn set_cmyk(self : CMYK, x : Int, y : Int, c : @color.CMYK) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = c.c
  self.pix[i + 1] = c.m
  self.pix[i + 2] = c.y
  self.pix[i + 3] = c.k
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for CMYK with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return CMYK::new_empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  CMYK::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for CMYK with opaque(_self) {
  true
}

// CMYK::new returns a new CMYK image with the given bounds.
///|
pub fn CMYK::new(r : Rectangle) -> CMYK!SizeError {
  {
    pix: Slice::new(Array::make(pixel_buffer_length!(4, r, "CMYK"), b'\x00')),
    stride: 4 * r.dx(),
    rect: r,
  }
}

// Paletted is an in-memory image of Byte indices into a given palette.
///|
pub(all) struct Paletted {
  // pix holds the image's pixels, as palette indices. The pixel at
  // (x, y) starts at pix[(y-rect.min.y)*stride + (x-rect.min.x)*1].
  pix : Slice[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
  // Palette is the image's palette.
  mut palette : @color.Palette
}

///|
/// `Paletted` satisfies the `Image` trait.
let _Paletted : &Image = Paletted::new_empty()

///|
pub impl Image for Paletted with raw_data(self) {
  self.pix
}

///|
pub impl Image for Paletted with get_bytes_per_pixel(_self) {
  1
}

///|
pub impl Image for Paletted with get_stride(self) {
  self.stride
}

///|
pub impl Image for Paletted with color_model(self) {
  self.palette
}

///|
pub impl Image for Paletted with bounds(self) {
  self.rect
}

///|
pub fn Paletted::op_get(self : Paletted, p : Point) -> &@color.Color {
  self.at(p.x, p.y)
}

///|
pub impl Image for Paletted with at(self, x, y) {
  if self.palette._.length() == 0 {
    return @color.black // nil
  }
  if not(pt(x, y).is_in(self.rect)) {
    return self.palette._[0]
  }
  let i = self.pix_offset(x, y)
  return self.palette._[self.pix[i].to_int()]
}

///|
pub fn Paletted::rgba64_at(self : Paletted, x : Int, y : Int) -> @color.RGBA64 {
  if self.palette._.length() == 0 {
    return @color.RGBA64::new(0, 0, 0, 0)
  }
  let mut c : &@color.Color = @color.black
  if not(pt(x, y).is_in(self.rect)) {
    c = self.palette._[0]
  } else {
    let i = self.pix_offset(x, y)
    c = self.palette._[self.pix[i].to_int()]
  }
  let (r, g, b, a) = c.rgba()
  { r, g, b, a }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
///|
pub impl Image for Paletted with pix_offset(self, x, y) {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 1
}

///|
pub fn Paletted::op_set(self : Paletted, p : Point, c : &@color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

///|
pub impl Image for Paletted with set(self, x, y, c) {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = self.palette.index(c).to_byte()
}

///|
pub fn Paletted::set_rgba64(
  self : Paletted,
  x : Int,
  y : Int,
  c : @color.RGBA64
) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = self.palette.index(c).to_byte()
}

///|
pub impl Image for Paletted with color_index_at(self, x, y) {
  if not(pt(x, y).is_in(self.rect)) {
    return 0
  }
  let i = self.pix_offset(x, y)
  self.pix[i]
}

///|
pub fn set_color_index(self : Paletted, x : Int, y : Int, index : Byte) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = index
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
///|
pub impl Image for Paletted with sub_image(self, r) {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Paletted::{
      pix: Slice::new([]),
      stride: 0,
      rect: Rectangle::new(),
      palette: self.palette,
    }
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Paletted::{
    pix: self.pix[i:],
    stride: self.stride,
    rect: self.rect.intersect(r),
    palette: self.palette,
  }
}

// opaque scans the entire image and reports whether it is fully opaque.
///|
pub impl Image for Paletted with opaque(self) {
  let present = Array::make(256, false)
  let mut i0 = 0
  let mut i1 = self.rect.dx()
  for y = self.rect.min.y; y < self.rect.max.y; y = y + 1 {
    for c in self.pix[i0:i1] {
      present[c.to_int()] = true
    }
    i0 += self.stride
    i1 += self.stride
  }
  for i, c in self.palette._ {
    if not(present[i]) {
      continue
    }
    let (_, _, _, a) = c.rgba()
    if a != 0xffff {
      return false
    }
  }
  true
}

// Paletted::new returns a new [Paletted] image with the given width, height and
// palette.
///|
pub fn Paletted::new(r : Rectangle, p : @color.Palette) -> Paletted!SizeError {
  {
    pix: Slice::new(
      Array::make(pixel_buffer_length!(1, r, "Paletted"), b'\x00'),
    ),
    stride: 1 * r.dx(),
    rect: r,
    palette: p,
  }
}

///|
pub fn Paletted::new_empty() -> Paletted {
  {
    pix: Slice::new([]),
    stride: 0,
    rect: Rectangle::new(),
    palette: @color.Palette::new_empty(),
  }
}
