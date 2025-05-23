// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/color/ycbcr.go
// which has the copyright notice:
// Copyright 2011 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
/// rgb_to_y_cb_cr converts an RGB triple to a Y'CbCr triple.
pub fn rgb_to_y_cb_cr(r : Byte, g : Byte, b : Byte) -> (Byte, Byte, Byte) {
  // The JFIF specification says:
  //	Y' =  0.2990*R + 0.5870*G + 0.1140*B
  //	Cb = -0.1687*R - 0.3313*G + 0.5000*B + 128
  //	Cr =  0.5000*R - 0.4187*G - 0.0813*B + 128
  // https://www.w3.org/Graphics/JPEG/jfif3.pdf says Y but means Y'.

  let r1 = r.to_int()
  let g1 = g.to_int()
  let b1 = b.to_int()

  // yy is in range [0,0xff].
  //
  // Note that 19595 + 38470 + 7471 equals 65536.
  let yy = (19595 * r1 + 38470 * g1 + 7471 * b1 + (1 << 15)) >> 16

  // The bit twiddling below is equivalent to
  //
  // cb := (-11056*r1 - 21712*g1 + 32768*b1 + 257<<15) >> 16
  // if cb < 0 {
  //     cb = 0
  // } else if cb > 0xff {
  //     cb = ^int32(0)
  // }
  //
  // but uses fewer branches and is faster.
  // Note that the uint8 type conversion in the return
  // statement will convert ^int32(0) to 0xff.
  // The code below to compute cr uses a similar pattern.
  //
  // Note that -11056 - 21712 + 32768 equals 0.
  let mut cb = -11056 * r1 - 21712 * g1 + 32768 * b1 + (257 << 15)
  if (cb.reinterpret_as_uint() & 0xff000000) == 0 {
    cb = cb >> 16
  } else {
    cb = (cb >> 31).lnot()
  }

  // Note that 32768 - 27440 - 5328 equals 0.
  let mut cr = 32768 * r1 - 27440 * g1 - 5328 * b1 + (257 << 15)
  if (cr.reinterpret_as_uint() & 0xff000000) == 0 {
    cr = cr >> 16
  } else {
    cr = (cr >> 31).lnot()
  }
  let yy = yy.to_byte()
  let cb = cb.to_byte()
  let cr = cr.to_byte()
  (yy, cb, cr)
}

///|
/// y_cb_cr_to_rgb converts a Y'CbCr triple to an RGB triple.
pub fn y_cb_cr_to_rgb(y : Byte, cb : Byte, cr : Byte) -> (Byte, Byte, Byte) {
  // The JFIF specification says:
  //	R = Y' + 1.40200*(Cr-128)
  //	G = Y' - 0.34414*(Cb-128) - 0.71414*(Cr-128)
  //	B = Y' + 1.77200*(Cb-128)
  // https://www.w3.org/Graphics/JPEG/jfif3.pdf says Y but means Y'.
  //
  // Those formulae use non-integer multiplication factors. When computing,
  // integer math is generally faster than floating point math. We multiply
  // all of those factors by 1<<16 and round to the nearest integer:
  //	 91881 = roundToNearestInteger(1.40200 * 65536).
  //	 22554 = roundToNearestInteger(0.34414 * 65536).
  //	 46802 = roundToNearestInteger(0.71414 * 65536).
  //	116130 = roundToNearestInteger(1.77200 * 65536).
  //
  // Adding a rounding adjustment in the range [0, 1<<16-1] and then shifting
  // right by 16 gives us an integer math version of the original formulae.
  //	R = (65536*Y' +  91881 *(Cr-128)                  + adjustment) >> 16
  //	G = (65536*Y' -  22554 *(Cb-128) - 46802*(Cr-128) + adjustment) >> 16
  //	B = (65536*Y' + 116130 *(Cb-128)                  + adjustment) >> 16
  // A constant rounding adjustment of 1<<15, one half of 1<<16, would mean
  // round-to-nearest when dividing by 65536 (shifting right by 16).
  // Similarly, a constant rounding adjustment of 0 would mean round-down.
  //
  // Defining YY1 = 65536*Y' + adjustment simplifies the formulae and
  // requires fewer CPU operations:
  //	R = (YY1 +  91881 *(Cr-128)                 ) >> 16
  //	G = (YY1 -  22554 *(Cb-128) - 46802*(Cr-128)) >> 16
  //	B = (YY1 + 116130 *(Cb-128)                 ) >> 16
  //
  // The inputs (y, cb, cr) are 8 bit color, ranging in [0x00, 0xff]. In this
  // function, the output is also 8 bit color, but in the related YCbCr.RGBA
  // method, below, the output is 16 bit color, ranging in [0x0000, 0xffff].
  // Outputting 16 bit color simply requires changing the 16 to 8 in the "R =
  // etc >> 16" equation, and likewise for G and B.
  //
  // As mentioned above, a constant rounding adjustment of 1<<15 is a natural
  // choice, but there is an additional constraint: if c0 := YCbCr{Y: y, Cb:
  // 0x80, Cr: 0x80} and c1 := Gray{Y: y} then c0.RGBA() should equal
  // c1.RGBA(). Specifically, if y == 0 then "R = etc >> 8" should yield
  // 0x0000 and if y == 0xff then "R = etc >> 8" should yield 0xffff. If we
  // used a constant rounding adjustment of 1<<15, then it would yield 0x0080
  // and 0xff80 respectively.
  //
  // Note that when cb == 0x80 and cr == 0x80 then the formulae collapse to:
  //	R = YY1 >> n
  //	G = YY1 >> n
  //	B = YY1 >> n
  // where n is 16 for this function (8 bit color output) and 8 for the
  // YCbCr.RGBA method (16 bit color output).
  //
  // The solution is to make the rounding adjustment non-constant, and equal
  // to 257*Y', which ranges over [0, 1<<16-1] as Y' ranges over [0, 255].
  // YY1 is then defined as:
  //	YY1 = 65536*Y' + 257*Y'
  // or equivalently:
  //	YY1 = Y' * 0x10101
  let yy1 = y.to_int() * 0x10101
  let cb1 = cb.to_int() - 128
  let cr1 = cr.to_int() - 128

  // The bit twiddling below is equivalent to
  //
  // r := (yy1 + 91881*cr1) >> 16
  // if r < 0 {
  //     r = 0
  // } else if r > 0xff {
  //     r = ^int32(0)
  // }
  //
  // but uses fewer branches and is faster.
  // Note that the uint8 type conversion in the return
  // statement will convert ^int32(0) to 0xff.
  // The code below to compute g and b uses a similar pattern.
  let mut r = yy1 + 91881 * cr1
  if (r.reinterpret_as_uint() & 0xff000000) == 0 {
    r = r >> 16
  } else {
    r = (r >> 31).lnot()
  }
  let mut g = yy1 - 22554 * cb1 - 46802 * cr1
  if (g.reinterpret_as_uint() & 0xff000000) == 0 {
    g = g >> 16
  } else {
    g = (g >> 31).lnot()
  }
  let mut b = yy1 + 116130 * cb1
  if (b.reinterpret_as_uint() & 0xff000000) == 0 {
    b = b >> 16
  } else {
    b = (b >> 31).lnot()
  }
  let r = r.to_byte()
  let g = g.to_byte()
  let b = b.to_byte()
  (r, g, b)
}

///|
/// YCbCr represents a fully opaque 24-bit Y'CbCr color, having 8 bits each for
/// one luma and two chroma components.
///
/// JPEG, VP8, the MPEG family and other codecs use this color model. Such
/// codecs often use the terms YUV and Y'CbCr interchangeably, but strictly
/// speaking, the term YUV applies only to analog video signals, and Y' (luma)
/// is Y (luminance) after applying gamma correction.
///
/// Conversion between RGB and Y'CbCr is lossy and there are multiple, slightly
/// different formulae for converting between the two. This package follows
/// the JFIF specification at https://www.w3.org/Graphics/JPEG/jfif3.pdf.
pub(all) struct YCbCr {
  y : Byte
  cb : Byte
  cr : Byte
} derive(Show, Eq)

///|
/// `YCbCr` satisfies the `Color` trait.
let _YCbCr : &Color = YCbCr::new(0, 0, 0)

///|
pub fn YCbCr::new(y : Byte, cb : Byte, cr : Byte) -> YCbCr {
  { y, cb, cr }
}

///|
pub impl Color for YCbCr with model(_self) {
  "YCbCr"
}

///|
pub impl Color for YCbCr with raw(self) {
  (self.y.to_uint(), self.cb.to_uint(), self.cr.to_uint(), 0)
}

///|
pub impl Color for YCbCr with rgba(self) {
  // This code is a copy of the y_cb_cr_to_rgb function above, except that it
  // returns values in the range [0, 0xffff] instead of [0, 0xff]. There is a
  // subtle difference between doing this and having YCbCr satisfy the Color
  // interface by first converting to an RGBA. The latter loses some
  // information by going to and from 8 bits per channel.
  //
  // For example, this code:
  //	const y, cb, cr = 0x7f, 0x7f, 0x7f
  //	r, g, b := color.y_cb_cr_to_rgb(y, cb, cr)
  //	r0, g0, b0, _ := color.YCbCr{y, cb, cr}.RGBA()
  //	r1, g1, b1, _ := color.RGBA{r, g, b, 0xff}.RGBA()
  //	fmt.Printf("0x%04x 0x%04x 0x%04x\n", r0, g0, b0)
  //	fmt.Printf("0x%04x 0x%04x 0x%04x\n", r1, g1, b1)
  // prints:
  //	0x7e18 0x808d 0x7db9
  //	0x7e7e 0x8080 0x7d7d

  let yy1 = self.y.to_int() * 0x10101
  let cb1 = self.cb.to_int() - 128
  let cr1 = self.cr.to_int() - 128

  // The bit twiddling below is equivalent to
  //
  // r := (yy1 + 91881*cr1) >> 8
  // if r < 0 {
  //     r = 0
  // } else if r > 0xff {
  //     r = 0xffff
  // }
  //
  // but uses fewer branches and is faster.
  // The code below to compute g and b uses a similar pattern.
  let mut r = yy1 + 91881 * cr1
  if (r.reinterpret_as_uint() & 0xff000000) == 0 {
    r = r >> 8
  } else {
    r = (r >> 31).lnot() & 0xffff
  }
  let mut g = yy1 - 22554 * cb1 - 46802 * cr1
  if (g.reinterpret_as_uint() & 0xff000000) == 0 {
    g = g >> 8
  } else {
    g = (g >> 31).lnot() & 0xffff
  }
  let mut b = yy1 + 116130 * cb1
  if (b.reinterpret_as_uint() & 0xff000000) == 0 {
    b = b >> 8
  } else {
    b = (b >> 31).lnot() & 0xffff
  }
  let r = r.reinterpret_as_uint()
  let g = g.reinterpret_as_uint()
  let b = b.reinterpret_as_uint()
  (r, g, b, 0xffff)
}

///|
/// y_cb_cr_model is the [Model] for Y'CbCr colors.
pub let y_cb_cr_model : &Model = model_func(y_cb_cr_model_fn, "YCbCr", None)

///|
fn y_cb_cr_model_fn(c : &Color) -> &Color {
  if c.model() == "YCbCr" {
    return c
  }
  let (r, g, b, _) = c.rgba()
  let r = (r >> 8).to_byte()
  let g = (g >> 8).to_byte()
  let b = (b >> 8).to_byte()
  let (y, cb, cr) = rgb_to_y_cb_cr(r, g, b)
  let c : YCbCr = { y, cb, cr }
  c
}

///|
/// NYCbCrA represents a non-alpha-premultiplied Y'CbCr-with-alpha color, having
/// 8 bits each for one luma, two chroma and one alpha component.
pub(all) struct NYCbCrA {
  y : Byte
  cb : Byte
  cr : Byte
  a : Byte
} derive(Show, Eq)

///|
/// `NYCbCrA` satisfies the `Color` trait.
let _NYCbCrA : &Color = NYCbCrA::new(0, 0, 0, 0)

///|
pub fn NYCbCrA::new(y : Byte, cb : Byte, cr : Byte, a : Byte) -> NYCbCrA {
  { y, cb, cr, a }
}

///|
pub impl Color for NYCbCrA with model(_self) {
  "NYCbCrA"
}

///|
pub impl Color for NYCbCrA with raw(self) {
  (self.y.to_uint(), self.cb.to_uint(), self.cr.to_uint(), self.a.to_uint())
}

///|
pub impl Color for NYCbCrA with rgba(self) {
  // The first part of this method is the same as YCbCr.RGBA.
  let yy1 = self.y.to_int() * 0x10101
  let cb1 = self.cb.to_int() - 128
  let cr1 = self.cr.to_int() - 128

  // The bit twiddling below is equivalent to
  //
  // r := (yy1 + 91881*cr1) >> 8
  // if r < 0 {
  //     r = 0
  // } else if r > 0xff {
  //     r = 0xffff
  // }
  //
  // but uses fewer branches and is faster.
  // The code below to compute g and b uses a similar pattern.
  let mut r = yy1 + 91881 * cr1
  if (r.reinterpret_as_uint() & 0xff000000) == 0 {
    r = r >> 8
  } else {
    r = (r >> 31).lnot() & 0xffff
  }
  let mut g = yy1 - 22554 * cb1 - 46802 * cr1
  if (g.reinterpret_as_uint() & 0xff000000) == 0 {
    g = g >> 8
  } else {
    g = (g >> 31).lnot() & 0xffff
  }
  let mut b = yy1 + 116130 * cb1
  if (b.reinterpret_as_uint() & 0xff000000) == 0 {
    b = b >> 8
  } else {
    b = (b >> 31).lnot() & 0xffff
  }

  // The second part of this method applies the alpha.
  let a = self.a.to_uint() * 0x101
  let r = r.reinterpret_as_uint() * a / 0xffff
  let g = g.reinterpret_as_uint() * a / 0xffff
  let b = b.reinterpret_as_uint() * a / 0xffff
  (r, g, b, a)
}

///|
/// n_y_cb_cr_a_model is the [Model] for non-alpha-premultiplied Y'CbCr-with-alpha
/// colors.
pub let n_y_cb_cr_a_model : &Model = model_func(
  n_y_cb_cr_a_model_fn,
  "NYCbCrA",
  None,
)

///|
fn n_y_cb_cr_a_model_fn(c : &Color) -> &Color {
  if c.model() == "NYCbCrA" {
    return c
  }
  let (r, g, b, a) = c.rgba()
  let mut r = r
  let mut g = g
  let mut b = b

  // Convert from alpha-premultiplied to non-alpha-premultiplied.
  if a != 0 {
    r = r * 0xffff / a
    g = g * 0xffff / a
    b = b * 0xffff / a
  }

  //
  let r = (r >> 8).to_byte()
  let g = (g >> 8).to_byte()
  let b = (b >> 8).to_byte()
  let a = (a >> 8).to_byte()
  let (y, cb, cr) = rgb_to_y_cb_cr(r, g, b)
  let c : NYCbCrA = { y, cb, cr, a }
  c
}

///|
/// rgb_to_cmyk converts an RGB triple to a CMYK quadruple.
pub fn rgb_to_cmyk(r : Byte, g : Byte, b : Byte) -> (Byte, Byte, Byte, Byte) {
  let rr = r.to_uint()
  let gg = g.to_uint()
  let bb = b.to_uint()
  let mut w = rr
  if w < gg {
    w = gg
  }
  if w < bb {
    w = bb
  }
  if w == 0 {
    return (0, 0, 0, 0xff)
  }
  let c = ((w - rr) * 0xff / w).to_byte()
  let m = ((w - gg) * 0xff / w).to_byte()
  let y = ((w - bb) * 0xff / w).to_byte()
  let k = (0xffU - w).to_byte()
  (c, m, y, k)
}

///|
/// cmyk_to_rgb converts a [CMYK] quadruple to an RGB triple.
pub fn cmyk_to_rgb(
  c : Byte,
  m : Byte,
  y : Byte,
  k : Byte
) -> (Byte, Byte, Byte) {
  let w = 0xffffU - k.to_uint() * 0x101
  let r = (0xffffU - c.to_uint() * 0x101) * w / 0xffff
  let g = (0xffffU - m.to_uint() * 0x101) * w / 0xffff
  let b = (0xffffU - y.to_uint() * 0x101) * w / 0xffff
  let r = (r >> 8).to_byte()
  let g = (g >> 8).to_byte()
  let b = (b >> 8).to_byte()
  (r, g, b)
}

///|
/// CMYK represents a fully opaque CMYK color, having 8 bits for each of cyan,
/// magenta, yellow and black.
///
/// It is not associated with any particular color profile.
pub(all) struct CMYK {
  c : Byte
  m : Byte
  y : Byte
  k : Byte
} derive(Show, Eq)

///|
/// `CMYK` satisfies the `Color` trait.
let _CMYK : &Color = CMYK::new(0, 0, 0, 0)

///|
pub fn CMYK::new(c : Byte, m : Byte, y : Byte, k : Byte) -> CMYK {
  { c, m, y, k }
}

///|
pub impl Color for CMYK with model(_self) {
  "CMYK"
}

///|
pub impl Color for CMYK with raw(self) {
  (self.c.to_uint(), self.m.to_uint(), self.y.to_uint(), self.k.to_uint())
}

///|
pub impl Color for CMYK with rgba(self) {
  // This code is a copy of the cmyk_to_rgb function above, except that it
  // returns values in the range [0, 0xffff] instead of [0, 0xff].

  let w = 0xffffU - self.k.to_uint() * 0x101
  let r = (0xffffU - self.c.to_uint() * 0x101) * w / 0xffff
  let g = (0xffffU - self.m.to_uint() * 0x101) * w / 0xffff
  let b = (0xffffU - self.y.to_uint() * 0x101) * w / 0xffff
  (r, g, b, 0xffff)
}

///|
/// cmyk_model is the [Model] for CMYK colors.
pub let cmyk_model : &Model = model_func(cmyk_model_fn, "CMYK", None)

///|
fn cmyk_model_fn(c : &Color) -> &Color {
  CMYK::from(c)
}

///|
pub fn CMYK::from(c : &Color) -> CMYK {
  if c.model() == "CMYK" {
    let (c, m, y, k) = c.raw()
    return { c: c.to_byte(), m: m.to_byte(), y: y.to_byte(), k: k.to_byte() }
  }
  let (r, g, b, _) = c.rgba()
  let r = (r >> 8).to_byte()
  let g = (g >> 8).to_byte()
  let b = (b >> 8).to_byte()
  let (c, m, y, k) = rgb_to_cmyk(r, g, b)
  { c, m, y, k }
}
