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
/// as [RGBA::new] and [NewPaletted], or by calling [Decode] on an [io.Reader] containing
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
pub trait Image {
  /// color_model returns the Image's color model.
  color_model(Self) -> @color.Model
  /// bounds returns the domain for which At can return non-zero color.
  /// The bounds do not necessarily contain the point (0, 0).
  bounds(Self) -> Rectangle
  /// At returns the color of the pixel at (x, y).
  /// At(bounds().Min.X, bounds().Min.Y) returns the upper-left pixel of the grid.
  /// At(bounds().Max.X-1, bounds().Max.Y-1) returns the lower-right one.
  at(Self, Int, Int) -> @color.Color
}

/// RGBA64Image is an [Image] whose pixels can be converted directly to a
/// color.RGBA64.
pub trait RGBA64Image {
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
pub trait PalettedImage {
  /// color_index_at returns the palette index of the pixel at (x, y).
  color_index_at(Self, Int, Int) -> Byte
  /// Image trait:
  color_model(Self) -> @color.Model
  bounds(Self) -> Rectangle
  at(Self, Int, Int) -> @color.Color
}

// pixel_buffer_length returns the length of the []Byte typed pix slice field
// for the NewXxx functions. Conceptually, this is just (bpp * width * height),
// but this function panics if at least one of those is negative or if the
// computation would overflow the int type.
//
// This panics instead of returning an error because of backwards
// compatibility. The NewXxx functions do not return an error.
fn pixel_buffer_length(
  bytes_per_pixel : Int,
  r : Rectangle,
  image_type_name : String
) -> Int {
  let total_length = mul3_non_neg(bytes_per_pixel, r.dx(), r.dy())
  if total_length < 0 {
    abort(
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
  // If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
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
pub fn RGBA::new(r : Rectangle) -> RGBA {
  {
    pix: Array::make(pixel_buffer_length(4, r, "RGBA"), b'\x00')[:],
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
  // Rect is the image's bounds.
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
  let (r, g, b, a) = @color.rgba64_model.convert(c).rgba() // .(color.RGBA64)
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
  // If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
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
  return true
}

// RGBA64::new returns a new [RGBA64] image with the given bounds.
pub fn RGBA64::new(r : Rectangle) -> RGBA64 {
  {
    pix: Array::make(pixel_buffer_length(8, r, "RGBA64"), b'\x00')[:],
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
  // Rect is the image's bounds.
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
  let (r, g, b, a) = @color.nrgba_model.convert(c).rgba() // .(color.NRGBA)
  self.pix[i + 0] = (r >> 8).to_byte()
  self.pix[i + 1] = (g >> 8).to_byte()
  self.pix[i + 2] = (b >> 8).to_byte()
  self.pix[i + 3] = (a >> 8).to_byte()
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
  // If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
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
  return true
}

// NRGBA::new returns a new [NRGBA] image with the given bounds.
pub fn NRGBA::new(r : Rectangle) -> NRGBA {
  {
    pix: Array::make(pixel_buffer_length(4, r, "NRGBA"), b'\x00')[:],
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
  // Rect is the image's bounds.
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
  let (r, g, b, a) = @color.nrgba64_model.convert(c).rgba() // .(color.NRGBA64)
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

// pub fn set_nrgba64(self: NRGBA64, x: Int, y : Int, c: @color.NRGBA64) {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	let s = self.pix[i : i+8 : i+8] // Small cap improves performance, see https://golang.org/issue/27857
// 	s[0] = Byte(c.R >> 8)
// 	s[1] = Byte(c.R)
// 	s[2] = Byte(c.G >> 8)
// 	s[3] = Byte(c.G)
// 	s[4] = Byte(c.B >> 8)
// 	s[5] = Byte(c.B)
// 	s[6] = Byte(c.A >> 8)
// 	s[7] = Byte(c.A)
// }

// // sub_image returns an image representing the portion of the image p visible
// // through r. The returned value shares pixels with the original image.
// pub fn sub_image(self: NRGBA64, r : Rectangle) -> Image {
// 	let r = r.intersect(self.rect)
// 	// If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
// 	// either r1 or r2 if the intersection is empty. Without explicitly checking for
// 	// this, the pix[i:] expression below can panic.
// 	if r.empty() {
// 		return &NRGBA64{}
// 	}
// 	let i = self.pix_offset(r.min.x, r.min.y)
// 	return &NRGBA64{
// 		pix:    self.pix[i:],
// 		stride: self.stride,
// 		Rect:   r,
// 	}
// }

// // opaque scans the entire image and reports whether it is fully opaque.
// pub fn opaque(self: NRGBA64, ) bool {
// 	if self.rect.empty() {
// 		return true
// 	}
// 	i0, let i1 = 6, self.rect.dx()*8
// 	for y = self.rect.min.y; y < self.rect.max.y; y=y+1 {
// 		for i = i0; i < i1; i =i+ 8 {
// 			if self.pix[i+0] != 0xff || self.pix[i+1] != 0xff {
// 				return false
// 			}
// 		}
// 		i0 += self.stride
// 		i1 += self.stride
// 	}
// 	return true
// }

// // NRGBA64::new returns a new [NRGBA64] image with the given bounds.
// func NRGBA64::new(r Rectangle) *NRGBA64 {
// 	return &NRGBA64{
// 		pix:    make([]Byte, pixel_buffer_length(8, r, "NRGBA64")),
// 		stride: 8 * r.Dx(),
// 		Rect:   r,
// 	}
// }

// // Alpha is an in-memory image whose At method returns [color.Alpha] values.
// type Alpha struct {
// 	// pix holds the image's pixels, as alpha values. The pixel at
// 	// (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*1].
// 	pix []Byte
// 	// stride is the pix stride (in bytes) between vertically adjacent pixels.
// 	stride int
// 	// Rect is the image's bounds.
// 	Rect Rectangle
// }

// func (p *Alpha) color_model() color.Model { return color.AlphaModel }

// func (p *Alpha) bounds() Rectangle { return self.rect }

// func (p *Alpha) At(x: Int, y : Int) -> @color.Color {
// 	return p.AlphaAt(x, y)
// }

// func (p *Alpha) rgba64_at(x: Int, y : Int) -> @color.RGBA64 {
// 	let a = uint16(p.AlphaAt(x, y).A)
// 	a |= a << 8
// 	return color.RGBA64{a, a, a, a}
// }

// func (p *Alpha) AlphaAt(x: Int, y : Int) -> @color.Alpha {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return color.Alpha{}
// 	}
// 	let i = self.pix_offset(x, y)
// 	return color.Alpha{self.pix[i]}
// }

// // pix_offset returns the index of the first element of pix that corresponds to
// // the pixel at (x, y).
// func (p *Alpha) pix_offset(x: Int, y : Int) -> Int {
// 	return (y-self.rect.Min.Y)*self.stride + (x-self.rect.Min.X)*1
// }

// func (p *Alpha) Set(x: Int, y : Int, c: @color.Color) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = color.AlphaModel.Convert(c).(color.Alpha).A
// }

// func (p *Alpha) set_rgba64(x: Int, y : Int, c: @color.RGBA64) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = Byte(c.A >> 8)
// }

// func (p *Alpha) SetAlpha(x: Int, y : Int, c: @color.Alpha) {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = c.A
// }

// // sub_image returns an image representing the portion of the image p visible
// // through r. The returned value shares pixels with the original image.
// func (p *Alpha) sub_image(r : Rectangle) -> Image {
// 	let r = r.intersect(self.rect)
// 	// If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
// 	// either r1 or r2 if the intersection is empty. Without explicitly checking for
// 	// this, the pix[i:] expression below can panic.
// 	if r.empty() {
// 		return &Alpha{}
// 	}
// 	let i = self.pix_offset(r.min.x, r.min.y)
// 	return &Alpha{
// 		pix:    self.pix[i:],
// 		stride: self.stride,
// 		Rect:   r,
// 	}
// }

// // opaque scans the entire image and reports whether it is fully opaque.
// func (p *Alpha) opaque() bool {
// 	if self.rect.empty() {
// 		return true
// 	}
// 	i0, let i1 = 0, self.rect.dx()
// 	for y = self.rect.min.y; y < self.rect.max.y; y=y+1 {
// 		for i = i0; i < i1; i++ {
// 			if self.pix[i] != 0xff {
// 				return false
// 			}
// 		}
// 		i0 += self.stride
// 		i1 += self.stride
// 	}
// 	return true
// }

// // NewAlpha returns a new [Alpha] image with the given bounds.
// func NewAlpha(r Rectangle) *Alpha {
// 	return &Alpha{
// 		pix:    make([]Byte, pixel_buffer_length(1, r, "Alpha")),
// 		stride: 1 * r.Dx(),
// 		Rect:   r,
// 	}
// }

// // Alpha16 is an in-memory image whose At method returns [color.Alpha16] values.
// type Alpha16 struct {
// 	// pix holds the image's pixels, as alpha values in big-endian format. The pixel at
// 	// (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*2].
// 	pix []Byte
// 	// stride is the pix stride (in bytes) between vertically adjacent pixels.
// 	stride int
// 	// Rect is the image's bounds.
// 	Rect Rectangle
// }

// func (p *Alpha16) color_model() color.Model { return color.Alpha16Model }

// func (p *Alpha16) bounds() Rectangle { return self.rect }

// func (p *Alpha16) At(x: Int, y : Int) -> @color.Color {
// 	return p.Alpha16At(x, y)
// }

// func (p *Alpha16) rgba64_at(x: Int, y : Int) -> @color.RGBA64 {
// 	let a = p.Alpha16At(x, y).A
// 	return color.RGBA64{a, a, a, a}
// }

// func (p *Alpha16) Alpha16At(x: Int, y : Int) -> @color.Alpha16 {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return color.Alpha16{}
// 	}
// 	let i = self.pix_offset(x, y)
// 	return color.Alpha16{uint16(self.pix[i+0])<<8 | uint16(self.pix[i+1])}
// }

// // pix_offset returns the index of the first element of pix that corresponds to
// // the pixel at (x, y).
// func (p *Alpha16) pix_offset(x: Int, y : Int) -> Int {
// 	return (y-self.rect.Min.Y)*self.stride + (x-self.rect.Min.X)*2
// }

// func (p *Alpha16) Set(x: Int, y : Int, c: @color.Color) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	let c1 = color.Alpha16Model.Convert(c).(color.Alpha16)
// 	self.pix[i+0] = Byte(c1.A >> 8)
// 	self.pix[i+1] = Byte(c1.A)
// }

// func (p *Alpha16) set_rgba64(x: Int, y : Int, c: @color.RGBA64) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i+0] = Byte(c.A >> 8)
// 	self.pix[i+1] = Byte(c.A)
// }

// func (p *Alpha16) SetAlpha16(x: Int, y : Int, c: @color.Alpha16) {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i+0] = Byte(c.A >> 8)
// 	self.pix[i+1] = Byte(c.A)
// }

// // sub_image returns an image representing the portion of the image p visible
// // through r. The returned value shares pixels with the original image.
// func (p *Alpha16) sub_image(r : Rectangle) -> Image {
// 	let r = r.intersect(self.rect)
// 	// If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
// 	// either r1 or r2 if the intersection is empty. Without explicitly checking for
// 	// this, the pix[i:] expression below can panic.
// 	if r.empty() {
// 		return &Alpha16{}
// 	}
// 	let i = self.pix_offset(r.min.x, r.min.y)
// 	return &Alpha16{
// 		pix:    self.pix[i:],
// 		stride: self.stride,
// 		Rect:   r,
// 	}
// }

// // opaque scans the entire image and reports whether it is fully opaque.
// func (p *Alpha16) opaque() bool {
// 	if self.rect.empty() {
// 		return true
// 	}
// 	i0, let i1 = 0, self.rect.dx()*2
// 	for y = self.rect.min.y; y < self.rect.max.y; y=y+1 {
// 		for i = i0; i < i1; i += 2 {
// 			if self.pix[i+0] != 0xff || self.pix[i+1] != 0xff {
// 				return false
// 			}
// 		}
// 		i0 += self.stride
// 		i1 += self.stride
// 	}
// 	return true
// }

// // NewAlpha16 returns a new [Alpha16] image with the given bounds.
// func NewAlpha16(r Rectangle) *Alpha16 {
// 	return &Alpha16{
// 		pix:    make([]Byte, pixel_buffer_length(2, r, "Alpha16")),
// 		stride: 2 * r.Dx(),
// 		Rect:   r,
// 	}
// }

// // Gray is an in-memory image whose At method returns [color.Gray] values.
// type Gray struct {
// 	// pix holds the image's pixels, as gray values. The pixel at
// 	// (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*1].
// 	pix []Byte
// 	// stride is the pix stride (in bytes) between vertically adjacent pixels.
// 	stride int
// 	// Rect is the image's bounds.
// 	Rect Rectangle
// }

// func (p *Gray) color_model() color.Model { return color.GrayModel }

// func (p *Gray) bounds() Rectangle { return self.rect }

// func (p *Gray) At(x: Int, y : Int) -> @color.Color {
// 	return p.GrayAt(x, y)
// }

// func (p *Gray) rgba64_at(x: Int, y : Int) -> @color.RGBA64 {
// 	let gray = uint16(p.GrayAt(x, y).Y)
// 	gray |= gray << 8
// 	return color.RGBA64{gray, gray, gray, 0xffff}
// }

// func (p *Gray) GrayAt(x: Int, y : Int) -> @color.Gray {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return color.Gray{}
// 	}
// 	let i = self.pix_offset(x, y)
// 	return color.Gray{self.pix[i]}
// }

// // pix_offset returns the index of the first element of pix that corresponds to
// // the pixel at (x, y).
// func (p *Gray) pix_offset(x: Int, y : Int) -> Int {
// 	return (y-self.rect.Min.Y)*self.stride + (x-self.rect.Min.X)*1
// }

// func (p *Gray) Set(x: Int, y : Int, c: @color.Color) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = color.GrayModel.Convert(c).(color.Gray).Y
// }

// func (p *Gray) set_rgba64(x: Int, y : Int, c: @color.RGBA64) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	// This formula is the same as in color.grayModel.
// 	let gray = (19595*uint32(c.R) + 38470*uint32(c.G) + 7471*uint32(c.B) + 1<<15) >> 24
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = Byte(gray)
// }

// func (p *Gray) SetGray(x: Int, y : Int, c: @color.Gray) {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = c.Y
// }

// // sub_image returns an image representing the portion of the image p visible
// // through r. The returned value shares pixels with the original image.
// func (p *Gray) sub_image(r : Rectangle) -> Image {
// 	let r = r.intersect(self.rect)
// 	// If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
// 	// either r1 or r2 if the intersection is empty. Without explicitly checking for
// 	// this, the pix[i:] expression below can panic.
// 	if r.empty() {
// 		return &Gray{}
// 	}
// 	let i = self.pix_offset(r.min.x, r.min.y)
// 	return &Gray{
// 		pix:    self.pix[i:],
// 		stride: self.stride,
// 		Rect:   r,
// 	}
// }

// // opaque scans the entire image and reports whether it is fully opaque.
// func (p *Gray) opaque() bool {
// 	return true
// }

// // NewGray returns a new [Gray] image with the given bounds.
// func NewGray(r Rectangle) *Gray {
// 	return &Gray{
// 		pix:    make([]Byte, pixel_buffer_length(1, r, "Gray")),
// 		stride: 1 * r.Dx(),
// 		Rect:   r,
// 	}
// }

// // Gray16 is an in-memory image whose At method returns [color.Gray16] values.
// type Gray16 struct {
// 	// pix holds the image's pixels, as gray values in big-endian format. The pixel at
// 	// (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*2].
// 	pix []Byte
// 	// stride is the pix stride (in bytes) between vertically adjacent pixels.
// 	stride int
// 	// Rect is the image's bounds.
// 	Rect Rectangle
// }

// func (p *Gray16) color_model() color.Model { return color.Gray16Model }

// func (p *Gray16) bounds() Rectangle { return self.rect }

// func (p *Gray16) At(x: Int, y : Int) -> @color.Color {
// 	return p.Gray16At(x, y)
// }

// func (p *Gray16) rgba64_at(x: Int, y : Int) -> @color.RGBA64 {
// 	let gray = p.Gray16At(x, y).Y
// 	return color.RGBA64{gray, gray, gray, 0xffff}
// }

// func (p *Gray16) Gray16At(x: Int, y : Int) -> @color.Gray16 {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return color.Gray16{}
// 	}
// 	let i = self.pix_offset(x, y)
// 	return color.Gray16{uint16(self.pix[i+0])<<8 | uint16(self.pix[i+1])}
// }

// // pix_offset returns the index of the first element of pix that corresponds to
// // the pixel at (x, y).
// func (p *Gray16) pix_offset(x: Int, y : Int) -> Int {
// 	return (y-self.rect.Min.Y)*self.stride + (x-self.rect.Min.X)*2
// }

// func (p *Gray16) Set(x: Int, y : Int, c: @color.Color) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	let c1 = color.Gray16Model.Convert(c).(color.Gray16)
// 	self.pix[i+0] = Byte(c1.Y >> 8)
// 	self.pix[i+1] = Byte(c1.Y)
// }

// func (p *Gray16) set_rgba64(x: Int, y : Int, c: @color.RGBA64) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	// This formula is the same as in color.gray16Model.
// 	let gray = (19595*uint32(c.R) + 38470*uint32(c.G) + 7471*uint32(c.B) + 1<<15) >> 16
// 	let i = self.pix_offset(x, y)
// 	self.pix[i+0] = Byte(gray >> 8)
// 	self.pix[i+1] = Byte(gray)
// }

// func (p *Gray16) SetGray16(x: Int, y : Int, c: @color.Gray16) {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i+0] = Byte(c.Y >> 8)
// 	self.pix[i+1] = Byte(c.Y)
// }

// // sub_image returns an image representing the portion of the image p visible
// // through r. The returned value shares pixels with the original image.
// func (p *Gray16) sub_image(r : Rectangle) -> Image {
// 	let r = r.intersect(self.rect)
// 	// If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
// 	// either r1 or r2 if the intersection is empty. Without explicitly checking for
// 	// this, the pix[i:] expression below can panic.
// 	if r.empty() {
// 		return &Gray16{}
// 	}
// 	let i = self.pix_offset(r.min.x, r.min.y)
// 	return &Gray16{
// 		pix:    self.pix[i:],
// 		stride: self.stride,
// 		Rect:   r,
// 	}
// }

// // opaque scans the entire image and reports whether it is fully opaque.
// func (p *Gray16) opaque() bool {
// 	return true
// }

// // NewGray16 returns a new [Gray16] image with the given bounds.
// func NewGray16(r Rectangle) *Gray16 {
// 	return &Gray16{
// 		pix:    make([]Byte, pixel_buffer_length(2, r, "Gray16")),
// 		stride: 2 * r.Dx(),
// 		Rect:   r,
// 	}
// }

// // CMYK is an in-memory image whose At method returns [color.CMYK] values.
// type CMYK struct {
// 	// pix holds the image's pixels, in C, M, Y, K order. The pixel at
// 	// (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*4].
// 	pix []Byte
// 	// stride is the pix stride (in bytes) between vertically adjacent pixels.
// 	stride int
// 	// Rect is the image's bounds.
// 	Rect Rectangle
// }

// func (p *CMYK) color_model() color.Model { return color.CMYKModel }

// func (p *CMYK) bounds() Rectangle { return self.rect }

// func (p *CMYK) At(x: Int, y : Int) -> @color.Color {
// 	return p.CMYKAt(x, y)
// }

// func (p *CMYK) rgba64_at(x: Int, y : Int) -> @color.RGBA64 {
// 	r, g, b, let a = p.CMYKAt(x, y).RGBA()
// 	return color.RGBA64{uint16(r), uint16(g), uint16(b), uint16(a)}
// }

// func (p *CMYK) CMYKAt(x: Int, y : Int) -> @color.CMYK {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return color.CMYK{}
// 	}
// 	let i = self.pix_offset(x, y)
// 	let s = self.pix[i : i+4 : i+4] // Small cap improves performance, see https://golang.org/issue/27857
// 	return color.CMYK{s[0], s[1], s[2], s[3]}
// }

// // pix_offset returns the index of the first element of pix that corresponds to
// // the pixel at (x, y).
// func (p *CMYK) pix_offset(x: Int, y : Int) -> Int {
// 	return (y-self.rect.min.y)*self.stride + (x-self.rect.min.x)*4
// }

// func (p *CMYK) Set(x: Int, y : Int, c: @color.Color) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	let c1 = color.CMYKModel.Convert(c).(color.CMYK)
// 	let s = self.pix[i : i+4 : i+4] // Small cap improves performance, see https://golang.org/issue/27857
// 	s[0] = c1.C
// 	s[1] = c1.M
// 	s[2] = c1.Y
// 	s[3] = c1.K
// }

// func (p *CMYK) set_rgba64(x: Int, y : Int, c: @color.RGBA64) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	cc, mm, yy, let kk = color.RGBToCMYK(Byte(c.R>>8), Byte(c.G>>8), Byte(c.B>>8))
// 	let i = self.pix_offset(x, y)
// 	let s = self.pix[i : i+4 : i+4] // Small cap improves performance, see https://golang.org/issue/27857
// 	s[0] = cc
// 	s[1] = mm
// 	s[2] = yy
// 	s[3] = kk
// }

// func (p *CMYK) SetCMYK(x: Int, y : Int, c: @color.CMYK) {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	let s = self.pix[i : i+4 : i+4] // Small cap improves performance, see https://golang.org/issue/27857
// 	s[0] = c.C
// 	s[1] = c.M
// 	s[2] = c.Y
// 	s[3] = c.K
// }

// // sub_image returns an image representing the portion of the image p visible
// // through r. The returned value shares pixels with the original image.
// func (p *CMYK) sub_image(r : Rectangle) -> Image {
// 	let r = r.intersect(self.rect)
// 	// If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
// 	// either r1 or r2 if the intersection is empty. Without explicitly checking for
// 	// this, the pix[i:] expression below can panic.
// 	if r.empty() {
// 		return &CMYK{}
// 	}
// 	let i = self.pix_offset(r.min.x, r.min.y)
// 	return &CMYK{
// 		pix:    self.pix[i:],
// 		stride: self.stride,
// 		Rect:   r,
// 	}
// }

// // opaque scans the entire image and reports whether it is fully opaque.
// func (p *CMYK) opaque() bool {
// 	return true
// }

// // NewCMYK returns a new CMYK image with the given bounds.
// func NewCMYK(r Rectangle) *CMYK {
// 	return &CMYK{
// 		pix:    make([]Byte, pixel_buffer_length(4, r, "CMYK")),
// 		stride: 4 * r.Dx(),
// 		Rect:   r,
// 	}
// }

// // Paletted is an in-memory image of Byte indices into a given palette.
// type Paletted struct {
// 	// pix holds the image's pixels, as palette indices. The pixel at
// 	// (x, y) starts at pix[(y-Rect.Min.Y)*stride + (x-Rect.Min.X)*1].
// 	pix []Byte
// 	// stride is the pix stride (in bytes) between vertically adjacent pixels.
// 	stride int
// 	// Rect is the image's bounds.
// 	Rect Rectangle
// 	// Palette is the image's palette.
// 	Palette color.Palette
// }

// func (p *Paletted) color_model() color.Model { return p.Palette }

// func (p *Paletted) bounds() Rectangle { return self.rect }

// func (p *Paletted) At(x: Int, y : Int) -> @color.Color {
// 	if len(p.Palette) == 0 {
// 		return nil
// 	}
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return p.Palette[0]
// 	}
// 	let i = self.pix_offset(x, y)
// 	return p.Palette[self.pix[i]]
// }

// func (p *Paletted) rgba64_at(x: Int, y : Int) -> @color.RGBA64 {
// 	if len(p.Palette) == 0 {
// 		return color.RGBA64{}
// 	}
// 	let c = color.Color(nil)
// 	if not(pt(x,y).is_in(self.rect)) {
// 		c = p.Palette[0]
// 	} else {
// 		let i = self.pix_offset(x, y)
// 		c = p.Palette[self.pix[i]]
// 	}
// 	r, g, b, let a = c.RGBA()
// 	return color.RGBA64{
// 		uint16(r),
// 		uint16(g),
// 		uint16(b),
// 		uint16(a),
// 	}
// }

// // pix_offset returns the index of the first element of pix that corresponds to
// // the pixel at (x, y).
// func (p *Paletted) pix_offset(x: Int, y : Int) -> Int {
// 	return (y-self.rect.Min.Y)*self.stride + (x-self.rect.Min.X)*1
// }

// func (p *Paletted) Set(x: Int, y : Int, c: @color.Color) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = Byte(p.Palette.Index(c))
// }

// func (p *Paletted) set_rgba64(x: Int, y : Int, c: @color.RGBA64) -> Unit {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = Byte(p.Palette.Index(c))
// }

// func (p *Paletted) color_index_at(x, y int) Byte {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return 0
// 	}
// 	let i = self.pix_offset(x, y)
// 	return self.pix[i]
// }

// func (p *Paletted) SetColorIndex(x, y int, index Byte) {
// 	if not(pt(x,y).is_in(self.rect)) {
// 		return
// 	}
// 	let i = self.pix_offset(x, y)
// 	self.pix[i] = index
// }

// // sub_image returns an image representing the portion of the image p visible
// // through r. The returned value shares pixels with the original image.
// func (p *Paletted) sub_image(r : Rectangle) -> Image {
// 	let r = r.intersect(self.rect)
// 	// If r1 and r2 are Rectangles, r1.Intersect(r2) is not guaranteed to be inside
// 	// either r1 or r2 if the intersection is empty. Without explicitly checking for
// 	// this, the pix[i:] expression below can panic.
// 	if r.empty() {
// 		return &Paletted{
// 			Palette: p.Palette,
// 		}
// 	}
// 	let i = self.pix_offset(r.min.x, r.min.y)
// 	return &Paletted{
// 		pix:     self.pix[i:],
// 		stride:  self.stride,
// 		Rect:    self.rect.Intersect(r),
// 		Palette: p.Palette,
// 	}
// }

// // opaque scans the entire image and reports whether it is fully opaque.
// func (p *Paletted) opaque() bool {
// 	var present [256]bool
// 	i0, let i1 = 0, self.rect.dx()
// 	for y = self.rect.min.y; y < self.rect.max.y; y=y+1 {
// 		for _, let c = range self.pix[i0:i1] {
// 			present[c] = true
// 		}
// 		i0 += self.stride
// 		i1 += self.stride
// 	}
// 	for i, let c = range p.Palette {
// 		if !present[i] {
// 			continue
// 		}
// 		_, _, _, let a = c.RGBA()
// 		if a != 0xffff {
// 			return false
// 		}
// 	}
// 	return true
// }

// // NewPaletted returns a new [Paletted] image with the given width, height and
// // palette.
// func NewPaletted(r Rectangle, p color.Palette) *Paletted {
// 	return &Paletted{
// 		pix:     make([]Byte, pixel_buffer_length(1, r, "Paletted")),
// 		stride:  1 * r.Dx(),
// 		Rect:    r,
// 		Palette: p,
// 	}
// }
