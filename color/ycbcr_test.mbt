// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/color/ycbcr_test.go
// which has the copyright notice:
// Copyright 2011 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

fn delta(x : Byte, y : Byte) -> Byte {
  if x >= y {
    return x - y
  }
  return y - x
}

type! EqError String

fn eq(c0 : @color.Color, c1 : @color.Color) -> Unit!EqError {
  let (r0, g0, b0, a0) = c0.rgba()
  let (r1, g1, b1, a1) = c1.rgba()
  if r0 != r1 || g0 != g1 || b0 != b1 || a0 != a1 {
    raise EqError(
      "got (\{r0}, \{g0}, \{b0}, \{a0})\nwant (\{r1}, \{g1}, \{b1}, \{a1})",
    )
  }
}

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

// // TestYCbCrGray tests that YCbCr colors are a superset of Gray colors.
// func TestYCbCrGray(t *testing.T) {
// 	for i := 0; i < 256; i++ {
// 		c0 := YCbCr{uint8(i), 0x80, 0x80}
// 		c1 := Gray{uint8(i)}
// 		if err := eq(c0, c1); err != nil {
// 			t.Errorf("i=0x%02x:\n%v", i, err)
// 		}
// 	}
// }

// // TestNYCbCrAAlpha tests that NYCbCrA colors are a superset of Alpha colors.
// func TestNYCbCrAAlpha(t *testing.T) {
// 	for i := 0; i < 256; i++ {
// 		c0 := NYCbCrA{YCbCr{0xff, 0x80, 0x80}, uint8(i)}
// 		c1 := Alpha{uint8(i)}
// 		if err := eq(c0, c1); err != nil {
// 			t.Errorf("i=0x%02x:\n%v", i, err)
// 		}
// 	}
// }

// // TestNYCbCrAYCbCr tests that NYCbCrA colors are a superset of YCbCr colors.
// func TestNYCbCrAYCbCr(t *testing.T) {
// 	for i := 0; i < 256; i++ {
// 		c0 := NYCbCrA{YCbCr{uint8(i), 0x40, 0xc0}, 0xff}
// 		c1 := YCbCr{uint8(i), 0x40, 0xc0}
// 		if err := eq(c0, c1); err != nil {
// 			t.Errorf("i=0x%02x:\n%v", i, err)
// 		}
// 	}
// }

// // TestCMYKRoundtrip tests that a subset of RGB space can be converted to CMYK
// // and back to within 1/256 tolerance.
// func TestCMYKRoundtrip(t *testing.T) {
// 	for r := 0; r < 256; r += 7 {
// 		for g := 0; g < 256; g += 5 {
// 			for b := 0; b < 256; b += 3 {
// 				r0, g0, b0 := uint8(r), uint8(g), uint8(b)
// 				c, m, y, k := RGBToCMYK(r0, g0, b0)
// 				r1, g1, b1 := CMYKToRGB(c, m, y, k)
// 				if delta(r0, r1) > 1 || delta(g0, g1) > 1 || delta(b0, b1) > 1 {
// 					t.Fatalf("\nr0, g0, b0 = %d, %d, %d\nc, m, y, k = %d, %d, %d, %d\nr1, g1, b1 = %d, %d, %d",
// 						r0, g0, b0, c, m, y, k, r1, g1, b1)
// 				}
// 			}
// 		}
// 	}
// }

// // TestCMYKToRGBConsistency tests that calling the RGBA method (16 bit color)
// // then truncating to 8 bits is equivalent to calling the CMYKToRGB function (8
// // bit color).
// func TestCMYKToRGBConsistency(t *testing.T) {
// 	for c := 0; c < 256; c += 7 {
// 		for m := 0; m < 256; m += 5 {
// 			for y := 0; y < 256; y += 3 {
// 				for k := 0; k < 256; k += 11 {
// 					x := CMYK{uint8(c), uint8(m), uint8(y), uint8(k)}
// 					r0, g0, b0, _ := x.RGBA()
// 					r1, g1, b1 := uint8(r0>>8), uint8(g0>>8), uint8(b0>>8)
// 					r2, g2, b2 := CMYKToRGB(x.C, x.M, x.Y, x.K)
// 					if r1 != r2 || g1 != g2 || b1 != b2 {
// 						t.Fatalf("c, m, y, k = %d, %d, %d, %d\nr1, g1, b1 = %d, %d, %d\nr2, g2, b2 = %d, %d, %d",
// 							c, m, y, k, r1, g1, b1, r2, g2, b2)
// 					}
// 				}
// 			}
// 		}
// 	}
// }

// // TestCMYKGray tests that CMYK colors are a superset of Gray colors.
// func TestCMYKGray(t *testing.T) {
// 	for i := 0; i < 256; i++ {
// 		if err := eq(CMYK{0x00, 0x00, 0x00, uint8(255 - i)}, Gray{uint8(i)}); err != nil {
// 			t.Errorf("i=0x%02x:\n%v", i, err)
// 		}
// 	}
// }

// func TestPalette(t *testing.T) {
// 	p := Palette{
// 		RGBA{0xff, 0xff, 0xff, 0xff},
// 		RGBA{0x80, 0x00, 0x00, 0xff},
// 		RGBA{0x7f, 0x00, 0x00, 0x7f},
// 		RGBA{0x00, 0x00, 0x00, 0x7f},
// 		RGBA{0x00, 0x00, 0x00, 0x00},
// 		RGBA{0x40, 0x40, 0x40, 0x40},
// 	}
// 	// Check that, for a Palette with no repeated colors, the closest color to
// 	// each element is itself.
// 	for i, c := range p {
// 		j := p.Index(c)
// 		if i != j {
// 			t.Errorf("Index(%v): got %d (color = %v), want %d", c, j, p[j], i)
// 		}
// 	}
// 	// Check that finding the closest color considers alpha, not just red,
// 	// green and blue.
// 	got := p.Convert(RGBA{0x80, 0x00, 0x00, 0x80})
// 	want := RGBA{0x7f, 0x00, 0x00, 0x7f}
// 	if got != want {
// 		t.Errorf("got %v, want %v", got, want)
// 	}
// }

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
