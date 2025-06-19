// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/png/paeth_test.go
// which has the copyright notice:
// Copyright 2012 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
fn slow_abs(x : Int) -> Int {
  if x < 0 {
    return -x
  }
  x
}

///|
// slow_paeth is a slow but simple implementation of the Paeth function.
// It is a straight port of the sample code in the PNG spec, section 9.4.
fn slow_paeth(a : Byte, b : Byte, c : Byte) -> Byte {
  let p = a.to_int() + b.to_int() - c.to_int()
  let pa = slow_abs(p - a.to_int())
  let pb = slow_abs(p - b.to_int())
  let pc = slow_abs(p - c.to_int())
  if pa <= pb && pa <= pc {
    return a
  } else if pb <= pc {
    return b
  }
  c
}

///|
// slow_filter_paeth is a slow but simple implementation of func filter_paeth.
fn slow_filter_paeth(
  cdat : Slice[Byte],
  pdat : Slice[Byte],
  bytes_per_pixel : Int
) -> Unit {
  for i = 0; i < bytes_per_pixel; i = i + 1 {
    cdat[i] += paeth(0, pdat[i], 0)
  }
  for i = bytes_per_pixel; i < cdat.length(); i = i + 1 {
    cdat[i] += paeth(
      cdat[i - bytes_per_pixel],
      pdat[i],
      pdat[i - bytes_per_pixel],
    )
  }
}

///|
suberror TestError String derive(Show)

///|
test "paeth" {
  for a = 0; a < 256; a = a + 15 {
    for b = 0; b < 256; b = b + 15 {
      for c = 0; c < 256; c = c + 15 {
        let got = paeth(a.to_byte(), b.to_byte(), c.to_byte())
        let want = slow_paeth(a.to_byte(), b.to_byte(), c.to_byte())
        if got != want {
          raise TestError(
            "a, b, c = \{a}, \{b}, \{c}: got \{got}, want \{want}",
          )
        }
      }
    }
  }
}

// func BenchmarkPaeth(b *testing.B) {
// 	for i = 0; i < b.N; i++ {
// 		paeth(uint8(i>>16), uint8(i>>8), uint8(i))
// 	}
// }

///|
test "paeth decode" {
  let pdat0 = Slice::new(Array::make(32, b'\x00'))
  let pdat1 = Slice::new(Array::make(32, b'\x00'))
  let pdat2 = Slice::new(Array::make(32, b'\x00'))
  let cdat0 = Slice::new(Array::make(32, b'\x00'))
  let cdat1 = Slice::new(Array::make(32, b'\x00'))
  let cdat2 = Slice::new(Array::make(32, b'\x00'))
  let r = @random.Rand::new(
    generator=@random.chacha8(seed=b"00000000000000000000000000000000"),
  )
  for bytes_per_pixel = 1
      bytes_per_pixel <= 8
      bytes_per_pixel = bytes_per_pixel + 1 {
    for i = 0; i < 100; i = i + 1 {
      for j in 0..<pdat0.length() {
        pdat0[j] = r.int().to_byte()
        cdat0[j] = r.int().to_byte()
      }
      let _ = slice_copy(pdat1, pdat0)
      let _ = slice_copy(pdat2, pdat0)
      let _ = slice_copy(cdat1, cdat0)
      let _ = slice_copy(cdat2, cdat0)
      filter_paeth(cdat1, pdat1, bytes_per_pixel)
      slow_filter_paeth(cdat2, pdat2, bytes_per_pixel)
      let got = cdat1.to_bytes()
      let want = cdat2.to_bytes()
      if got != want {
        raise TestError(
          "bytes_per_pixel: \{bytes_per_pixel}\npdat0: \{dump(pdat0)}\ncdat0: \{dump(cdat0)}\ngot:   \{dump(cdat1)}\nwant:  \{dump(cdat2)}",
        )
      }
    }
  }
}

///|
fn dump(b : Slice[Byte]) -> String {
  b
  .to_bytes()
  .to_array()
  .map(fn(b) { b.to_int() })
  .to_string()
  .replace_all(old=",", new="")
}
