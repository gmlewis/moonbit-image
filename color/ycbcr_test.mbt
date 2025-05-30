// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/color/ycbcr_test.go
// which has the copyright notice:
// Copyright 2011 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
fn delta(x : Byte, y : Byte) -> Byte {
  if x >= y {
    return x - y
  }
  return y - x
}

///|
type! EqError String derive(Show)

///|
fn eq(c0 : &@color.Color, c1 : &@color.Color) -> EqError? {
  let (r0, g0, b0, a0) = c0.rgba()
  let (r1, g1, b1, a1) = c1.rgba()
  if r0 != r1 || g0 != g1 || b0 != b1 || a0 != a1 {
    return Some(
      EqError(
        "got (\{r0}, \{g0}, \{b0}, \{a0})\nwant (\{r1}, \{g1}, \{b1}, \{a1})",
      ),
    )
  }
  None
}

///|
test "a subset of RGB space can be converted to YCbCr and back to within 2/256 tolerance" {
  // func TestYCbCrRoundtrip(t *testing.T) {
  for r = 0; r < 256; r = r + 7 {
    for g = 0; g < 256; g = g + 5 {
      for b = 0; b < 256; b = b + 3 {
        let (r0, g0, b0) = (r.to_byte(), g.to_byte(), b.to_byte())
        let (y, cb, cr) = @color.rgb_to_y_cb_cr(r0, g0, b0)
        let (r1, g1, b1) = @color.y_cb_cr_to_rgb(y, cb, cr)
        if delta(r0, r1) > 2 || delta(g0, g1) > 2 || delta(b0, b1) > 2 {
          raise EqError(
            "\nr0, g0, b0 = \{r0}, \{g0}, \{b0}\ny,  cb, cr = \{y}, \{cb}, \{cr}\nr1, g1, b1 = \{r1}, \{g1}, \{b1}",
          )
        }
      }
    }
  }
}

///|
test "calling the RGBA method (16 bit color) then truncating to 8 bits is equivalent to calling the YCbCrToRGB function (8 bit color)" {
  // func TestYCbCrToRGBConsistency(t *testing.T) {
  for y = 0; y < 256; y = y + 7 {
    for cb = 0; cb < 256; cb = cb + 5 {
      for cr = 0; cr < 256; cr = cr + 3 {
        let x : @color.YCbCr = {
          y: y.to_byte(),
          cb: cb.to_byte(),
          cr: cr.to_byte(),
        }
        let (r0, g0, b0, _) = x.rgba()
        let (r1, g1, b1) = (
          (r0 >> 8).to_byte(),
          (g0 >> 8).to_byte(),
          (b0 >> 8).to_byte(),
        )
        let (r2, g2, b2) = @color.y_cb_cr_to_rgb(x.y, x.cb, x.cr)
        if r1 != r2 || g1 != g2 || b1 != b2 {
          raise EqError(
            "y, cb, cr = \{y}, \{cb}, \{cr}\nr1, g1, b1 = \{r1}, \{g1}, \{b1}\nr2, g2, b2 = \{r2}, \{g2}, \{b2}",
          )
        }
      }
    }
  }
}

///|
test "YCbCr colors are a superset of Gray colors" {
  // func TestYCbCrGray(t *testing.T) {
  for i = 0; i < 256; i = i + 1 {
    let c0 : @color.YCbCr = { y: i.to_byte(), cb: 0x80, cr: 0x80 }
    let c1 : @color.Gray = { y: i.to_byte() }
    let err = eq(c0, c1)
    guard err is None else { raise EqError("i=\{i}:\n\{err}") }
  }
}

///|
test "NYCbCrA colors are a superset of Alpha colors" {
  // func TestNYCbCrAAlpha(t *testing.T) {
  for i = 0; i < 256; i = i + 1 {
    let c0 : @color.NYCbCrA = { y: 0xff, cb: 0x80, cr: 0x80, a: i.to_byte() }
    let c1 : @color.Alpha = { a: i.to_byte() }
    let err = eq(c0, c1)
    guard err is None else { raise EqError("i=\{i}:\n\{err}") }
  }
}

///|
test "NYCbCrA colors are a superset of YCbCr colors" {
  // func TestNYCbCrAYCbCr(t *testing.T) {
  for i = 0; i < 256; i = i + 1 {
    let c0 : @color.NYCbCrA = { y: i.to_byte(), cb: 0x40, cr: 0xc0, a: 0xff }
    let c1 : @color.YCbCr = { y: i.to_byte(), cb: 0x40, cr: 0xc0 }
    let err = eq(c0, c1)
    guard err is None else { raise EqError("i=\{i}:\n\{err}") }
  }
}

///|
test "a subset of RGB space can be converted to CMYK and back to within 1/256 tolerance" {
  // func TestCMYKRoundtrip(t *testing.T) {
  for r = 0; r < 256; r = r + 7 {
    for g = 0; g < 256; g = g + 5 {
      for b = 0; b < 256; b = b + 3 {
        let (r0, g0, b0) = (r.to_byte(), g.to_byte(), b.to_byte())
        let (c, m, y, k) = @color.rgb_to_cmyk(r0, g0, b0)
        let (r1, g1, b1) = @color.cmyk_to_rgb(c, m, y, k)
        if delta(r0, r1) > 1 || delta(g0, g1) > 1 || delta(b0, b1) > 1 {
          raise EqError(
            "\nr0, g0, b0 = \{r0.to_int()}, \{g0.to_int()}, \{b0.to_int()}\nc, m, y, k = \{c.to_int()}, \{m.to_int()}, \{y.to_int()}, \{k.to_int()}\nr1, g1, b1 = \{r1.to_int()}, \{g1.to_int()}, \{b1.to_int()}",
          )
        }
      }
    }
  }
}

///|
test "calling the RGBA method (16 bit color) then truncating to 8 bits is equivalent to calling the CMYKToRGB function (8 bit color)" {
  // func TestCMYKToRGBConsistency(t *testing.T) {
  for c = 0; c < 256; c = c + 7 {
    for m = 0; m < 256; m = m + 5 {
      for y = 0; y < 256; y = y + 3 {
        for k = 0; k < 256; k = k + 11 {
          let x : @color.CMYK = {
            c: c.to_byte(),
            m: m.to_byte(),
            y: y.to_byte(),
            k: k.to_byte(),
          }
          let (r0, g0, b0, _) = x.rgba()
          let (r1, g1, b1) = (
            (r0 >> 8).to_byte(),
            (g0 >> 8).to_byte(),
            (b0 >> 8).to_byte(),
          )
          let (r2, g2, b2) = @color.cmyk_to_rgb(x.c, x.m, x.y, x.k)
          if r1 != r2 || g1 != g2 || b1 != b2 {
            raise EqError(
              "c, m, y, k = \{c}, \{m}, \{y}, \{k}\nr1, g1, b1 = \{r1}, \{g1}, \{b1}\nr2, g2, b2 = \{r2}, \{g2}, \{b2}",
            )
          }
        }
      }
    }
  }
}

///|
test "CMYK colors are a superset of Gray colors" {
  // func TestCMYKGray(t *testing.T) {
  for i = 0; i < 256; i = i + 1 {
    let c0 : @color.CMYK = { c: 0, m: 0, y: 0, k: (255 - i).to_byte() }
    let c1 : @color.Gray = { y: i.to_byte() }
    let err = eq(c0, c1)
    guard err is None else { raise EqError("i=\{i}:\n\{err}") }
  }
}

///|
test "palette" {
  // func TestPalette(t *testing.T) {
  let p = @color.Palette::from([
    @color.RGBA::new(0xff, 0xff, 0xff, 0xff),
    @color.RGBA::new(0x80, 0x00, 0x00, 0xff),
    @color.RGBA::new(0x7f, 0x00, 0x00, 0x7f),
    @color.RGBA::new(0x00, 0x00, 0x00, 0x7f),
    @color.RGBA::new(0x00, 0x00, 0x00, 0x00),
    @color.RGBA::new(0x40, 0x40, 0x40, 0x40),
  ])
  // Check that, for a Palette with no repeated colors, the closest color to
  // each element is itself.
  for i, c in p._ {
    let j = p.index(c)
    if i != j {
      raise EqError("Index(\{c}): got \{j} (color = \{p._[j]}), want \{i}")
    }
  }
  // Check that finding the closest color considers alpha, not just red,
  // green and blue.
  let got = p.convert(@color.RGBA::new(0x80, 0x00, 0x00, 0x80))
  let want = @color.RGBA::new(0x7f, 0x00, 0x00, 0x7f)
  if got != want {
    raise EqError("got \{got}, want \{want}")
  }
}

// var sink8 uint8
// var sink32 uint32

// func BenchmarkYCbCrToRGB(b *testing.B) {
// 	// YCbCrToRGB does saturating arithmetic.
// 	// Low, middle, and high values can take
// 	// different paths through the generated code.
// 	b.Run("0", func(b *testing.B) {
// 		for i := 0; i < b.N; i++ {
// 			sink8, sink8, sink8 = YCbCrToRGB(0, 0, 0)
// 		}
// 	})
// 	b.Run("128", func(b *testing.B) {
// 		for i := 0; i < b.N; i++ {
// 			sink8, sink8, sink8 = YCbCrToRGB(128, 128, 128)
// 		}
// 	})
// 	b.Run("255", func(b *testing.B) {
// 		for i := 0; i < b.N; i++ {
// 			sink8, sink8, sink8 = YCbCrToRGB(255, 255, 255)
// 		}
// 	})
// }

// func BenchmarkRGBToYCbCr(b *testing.B) {
// 	// RGBToYCbCr does saturating arithmetic.
// 	// Different values can take different paths
// 	// through the generated code.
// 	b.Run("0", func(b *testing.B) {
// 		for i := 0; i < b.N; i++ {
// 			sink8, sink8, sink8 = RGBToYCbCr(0, 0, 0)
// 		}
// 	})
// 	b.Run("Cb", func(b *testing.B) {
// 		for i := 0; i < b.N; i++ {
// 			sink8, sink8, sink8 = RGBToYCbCr(0, 0, 255)
// 		}
// 	})
// 	b.Run("Cr", func(b *testing.B) {
// 		for i := 0; i < b.N; i++ {
// 			sink8, sink8, sink8 = RGBToYCbCr(255, 0, 0)
// 		}
// 	})
// }

// func BenchmarkYCbCrToRGBA(b *testing.B) {
// 	// RGB does saturating arithmetic.
// 	// Low, middle, and high values can take
// 	// different paths through the generated code.
// 	b.Run("0", func(b *testing.B) {
// 		c := YCbCr{0, 0, 0}
// 		for i := 0; i < b.N; i++ {
// 			sink32, sink32, sink32, sink32 = c.RGBA()
// 		}
// 	})
// 	b.Run("128", func(b *testing.B) {
// 		c := YCbCr{128, 128, 128}
// 		for i := 0; i < b.N; i++ {
// 			sink32, sink32, sink32, sink32 = c.RGBA()
// 		}
// 	})
// 	b.Run("255", func(b *testing.B) {
// 		c := YCbCr{255, 255, 255}
// 		for i := 0; i < b.N; i++ {
// 			sink32, sink32, sink32, sink32 = c.RGBA()
// 		}
// 	})
// }

// func BenchmarkNYCbCrAToRGBA(b *testing.B) {
// 	// RGBA does saturating arithmetic.
// 	// Low, middle, and high values can take
// 	// different paths through the generated code.
// 	b.Run("0", func(b *testing.B) {
// 		c := NYCbCrA{YCbCr{0, 0, 0}, 0xff}
// 		for i := 0; i < b.N; i++ {
// 			sink32, sink32, sink32, sink32 = c.RGBA()
// 		}
// 	})
// 	b.Run("128", func(b *testing.B) {
// 		c := NYCbCrA{YCbCr{128, 128, 128}, 0xff}
// 		for i := 0; i < b.N; i++ {
// 			sink32, sink32, sink32, sink32 = c.RGBA()
// 		}
// 	})
// 	b.Run("255", func(b *testing.B) {
// 		c := NYCbCrA{YCbCr{255, 255, 255}, 0xff}
// 		for i := 0; i < b.N; i++ {
// 			sink32, sink32, sink32, sink32 = c.RGBA()
// 		}
// 	})
// }
