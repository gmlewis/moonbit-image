/// Package color implements a basic color library.
///
/// This package is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/color/color.go
/// which has the copyright notice:
/// Copyright 2011 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.

/// Color can convert itself to alpha-premultiplied 16-bits per channel RGBA.
/// The conversion may be lossy.
pub trait Color {
  // rgba returns the alpha-premultiplied red, green, blue and alpha values
  // for the color. Each value ranges within [0, 0xffff], but is represented
  // by a uint32 so that multiplying by a blend factor up to 0xffff will not
  // overflow.
  //
  // An alpha-premultiplied color component c has been scaled by alpha (a),
  // so has valid values 0 <= c <= a.
  rgba(Self) -> (UInt, UInt, UInt, UInt)
}

impl Show for Color with output(self, logger) {
  // let (r, g, b, a) = self.rgba()
  // logger.write_string("@color.RGBA::{r:\{r},g:\{g},b:\{b},a:\{a}}")
  logger.write_string(self.to_string())
}

pub fn to_string(self : Color) -> String {
  let (r, g, b, a) = self.rgba()
  "@color.RGBA::{r:\{r},g:\{g},b:\{b},a:\{a}}"
}

pub fn op_equal(self : Color, o : Color) -> Bool {
  let (r0, g0, b0, a0) = self.rgba()
  let (r1, g1, b1, a1) = o.rgba()
  r0 == r1 && g0 == g1 && b0 == b1 && a0 == a1
}

/// RGBA represents a traditional 32-bit alpha-premultiplied color, having 8
/// bits for each of red, green, blue and alpha.
///
/// An alpha-premultiplied color component C has been scaled by alpha (A), so
/// has valid values 0 <= C <= A.
pub struct RGBA {
  r : Byte
  g : Byte
  b : Byte
  a : Byte
} derive(Show, Eq)

pub fn RGBA::new(r : Byte, g : Byte, b : Byte, a : Byte) -> RGBA {
  { r, g, b, a }
}

pub fn rgba(self : RGBA) -> (UInt, UInt, UInt, UInt) {
  let r = self.r.to_uint() | (self.r.to_uint() << 8)
  let g = self.g.to_uint() | (self.g.to_uint() << 8)
  let b = self.b.to_uint() | (self.b.to_uint() << 8)
  let a = self.a.to_uint() | (self.a.to_uint() << 8)
  (r, g, b, a)
}

/// RGBA64 represents a 64-bit alpha-premultiplied color, having 16 bits for
/// each of red, green, blue and alpha.
///
/// An alpha-premultiplied color component C has been scaled by alpha (A), so
/// has valid values 0 <= C <= A.
pub struct RGBA64 {
  r : UInt // 16 bits
  g : UInt // 16 bits
  b : UInt // 16 bits
  a : UInt // 16 bits
} derive(Show, Eq)

pub fn RGBA64::new(r : UInt, g : UInt, b : UInt, a : UInt) -> RGBA64 {
  { r, g, b, a }
}

pub fn rgba(self : RGBA64) -> (UInt, UInt, UInt, UInt) {
  (self.r, self.g, self.b, self.a)
}

/// NRGBA represents a non-alpha-premultiplied 32-bit color.
pub struct NRGBA {
  r : Byte
  g : Byte
  b : Byte
  a : Byte
} derive(Show, Eq)

pub fn NRGBA::new(r : Byte, g : Byte, b : Byte, a : Byte) -> NRGBA {
  { r, g, b, a }
}

pub fn rgba(self : NRGBA) -> (UInt, UInt, UInt, UInt) {
  let a = self.a.to_uint()
  let mut r = self.r.to_uint() | (self.r.to_uint() << 8)
  r *= a
  r /= 0xff
  let mut g = self.g.to_uint() | (self.g.to_uint() << 8)
  g *= a
  g /= 0xff
  let mut b = self.b.to_uint() | (self.b.to_uint() << 8)
  b *= a
  b /= 0xff
  let a = a | (a << 8)
  (r, g, b, a)
}

/// NRGBA64 represents a non-alpha-premultiplied 64-bit color,
/// having 16 bits for each of red, green, blue and alpha.
pub struct NRGBA64 {
  r : UInt // 16 bits
  g : UInt // 16 bits
  b : UInt // 16 bits
  a : UInt // 16 bits
} derive(Show, Eq)

pub fn NRGBA64::new(r : UInt, g : UInt, b : UInt, a : UInt) -> NRGBA64 {
  { r, g, b, a }
}

pub fn rgba(self : NRGBA64) -> (UInt, UInt, UInt, UInt) {
  let r = self.r * self.a / 0xffff
  let g = self.g * self.a / 0xffff
  let b = self.b * self.a / 0xffff
  (r, g, b, self.a)
}

/// Alpha represents an 8-bit alpha color.
pub struct Alpha {
  a : Byte
} derive(Show, Eq)

pub fn Alpha::new(a : Byte) -> Alpha {
  { a, }
}

pub fn rgba(self : Alpha) -> (UInt, UInt, UInt, UInt) {
  let a = self.a.to_uint() | (self.a.to_uint() << 8)
  (a, a, a, a)
}

/// Alpha16 represents a 16-bit alpha color.
pub struct Alpha16 {
  a : UInt // 16 bits
} derive(Show, Eq)

pub fn Alpha16::new(a : UInt) -> Alpha16 {
  { a, }
}

pub fn rgba(self : Alpha16) -> (UInt, UInt, UInt, UInt) {
  (self.a, self.a, self.a, self.a)
}

/// Gray represents an 8-bit grayscale color.
pub struct Gray {
  y : Byte
} derive(Show, Eq)

pub fn Gray::new(y : Byte) -> Gray {
  { y, }
}

pub fn rgba(self : Gray) -> (UInt, UInt, UInt, UInt) {
  let y = self.y.to_uint() | (self.y.to_uint() << 8)
  (y, y, y, 0xffff)
}

/// Gray16 represents a 16-bit grayscale color.
pub struct Gray16 {
  y : UInt // 16 bits
} derive(Show, Eq)

pub fn Gray16::new(y : UInt) -> Gray16 {
  { y, }
}

pub fn rgba(self : Gray16) -> (UInt, UInt, UInt, UInt) {
  (self.y, self.y, self.y, 0xffff)
}

/// Model can convert any [Color] to one from its own color model. The conversion
/// may be lossy.
pub trait Model {
  convert(Self, Color) -> Color
}

/// model_func returns a [Model] that invokes f to implement the conversion.
pub fn model_func(f : (Color) -> Color) -> Model {
  // Note: using ModelFunc as the implementation
  // means that callers can still use comparisons
  // like m == RGBAModel. This is not possible if
  // we use the func value directly, because funcs
  // are no longer comparable.
  let mf : ModelFunc = { f, }
  mf
}

struct ModelFunc {
  f : (Color) -> Color
}

pub fn convert(self : ModelFunc, c : Color) -> Color {
  (self.f)(c)
}

/// Models for the standard color types.
pub let rgba_model : Model = model_func(rgba_model_fn)

pub let rgba64_model : Model = model_func(rgba64_model_fn)

pub let nrgba_model : Model = model_func(nrgba_model_fn)

pub let nrgba64_model : Model = model_func(nrgba64_model_fn)

pub let alpha_model : Model = model_func(alpha_model_fn)

pub let alpha16_model : Model = model_func(alpha16_model_fn)

pub let gray_model : Model = model_func(gray_model_fn)

pub let gray16_model : Model = model_func(gray16_model_fn)

fn rgba_model_fn(c : Color) -> Color {
  let (r, g, b, a) = c.rgba()
  let r = (r >> 8).to_byte()
  let g = (g >> 8).to_byte()
  let b = (b >> 8).to_byte()
  let a = (a >> 8).to_byte()
  let c : RGBA = { r, g, b, a }
  c
}

fn rgba64_model_fn(c : Color) -> Color {
  let (r, g, b, a) = c.rgba()
  let c : RGBA64 = { r, g, b, a }
  c
}

fn nrgba_model_fn(c : Color) -> Color {
  let (r, g, b, a) = c.rgba()
  if a == 0xffff {
    let r = (r >> 8).to_byte()
    let g = (g >> 8).to_byte()
    let b = (b >> 8).to_byte()
    let c : NRGBA = { r, g, b, a: 0xff }
    return c
  }
  if a == 0 {
    let c : NRGBA = { r: 0, g: 0, b: 0, a: 0 }
    return c
  }
  // Since Color.RGBA returns an alpha-premultiplied color, we should have r <= a && g <= a && b <= a.
  let r = ((r * 0xffff / a) >> 8).to_byte()
  let g = ((g * 0xffff / a) >> 8).to_byte()
  let b = ((b * 0xffff / a) >> 8).to_byte()
  let a = (a >> 8).to_byte()
  let c : NRGBA = { r, g, b, a }
  c
}

fn nrgba64_model_fn(c : Color) -> Color {
  let (r, g, b, a) = c.rgba()
  if a == 0xffff {
    let c : NRGBA64 = { r, g, b, a: 0xffff }
    return c
  }
  if a == 0 {
    let c : NRGBA64 = { r: 0, g: 0, b: 0, a: 0 }
    return c
  }
  // Since Color.RGBA returns an alpha-premultiplied color, we should have r <= a && g <= a && b <= a.
  let r = r * 0xffff / a
  let g = g * 0xffff / a
  let b = b * 0xffff / a
  let c : NRGBA64 = { r, g, b, a }
  c
}

fn alpha_model_fn(c : Color) -> Color {
  let (_, _, _, a) = c.rgba()
  let a = (a >> 8).to_byte()
  let c : Alpha = { a, }
  c
}

fn alpha16_model_fn(c : Color) -> Color {
  let (_, _, _, a) = c.rgba()
  let c : Alpha16 = { a, }
  c
}

fn gray_model_fn(c : Color) -> Color {
  let (r, g, b, _) = c.rgba()

  // These coefficients (the fractions 0.299, 0.587 and 0.114) are the same
  // as those given by the JFIF specification and used by func RGBToYCbCr in
  // ycbcr.go.
  //
  // Note that 19595 + 38470 + 7471 equals 65536.
  //
  // The 24 is 16 + 8. The 16 is the same as used in RGBToYCbCr. The 8 is
  // because the return value is 8 bit color, not 16 bit color.
  let y = (19595U * r + 38470U * g + 7471U * b + (1U << 15)) >> 24
  let y = y.to_byte()
  let y : Gray = { y, }
  y
}

fn gray16_model_fn(c : Color) -> Color {
  let (r, g, b, _) = c.rgba()

  // These coefficients (the fractions 0.299, 0.587 and 0.114) are the same
  // as those given by the JFIF specification and used by func RGBToYCbCr in
  // ycbcr.go.
  //
  // Note that 19595 + 38470 + 7471 equals 65536.
  let y = (19595U * r + 38470U * g + 7471U * b + (1U << 15)) >> 16
  let y : Gray16 = { y, }
  y
}

/// Palette is a palette of colors.
pub type Palette Array[Color]

/// convert returns the palette color closest to c in Euclidean R,G,B space.
pub fn convert(self : Palette, c : Color) -> Color {
  if self._.length() == 0 {
    return black
  }
  let idx = self.index(c)
  self._[idx]
}

/// index returns the index of the palette color closest to c in Euclidean
/// R,G,B,A space.
pub fn index(self : Palette, c : Color) -> Int {
  // A batch version of this computation is in image/draw/draw.go.

  let (cr, cg, cb, ca) = c.rgba()
  let mut ret = 0
  let mut best_sum = @uint.max_value
  for i, v in self._ {
    let (vr, vg, vb, va) = v.rgba()
    let sum = sq_diff(cr, vr) +
      sq_diff(cg, vg) +
      sq_diff(cb, vb) +
      sq_diff(ca, va)
    if sum < best_sum {
      if sum == 0 {
        return i
      }
      ret = i
      best_sum = sum
    }
  }
  return ret
}

/// sq_diff returns the squared-difference of x and y, shifted by 2 so that
/// adding four of those won't overflow a uint32.
///
/// x and y are both assumed to be in the range [0, 0xffff].
fn sq_diff(x : UInt, y : UInt) -> UInt {
  // The canonical code of this function looks as follows:
  //
  //	var d uint32
  //	if x > y {
  //		d = x - y
  //	} else {
  //		d = y - x
  //	}
  //	return (d * d) >> 2
  //
  // Language spec guarantees the following properties of unsigned integer
  // values operations with respect to overflow/wrap around:
  //
  // > For unsigned integer values, the operations +, -, *, and << are
  // > computed modulo 2n, where n is the bit width of the unsigned
  // > integer's type. Loosely speaking, these unsigned integer operations
  // > discard high bits upon overflow, and programs may rely on ``wrap
  // > around''.
  //
  // Considering these properties and the fact that this function is
  // called in the hot paths (x,y loops), it is reduced to the below code
  // which is slightly faster. See Testsq_diff for correctness check.
  let d = x - y
  (d * d) >> 2
}

/// Standard colors.
pub let black : Gray16 = { y: 0 }

pub let white : Gray16 = { y: 0xffff }

pub let transparent : Alpha16 = { a: 0 }

pub let opaque : Alpha16 = { a: 0xffff }

test "sq_diff" {
  // canonical sqDiff implementation
  let orig = fn(x : UInt, y : UInt) -> UInt {
    let d = if x > y { x - y } else { y - x }
    (d * d) >> 2
  }
  let test_cases = [
    0U, 1, 2, 0x0fffd, 0x0fffe, 0x0ffff, 0x10000, 0x10001, 0x10002, 0xfffffffd, 0xfffffffe,
    0xffffffff,
  ]
  for x in test_cases {
    for y in test_cases {
      let got = sq_diff(x, y)
      let want = orig(x, y)
      assert_eq!(got, want)
    }
  }
}
