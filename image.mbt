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
/// Values of the [Image] trait are created either by calling functions such
/// as [RGBA::new] and [Paletted::new], or by calling [Decode] on an [io.Reader] containing
/// image data in a format such as GIF, JPEG or PNG. Decoding any particular
/// image format requires the prior registration of a decoder function.
/// Registration is typically automatic as a side effect of initializing that
/// format's package so that, to decode a PNG image, it suffices to have
///
///	import _ "image/png"
///
/// in a program's main package. The _ means to import a package purely for its
/// initialization side effects.
///
/// See "The Go image package" for more details:
/// https://golang.org/doc/articles/image_package.html
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

/// Config holds an image's color model and dimensions.
pub struct Config {
  color_model : @color.Model
  width : Int
  height : Int
}

/// Image is a finite rectangular grid of [color.Color] values taken from a color
/// model.
pub(open) trait Image {
  /// color_model returns the Image's color model.
  color_model(Self) -> @color.Model
  /// bounds returns the domain for which At can return non-zero color.
  /// The bounds do not necessarily contain the point (0, 0).
  bounds(Self) -> Rectangle
  /// At returns the color of the pixel at (x, y).
  /// At(bounds().Min.X, bounds().Min.Y) returns the upper-left pixel of the grid.
  /// At(bounds().Max.X-1, bounds().Max.Y-1) returns the lower-right one.
  at(Self, Int, Int) -> @color.Color

  // other available methods:
  opaque(Self) -> Bool
  set(Self, Int, Int, @color.Color) -> Unit
  sub_image(Self, Rectangle) -> Image
}

/// RGBA64Image is an [Image] whose pixels can be converted directly to a
/// color.RGBA64.
pub(open) trait RGBA64Image {
  /// rgba64_at returns the RGBA64 color of the pixel at (x, y). It is
  /// equivalent to calling at(x, y).rgba() and converting the resulting
  /// 32-bit return values to a color.RGBA64, but it can avoid allocations
  /// from converting concrete color types to the color.Color trait type.
  rgba64_at(Self, Int, Int) -> @color.RGBA64
  /// Image trait:
  color_model(Self) -> @color.Model
  bounds(Self) -> Rectangle
  at(Self, Int, Int) -> @color.Color
}

/// PalettedImage is an image whose colors may come from a limited palette.
/// If m is a PalettedImage and m.color_model() returns a [color.Palette] p,
/// then m.At(x, y) should be equivalent to p[m.color_index_at(x, y)]. If m's
/// color model is not a color.Palette, then color_index_at's behavior is
/// undefined.
pub(open) trait PalettedImage {
  /// color_index_at returns the palette index of the pixel at (x, y).
  color_index_at(Self, Int, Int) -> Byte
  /// Image trait:
  color_model(Self) -> @color.Model
  bounds(Self) -> Rectangle
  at(Self, Int, Int) -> @color.Color
}

type! SizeError String derive(Show, Eq)

// pixel_buffer_length returns the length of the []Byte typed pix slice field
// for the NewXxx functions. Conceptually, this is just (bpp * width * height),
// but this function panics if at least one of those is negative or if the
// computation would overflow the int type.
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

/// RGBA is an in-memory image whose At method returns [color.RGBA] values.
pub struct RGBA {
  // pix holds the image's pixels, in R, G, B, A order. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*4].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn RGBA::empty() -> RGBA {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : RGBA) -> @color.Model {
  @color.rgba_model
}

pub fn bounds(self : RGBA) -> Rectangle {
  self.rect
}

pub fn op_get(self : RGBA, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : RGBA, x : Int, y : Int) -> @color.Color {
  self.rgba_at(x, y)
}

pub fn rgba64_at(self : RGBA, x : Int, y : Int) -> @color.RGBA64 {
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
pub fn pix_offset(self : RGBA, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 4
}

pub fn op_set(self : RGBA, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : RGBA, x : Int, y : Int, c : @color.Color) -> Unit {
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

pub fn set_rgba64(self : RGBA, x : Int, y : Int, c : @color.RGBA64) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (c.r >> 8).to_byte()
  self.pix[i + 1] = (c.g >> 8).to_byte()
  self.pix[i + 2] = (c.b >> 8).to_byte()
  self.pix[i + 3] = (c.a >> 8).to_byte()
}

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

/// sub_image returns an image representing the portion of the image p visible
/// through r. The returned value shares pixels with the original image.
pub fn sub_image(self : RGBA, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return RGBA::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  RGBA::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : RGBA) -> Bool {
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
pub fn RGBA::new(r : Rectangle) -> RGBA!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(4, r, "RGBA"), b'\x00')[:],
    stride: 4 * r.dx(),
    rect: r,
  }
}

// RGBA64 is an in-memory image whose At method returns [color.RGBA64] values.
pub struct RGBA64 {
  // pix holds the image's pixels, in R, G, B, A order and big-endian format. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*8].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn RGBA64::empty() -> RGBA64 {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : RGBA64) -> @color.Model {
  @color.rgba64_model
}

pub fn bounds(self : RGBA64) -> Rectangle {
  self.rect
}

pub fn op_get(self : RGBA64, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : RGBA64, x : Int, y : Int) -> @color.Color {
  self.rgba64_at(x, y)
}

pub fn rgba64_at(self : RGBA64, x : Int, y : Int) -> @color.RGBA64 {
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
pub fn pix_offset(self : RGBA64, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 8
}

pub fn op_set(self : RGBA64, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : RGBA64, x : Int, y : Int, c : @color.Color) -> Unit {
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

pub fn set_rgba64(self : RGBA64, x : Int, y : Int, c : @color.RGBA64) -> Unit {
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
pub fn sub_image(self : RGBA64, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return RGBA64::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  RGBA64::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : RGBA64) -> Bool {
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
pub fn RGBA64::new(r : Rectangle) -> RGBA64!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(8, r, "RGBA64"), b'\x00')[:],
    stride: 8 * r.dx(),
    rect: r,
  }
}

// NRGBA is an in-memory image whose At method returns [color.NRGBA] values.
pub struct NRGBA {
  // pix holds the image's pixels, in R, G, B, A order. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*4].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn NRGBA::empty() -> NRGBA {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : NRGBA) -> @color.Model {
  @color.nrgba_model
}

pub fn bounds(self : NRGBA) -> Rectangle {
  self.rect
}

pub fn op_get(self : NRGBA, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : NRGBA, x : Int, y : Int) -> @color.Color {
  self.nrgba_at(x, y)
}

pub fn rgba64_at(self : NRGBA, x : Int, y : Int) -> @color.RGBA64 {
  let (r, g, b, a) = self.nrgba_at(x, y).rgba()
  @color.RGBA64::new(r, g, b, a)
}

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
pub fn pix_offset(self : NRGBA, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 4
}

pub fn op_set(self : NRGBA, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : NRGBA, x : Int, y : Int, c : @color.Color) -> Unit {
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

pub fn set_rgba64(self : NRGBA, x : Int, y : Int, c : @color.RGBA64) -> Unit {
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
pub fn sub_image(self : NRGBA, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return NRGBA::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  NRGBA::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : NRGBA) -> Bool {
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
pub fn NRGBA::new(r : Rectangle) -> NRGBA!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(4, r, "NRGBA"), b'\x00')[:],
    stride: 4 * r.dx(),
    rect: r,
  }
}

// NRGBA64 is an in-memory image whose At method returns [color.NRGBA64] values.
pub struct NRGBA64 {
  // pix holds the image's pixels, in R, G, B, A order and big-endian format. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*8].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn NRGBA64::empty() -> NRGBA64 {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : NRGBA64) -> @color.Model {
  @color.nrgba64_model
}

pub fn bounds(self : NRGBA64) -> Rectangle {
  self.rect
}

pub fn op_get(self : NRGBA64, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : NRGBA64, x : Int, y : Int) -> @color.Color {
  self.nrgba64_at(x, y)
}

pub fn rgba64_at(self : NRGBA64, x : Int, y : Int) -> @color.RGBA64 {
  let (r, g, b, a) = self.nrgba64_at(x, y).rgba()
  @color.RGBA64::new(r, g, b, a)
}

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
pub fn pix_offset(self : NRGBA64, x : Int, y : Int) -> Int {
  return (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 8
}

pub fn op_set(self : NRGBA64, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : NRGBA64, x : Int, y : Int, c : @color.Color) -> Unit {
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

pub fn set_rgba64(self : NRGBA64, x : Int, y : Int, c : @color.RGBA64) -> Unit {
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
pub fn sub_image(self : NRGBA64, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return NRGBA64::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  NRGBA64::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : NRGBA64) -> Bool {
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
pub fn NRGBA64::new(r : Rectangle) -> NRGBA64!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(8, r, "NRGBA64"), b'\x00')[:],
    stride: 8 * r.dx(),
    rect: r,
  }
}

// Alpha is an in-memory image whose At method returns [color.Alpha] values.
pub struct Alpha {
  // pix holds the image's pixels, as alpha values. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*1].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn Alpha::empty() -> Alpha {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : Alpha) -> @color.Model {
  @color.alpha_model
}

pub fn bounds(self : Alpha) -> Rectangle {
  self.rect
}

pub fn op_get(self : Alpha, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : Alpha, x : Int, y : Int) -> @color.Color {
  self.alpha_at(x, y)
}

pub fn rgba64_at(self : Alpha, x : Int, y : Int) -> @color.RGBA64 {
  let mut a = self.alpha_at(x, y).a.to_uint()
  a = a | (a << 8)
  { r: a, g: a, b: a, a }
}

pub fn alpha_at(self : Alpha, x : Int, y : Int) -> @color.Alpha {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.Alpha::new(0)
  }
  let i = self.pix_offset(x, y)
  { a: self.pix[i] }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
pub fn pix_offset(self : Alpha, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 1
}

pub fn op_set(self : Alpha, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : Alpha, x : Int, y : Int, c : @color.Color) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { a } = @color.Alpha::from(c)
  self.pix[i] = a
}

pub fn set_rgba64(self : Alpha, x : Int, y : Int, c : @color.RGBA64) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = (c.a >> 8).to_byte()
}

pub fn set_alpha(self : Alpha, x : Int, y : Int, c : @color.Alpha) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = c.a
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
pub fn sub_image(self : Alpha, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Alpha::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Alpha::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : Alpha) -> Bool {
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
pub fn Alpha::new(r : Rectangle) -> Alpha!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(1, r, "Alpha"), b'\x00')[:],
    stride: 1 * r.dx(),
    rect: r,
  }
}

// Alpha16 is an in-memory image whose At method returns [color.Alpha16] values.
pub struct Alpha16 {
  // pix holds the image's pixels, as alpha values in big-endian format. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*2].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn Alpha16::empty() -> Alpha16 {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : Alpha16) -> @color.Model {
  @color.alpha16_model
}

pub fn bounds(self : Alpha16) -> Rectangle {
  self.rect
}

pub fn op_get(self : Alpha16, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : Alpha16, x : Int, y : Int) -> @color.Color {
  self.alpha16_at(x, y)
}

pub fn rgba64_at(self : Alpha16, x : Int, y : Int) -> @color.RGBA64 {
  let a = self.alpha16_at(x, y).a
  { r: a, g: a, b: a, a }
}

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
pub fn pix_offset(self : Alpha16, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 2
}

pub fn op_set(self : Alpha16, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : Alpha16, x : Int, y : Int, c : @color.Color) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { a } = @color.Alpha16::from(c)
  self.pix[i + 0] = (a >> 8).to_byte()
  self.pix[i + 1] = a.to_byte()
}

pub fn set_rgba64(self : Alpha16, x : Int, y : Int, c : @color.RGBA64) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (c.a >> 8).to_byte()
  self.pix[i + 1] = c.a.to_byte()
}

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
pub fn sub_image(self : Alpha16, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Alpha16::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Alpha16::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : Alpha16) -> Bool {
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
pub fn Alpha16::new(r : Rectangle) -> Alpha16!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(2, r, "Alpha16"), b'\x00')[:],
    stride: 2 * r.dx(),
    rect: r,
  }
}

// Gray is an in-memory image whose At method returns [color.Gray] values.
pub struct Gray {
  // pix holds the image's pixels, as gray values. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*1].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn Gray::empty() -> Gray {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : Gray) -> @color.Model {
  @color.gray_model
}

pub fn bounds(self : Gray) -> Rectangle {
  self.rect
}

pub fn op_get(self : Gray, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : Gray, x : Int, y : Int) -> @color.Color {
  self.gray_at(x, y)
}

pub fn rgba64_at(self : Gray, x : Int, y : Int) -> @color.RGBA64 {
  let mut gray = self.gray_at(x, y).y.to_uint()
  gray = gray | (gray << 8)
  { r: gray, g: gray, b: gray, a: 0xffff }
}

pub fn gray_at(self : Gray, x : Int, y : Int) -> @color.Gray {
  if not(pt(x, y).is_in(self.rect)) {
    return @color.Gray::new(0)
  }
  let i = self.pix_offset(x, y)
  { y: self.pix[i] }
}

// pix_offset returns the index of the first element of pix that corresponds to
// the pixel at (x, y).
pub fn pix_offset(self : Gray, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 1
}

pub fn op_set(self : Gray, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : Gray, x : Int, y : Int, c : @color.Color) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { y } = @color.Gray::from(c)
  self.pix[i] = y
}

pub fn set_rgba64(self : Gray, x : Int, y : Int, c : @color.RGBA64) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  // This formula is the same as in color.grayModel.
  let gray = (19595U * c.r + 38470U * c.g + 7471U * c.b + (1U << 15)) >> 24
  let i = self.pix_offset(x, y)
  self.pix[i] = gray.to_byte()
}

pub fn set_gray(self : Gray, x : Int, y : Int, c : @color.Gray) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = c.y
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
pub fn sub_image(self : Gray, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Gray::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Gray::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : Gray) -> Bool {
  true
}

// Gray::new returns a new [Gray] image with the given bounds.
pub fn Gray::new(r : Rectangle) -> Gray!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(1, r, "Gray"), b'\x00')[:],
    stride: 1 * r.dx(),
    rect: r,
  }
}

// Gray16 is an in-memory image whose At method returns [color.Gray16] values.
pub struct Gray16 {
  // pix holds the image's pixels, as gray values in big-endian format. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*2].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn Gray16::empty() -> Gray16 {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : Gray16) -> @color.Model {
  @color.gray16_model
}

pub fn bounds(self : Gray16) -> Rectangle {
  self.rect
}

pub fn op_get(self : Gray16, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : Gray16, x : Int, y : Int) -> @color.Color {
  self.gray16_at(x, y)
}

pub fn rgba64_at(self : Gray16, x : Int, y : Int) -> @color.RGBA64 {
  let gray = self.gray16_at(x, y).y
  { r: gray, g: gray, b: gray, a: 0xffff }
}

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
pub fn pix_offset(self : Gray16, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 2
}

pub fn op_set(self : Gray16, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : Gray16, x : Int, y : Int, c : @color.Color) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  let { y } = @color.Gray16::from(c)
  self.pix[i + 0] = (y >> 8).to_byte()
  self.pix[i + 1] = y.to_byte()
}

pub fn set_rgba64(self : Gray16, x : Int, y : Int, c : @color.RGBA64) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  // This formula is the same as in color.gray16Model.
  let gray = (19595U * c.r + 38470U * c.g + 7471U * c.b + (1U << 15)) >> 16
  let i = self.pix_offset(x, y)
  self.pix[i + 0] = (gray >> 8).to_byte()
  self.pix[i + 1] = gray.to_byte()
}

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
pub fn sub_image(self : Gray16, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Gray16::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  Gray16::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : Gray16) -> Bool {
  true
}

// Gray16::new returns a new [Gray16] image with the given bounds.
pub fn Gray16::new(r : Rectangle) -> Gray16!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(2, r, "Gray16"), b'\x00')[:],
    stride: 2 * r.dx(),
    rect: r,
  }
}

// CMYK is an in-memory image whose At method returns [color.CMYK] values.
pub struct CMYK {
  // pix holds the image's pixels, in C, M, Y, K order. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*4].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
}

pub fn CMYK::empty() -> CMYK {
  { pix: [][:], stride: 0, rect: Rectangle::new() }
}

pub fn color_model(self : CMYK) -> @color.Model {
  @color.cmyk_model
}

pub fn bounds(self : CMYK) -> Rectangle {
  self.rect
}

pub fn op_get(self : CMYK, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : CMYK, x : Int, y : Int) -> @color.Color {
  self.cmyk_at(x, y)
}

pub fn rgba64_at(self : CMYK, x : Int, y : Int) -> @color.RGBA64 {
  let (r, g, b, a) = self.cmyk_at(x, y).rgba()
  { r, g, b, a }
}

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
pub fn pix_offset(self : CMYK, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 4
}

pub fn set(self : CMYK, x : Int, y : Int, c : @color.Color) -> Unit {
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

pub fn set_rgba64(self : CMYK, x : Int, y : Int, c : @color.RGBA64) -> Unit {
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
pub fn sub_image(self : CMYK, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return CMYK::empty()
  }
  let i = self.pix_offset(r.min.x, r.min.y)
  CMYK::{ pix: self.pix[i:], stride: self.stride, rect: r }
}

// opaque scans the entire image and reports whether it is fully opaque.
pub fn opaque(self : CMYK) -> Bool {
  true
}

// CMYK::new returns a new CMYK image with the given bounds.
pub fn CMYK::new(r : Rectangle) -> CMYK!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(4, r, "CMYK"), b'\x00')[:],
    stride: 4 * r.dx(),
    rect: r,
  }
}

// Paletted is an in-memory image of Byte indices into a given palette.
pub struct Paletted {
  // pix holds the image's pixels, as palette indices. The pixel at
  // (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*1].
  pix : ArrayView[Byte]
  // stride is the pix stride (in bytes) between vertically adjacent pixels.
  stride : Int
  // rect is the image's bounds.
  rect : Rectangle
  // Palette is the image's palette.
  palette : @color.Palette
}

pub fn color_model(self : Paletted) -> @color.Model {
  self.palette
}

pub fn bounds(self : Paletted) -> Rectangle {
  self.rect
}

pub fn op_get(self : Paletted, p : Point) -> @color.Color {
  self.at(p.x, p.y)
}

pub fn at(self : Paletted, x : Int, y : Int) -> @color.Color {
  if self.palette._.length() == 0 {
    return @color.black // nil
  }
  if not(pt(x, y).is_in(self.rect)) {
    return self.palette._[0]
  }
  let i = self.pix_offset(x, y)
  return self.palette._[self.pix[i].to_int()]
}

pub fn rgba64_at(self : Paletted, x : Int, y : Int) -> @color.RGBA64 {
  if self.palette._.length() == 0 {
    return @color.RGBA64::new(0, 0, 0, 0)
  }
  let mut c : @color.Color = @color.black
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
pub fn pix_offset(self : Paletted, x : Int, y : Int) -> Int {
  (y - self.rect.min.y) * self.stride + (x - self.rect.min.x) * 1
}

pub fn op_set(self : Paletted, p : Point, c : @color.Color) -> Unit {
  self.set(p.x, p.y, c)
}

pub fn set(self : Paletted, x : Int, y : Int, c : @color.Color) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = self.palette.index(c).to_byte()
}

pub fn set_rgba64(self : Paletted, x : Int, y : Int, c : @color.RGBA64) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = self.palette.index(c).to_byte()
}

pub fn color_index_at(self : Paletted, x : Int, y : Int) -> Byte {
  if not(pt(x, y).is_in(self.rect)) {
    return 0
  }
  let i = self.pix_offset(x, y)
  self.pix[i]
}

pub fn set_color_index(self : Paletted, x : Int, y : Int, index : Byte) -> Unit {
  if not(pt(x, y).is_in(self.rect)) {
    return
  }
  let i = self.pix_offset(x, y)
  self.pix[i] = index
}

// sub_image returns an image representing the portion of the image p visible
// through r. The returned value shares pixels with the original image.
pub fn sub_image(self : Paletted, r : Rectangle) -> Image {
  let r = r.intersect(self.rect)
  // If r1 and r2 are Rectangles, r1.intersect(r2) is not guaranteed to be inside
  // either r1 or r2 if the intersection is empty. Without explicitly checking for
  // this, the pix[i:] expression below can panic.
  if r.empty() {
    return Paletted::{
      pix: [][:],
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
pub fn opaque(self : Paletted) -> Bool {
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
pub fn Paletted::new(r : Rectangle, p : @color.Palette) -> Paletted!SizeError {
  {
    pix: Array::make(pixel_buffer_length!(1, r, "Paletted"), b'\x00')[:],
    stride: 1 * r.dx(),
    rect: r,
    palette: p,
  }
}
