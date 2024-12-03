// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/image_test.go
// which has the copyright notice:
// Copyright 2011 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
typealias Slice[T] = @io.Slice[T]

///|
typealias Rectangle = @image.Rectangle

///|
typealias Image = @image.Image

///|
typealias SizeError = @image.SizeError

///|
fn cmp(cm : @color.Model, c0 : @color.Color, c1 : @color.Color) -> Bool {
  let (r0, g0, b0, a0) = cm.convert(c0).rgba()
  let (r1, g1, b1, a1) = cm.convert(c1).rgba()
  r0 == r1 && g0 == g1 && b0 == b1 && a0 == a1
}

///|
struct TestT {
  name : String
  image : () -> Image!SizeError
}

///|
let test_images : Array[TestT] = [
  { name: "rgba", image: fn() { @image.RGBA::new!(@image.rect(0, 0, 10, 10)) } },
  {
    name: "rgba64",
    image: fn() { @image.RGBA64::new!(@image.rect(0, 0, 10, 10)) },
  },
  {
    name: "nrgba",
    image: fn() { @image.NRGBA::new!(@image.rect(0, 0, 10, 10)) },
  },
  {
    name: "nrgba64",
    image: fn() { @image.NRGBA64::new!(@image.rect(0, 0, 10, 10)) },
  },
  {
    name: "alpha",
    image: fn() { @image.Alpha::new!(@image.rect(0, 0, 10, 10)) },
  },
  {
    name: "alpha16",
    image: fn() { @image.Alpha16::new!(@image.rect(0, 0, 10, 10)) },
  },
  { name: "gray", image: fn() { @image.Gray::new!(@image.rect(0, 0, 10, 10)) } },
  {
    name: "gray16",
    image: fn() { @image.Gray16::new!(@image.rect(0, 0, 10, 10)) },
  },
  {
    name: "paletted",
    image: fn() {
      @image.Paletted::new!(
        @image.rect(0, 0, 10, 10),
        @color.Palette::from([@color.transparent, @color.opaque]),
      )
    },
  },
]

test "image" {
  for tc in test_images {
    let m = (tc.image)!()
    if not(@image.rect(0, 0, 10, 10) == m.bounds()) {
      raise TestError(
        "\{tc.name}: want bounds \{@image.rect(0,0,10,10)}, got \{m.bounds()}",
      )
      continue
    }
    if not(cmp(m.color_model(), @color.transparent, m.at(6, 3))) {
      raise TestError(
        "\{tc.name}: at (6, 3), want a zero color, got \{m.at(6, 3)}",
      )
      continue
    }
    m.set(6, 3, @color.opaque)
    if not(cmp(m.color_model(), @color.opaque, m.at(6, 3))) {
      raise TestError(
        "\{tc.name}: at (6, 3), want a non-zero color, got \{m.at(6, 3)}",
      )
      continue
    }
    if not(m.sub_image(@image.rect(6, 3, 7, 4)).opaque()) {
      raise TestError("\{tc.name}: at (6, 3) was not opaque")
      continue
    }
    let m = m.sub_image(@image.rect(3, 2, 9, 8))
    if not(@image.rect(3, 2, 9, 8) == m.bounds()) {
      raise TestError(
        "\{tc.name}: sub-image want bounds \{@image.rect(3, 2, 9, 8)}, got \{m.bounds()}",
      )
      continue
    }
    if not(cmp(m.color_model(), @color.opaque, m.at(6, 3))) {
      raise TestError(
        "\{tc.name}: sub-image at (6, 3), want a non-zero color, got \{m.at(6, 3)}",
      )
      continue
    }
    if not(cmp(m.color_model(), @color.transparent, m.at(3, 3))) {
      raise TestError(
        "\{tc.name}: sub-image at (3, 3), want a zero color, got \{m.at(6, 3)}",
      )
      continue
    }
    m.set(3, 3, @color.opaque)
    if not(cmp(m.color_model(), @color.opaque, m.at(3, 3))) {
      raise TestError(
        "\{tc.name}: sub-image at (3, 3), want a non-zero color, got \{m.at(6, 3)}",
      )
      continue
    }
    // Test that taking an empty sub-image starting at a corner does not panic.
    let _ = m.sub_image(@image.rect(0, 0, 0, 0))
    let _ = m.sub_image(@image.rect(10, 0, 10, 0))
    let _ = m.sub_image(@image.rect(0, 10, 0, 10))
    let _ = m.sub_image(@image.rect(10, 10, 10, 10))

  }
}

///|
struct TestR {
  name : String
  f : (Rectangle) -> Image!SizeError
}

// call calls f(r) and reports whether it ran without raising an error.
///|
fn call(f : (Rectangle) -> Image!SizeError, r : Rectangle) -> Bool {
  // defer func() {
  // 	if recover() != nil {
  // 		ok = false
  // 	}
  // }()
  try {
    let _ = f!(r)

  } catch {
    _ => return false
  }
  true
}

test "new xxx bad rectangle" {
  let test_cases = [
    { name: "RGBA", f: fn(r) { @image.RGBA::new!(r) } },
    { name: "RGBA64", f: fn(r) { @image.RGBA64::new!(r) } },
    { name: "NRGBA", f: fn(r) { @image.NRGBA::new!(r) } },
    { name: "NRGBA64", f: fn(r) { @image.NRGBA64::new!(r) } },
    { name: "Alpha", f: fn(r) { @image.Alpha::new!(r) } },
    { name: "Alpha16", f: fn(r) { @image.Alpha16::new!(r) } },
    { name: "Gray", f: fn(r) { @image.Gray::new!(r) } },
    { name: "Gray16", f: fn(r) { @image.Gray16::new!(r) } },
    { name: "CMYK", f: fn(r) { @image.CMYK::new!(r) } },
    {
      name: "Paletted",
      f: fn(r) {
        @image.Paletted::new!(
          r,
          @color.Palette::from([@color.black, @color.white]),
        )
      },
    },
    // {name: "YCbCr", f: fn(r ) { @image.YCbCr::new(r, YCbCrSubsampleRatio422) }},
    // {name: "NYCbCrA", f: fn(r ) { @image.NYCbCrA::new(r, YCbCrSubsampleRatio444) }},
  ]
  for tc in test_cases {
    // Calling NewXxx(r) should fail (panic, since NewXxx doesn't return an
    // error) unless r's width and height are both non-negative.
    for neg_dx in [true, false] {
      for neg_dy in [true, false] {
        let r : Rectangle = { min: @image.pt(15, 28), max: @image.pt(16, 29) }
        if neg_dx {
          r.max.x = 14
        }
        if neg_dy {
          r.max.y = 27
        }
        let got = call(tc.f, r)
        let want = not(neg_dx) && not(neg_dy)
        if got != want {
          raise TestError(
            "\{tc.name}::new: neg_dx=\{neg_dx}, neg_dy=\{neg_dy}: got \{got}, want \{want}",
          )
        }
      }
    }

    // Passing a Rectangle whose width and height is MaxInt should also fail
    // (panic), due to overflow.
    let got = call(
      tc.f,
      Rectangle::{
        min: @image.pt(0, 0),
        max: @image.pt(@int.max_value, @int.max_value),
      },
    )
    if got {
      raise TestError("\{tc.name}::new: overflow: got ok, want !ok")
    }
  }
}

test "16 bits per color channel" {
  let testcolor_model = [
    @color.rgba64_model, @color.nrgba64_model, @color.alpha16_model, @color.gray16_model,
  ]
  for cm in testcolor_model {
    let c = cm.convert(@color.RGBA64::new(0x1234, 0x1234, 0x1234, 0x1234)) // Premultiplied alpha.
    let (r, _, _, _) = c.rgba()
    if r != 0x1234 {
      raise TestError("\{c}: want red value 0x1234 got \{r}")
      continue
    }
  }
  let test_image : Array[Image] = [
    @image.RGBA64::new!(@image.rect(0, 0, 10, 10)),
    @image.NRGBA64::new!(@image.rect(0, 0, 10, 10)),
    @image.Alpha16::new!(@image.rect(0, 0, 10, 10)),
    @image.Gray16::new!(@image.rect(0, 0, 10, 10)),
  ]
  for i, m in test_image {
    m.set(1, 2, @color.NRGBA64::new(0xffff, 0xffff, 0xffff, 0x1357)) // Non-premultiplied alpha.
    let (r, _, _, _) = m.at(1, 2).rgba()
    if r != 0x1357 {
      raise TestError("image #\{i+1}: want red value 0x1357 got \{r}")
      continue
    }
  }
}

// // memset sets every element of s to v.
// fn memset(s : ArrayView[Byte], v : Byte) -> Unit {
//   for i in 0..<s.length() {
//     s[i] = v
//   }
// }

// test "RGBA64 image" {
// 	let r = @image.rect(0, 0, 3, 2)
// 	let test_cases: Array[Image] = [
// 		@image.Alpha::new!(r),
// 		@image.Alpha16::new!(r),
// 		@image.CMYK::new!(r),
// 		@image.Gray::new!(r),
// 		@image.Gray16::new!(r),
// 		@image.NRGBA::new!(r),
// 		@image.NRGBA64::new!(r),
// 		// @image.NYCbCrA::new!(r, YCbCrSubsampleRatio444),
// 		// @image.Paletted::new!(r, palette.Plan9),
// 		@image.RGBA::new!(r),
// 		@image.RGBA64::new!(r),
// 		// @image.Uniform::new!(@color.RGBA64{}),
// 		// @image.YCbCr::new!(r, YCbCrSubsampleRatio444),
// 		r,
//   ]
// 	for tc in test_cases {
//     match tc.model() {
// 		// Most of the concrete image types in the test_cases implement the
// 		// draw.RGBA64Image interface: they have a SetRGBA64 method. We use an
// 		// interface literal here, instead of importing "image/draw", to avoid
// 		// an import cycle.
// 		//
// 		// The YCbCr and NYCbCrA types are special-cased. Chroma subsampling
// 		// means that setting one pixel can modify neighboring pixels. They
// 		// don't have Set or SetRGBA64 methods because that side effect could
// 		// be surprising. Here, we just memset the channel buffers instead.
// 		//
// 		// The Uniform and Rectangle types are also special-cased, as they
// 		// don't have a Set or SetRGBA64 method.
// 		// case interface {
// 		// 	SetRGBA64(x, y int, c @color.RGBA64)
// 		// }:
// 		// 	tc.SetRGBA64(1, 1, @color.RGBA64{0x7FFF, 0x3FFF, 0x0000, 0x7FFF})

// }
// 		"NYCbCrA" => {
// 			memset(tc.YCbCr.Y, 0x77)
// 			memset(tc.YCbCr.Cb, 0x88)
// 			memset(tc.YCbCr.Cr, 0x99)
// 			memset(tc.A, 0xAA)

// }
// 		"Uniform" => {
// 			tc.C = @color.RGBA64{0x7FFF, 0x3FFF, 0x0000, 0x7FFF}

// }
// 		"YCbCr" => {
// 			memset(tc.Y, 0x77)
// 			memset(tc.Cb, 0x88)
// 			memset(tc.Cr, 0x99)

// 		case Rectangle:
// 			// No-op. Rectangle pixels' colors are immutable. They're always
// 			// @color.Opaque.

// 		default:
// 			raise TestError("could not initialize pixels for %T", tc)
// 			continue
// 		}

// 		// Check that RGBA64At(x, y) is equivalent to At(x, y).rgba().
// 		rgba64Image, ok := tc.(RGBA64Image)
// 		if not(ok ) {
// 			raise TestError("%T is not an RGBA64Image", tc)
// 			continue
// 		}
// 		got := rgba64Image.RGBA64At(1, 1)
// 		wantR, wantG, wantB, wantA := tc.At(1, 1).rgba()
// 		if (uint32(got.R) != wantR) || (uint32(got.G) != wantG) ||
// 			(uint32(got.B) != wantB) || (uint32(got.A) != wantA) {
// 			raise TestError("%T:\ngot  (0x%04X, 0x%04X, 0x%04X, 0x%04X)\n"+
// 				"want (0x%04X, 0x%04X, 0x%04X, 0x%04X)", tc,
// 				got.R, got.G, got.B, got.A,
// 				wantR, wantG, wantB, wantA)
// 			continue
// 		}
// 	}
// }

// func BenchmarkAt(b *testing.B) {
// 	for _, tc := range test_images {
// 		b.Run(tc.name, func(b *testing.B) {
// 			m := tc.image()
// 			b.ReportAllocs()
// 			b.ResetTimer()
// 			for i := 0; i < b.N; i++ {
// 				m.at(4, 5)
// 			}
// 		})
// 	}
// }

// func BenchmarkSet(b *testing.B) {
// 	c := @color.Gray{0xff}
// 	for _, tc := range test_images {
// 		b.Run(tc.name, func(b *testing.B) {
// 			m := tc.image()
// 			b.ReportAllocs()
// 			b.ResetTimer()
// 			for i := 0; i < b.N; i++ {
// 				m.Set(4, 5, c)
// 			}
// 		})
// 	}
// }

// func BenchmarkRGBAAt(b *testing.B) {
// 	m := NewRGBA(@image.rect(0, 0, 10, 10))
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.RGBAAt(4, 5)
// 	}
// }

// func BenchmarkRGBASetRGBA(b *testing.B) {
// 	m := NewRGBA(@image.rect(0, 0, 10, 10))
// 	c := @color.RGBA{0xff, 0xff, 0xff, 0x13}
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.SetRGBA(4, 5, c)
// 	}
// }

// func BenchmarkRGBA64At(b *testing.B) {
// 	m := NewRGBA64(@image.rect(0, 0, 10, 10))
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.RGBA64At(4, 5)
// 	}
// }

// func BenchmarkRGBA64SetRGBA64(b *testing.B) {
// 	m := NewRGBA64(@image.rect(0, 0, 10, 10))
// 	c := @color.RGBA64{0xffff, 0xffff, 0xffff, 0x1357}
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.SetRGBA64(4, 5, c)
// 	}
// }

// func BenchmarkNRGBAAt(b *testing.B) {
// 	m := NewNRGBA(@image.rect(0, 0, 10, 10))
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.NRGBAAt(4, 5)
// 	}
// }

// func BenchmarkNRGBASetNRGBA(b *testing.B) {
// 	m := NewNRGBA(@image.rect(0, 0, 10, 10))
// 	c := @color.NRGBA{0xff, 0xff, 0xff, 0x13}
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.SetNRGBA(4, 5, c)
// 	}
// }

// func BenchmarkNRGBA64At(b *testing.B) {
// 	m := NewNRGBA64(@image.rect(0, 0, 10, 10))
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.NRGBA64At(4, 5)
// 	}
// }

// func BenchmarkNRGBA64SetNRGBA64(b *testing.B) {
// 	m := NewNRGBA64(@image.rect(0, 0, 10, 10))
// 	c := @color.NRGBA64{0xffff, 0xffff, 0xffff, 0x1357}
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.SetNRGBA64(4, 5, c)
// 	}
// }

// func BenchmarkAlphaAt(b *testing.B) {
// 	m := NewAlpha(@image.rect(0, 0, 10, 10))
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.AlphaAt(4, 5)
// 	}
// }

// func BenchmarkAlphaSetAlpha(b *testing.B) {
// 	m := NewAlpha(@image.rect(0, 0, 10, 10))
// 	c := @color.Alpha{0x13}
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.SetAlpha(4, 5, c)
// 	}
// }

// func BenchmarkAlpha16At(b *testing.B) {
// 	m := NewAlpha16(@image.rect(0, 0, 10, 10))
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.Alpha16At(4, 5)
// 	}
// }

// func BenchmarkAlphaSetAlpha16(b *testing.B) {
// 	m := NewAlpha16(@image.rect(0, 0, 10, 10))
// 	c := @color.Alpha16{0x13}
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.SetAlpha16(4, 5, c)
// 	}
// }

// func BenchmarkGrayAt(b *testing.B) {
// 	m := NewGray(@image.rect(0, 0, 10, 10))
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.GrayAt(4, 5)
// 	}
// }

// func BenchmarkGraySetGray(b *testing.B) {
// 	m := NewGray(@image.rect(0, 0, 10, 10))
// 	c := @color.Gray{0x13}
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.SetGray(4, 5, c)
// 	}
// }

// func BenchmarkGray16At(b *testing.B) {
// 	m := NewGray16(@image.rect(0, 0, 10, 10))
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.Gray16At(4, 5)
// 	}
// }

// func BenchmarkGraySetGray16(b *testing.B) {
// 	m := NewGray16(@image.rect(0, 0, 10, 10))
// 	c := @color.Gray16{0x13}
// 	b.ResetTimer()

// 	for i := 0; i < b.N; i++ {
// 		m.SetGray16(4, 5, c)
// 	}
// }
