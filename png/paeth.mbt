// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/png/paeth.go
// which has the copyright notice:
// Copyright 2012 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
typealias @io.Slice

///|
fn abs(x : Int) -> Int {
  // m = -1 if x < 0. m = 0 otherwise.
  let m = x >> 31

  // In two's complement representation, the negative number
  // of any number (except the smallest one) can be computed
  // by flipping all the bits and add 1. This is faster than
  // code with a branch.
  // See Hacker's Delight, section 2-4.
  (x ^ m) - m
}

///|
// paeth implements the Paeth filter function, as per the PNG specification.
fn paeth(a : Byte, b : Byte, c : Byte) -> Byte {
  // This is an optimized version of the sample code in the PNG spec.
  // For example, the sample code starts with:
  //	p := int(a) + int(b) - int(c)
  //	pa := abs(p - int(a))
  // but the optimized form uses fewer arithmetic operations:
  //	pa := int(b) - int(c)
  //	pa = abs(pa)
  let mut pc = c.to_int()
  let mut pa = b.to_int() - pc
  let mut pb = a.to_int() - pc
  pc = abs(pa + pb)
  pa = abs(pa)
  pb = abs(pb)
  if pa <= pb && pa <= pc {
    return a
  }
  if pb <= pc {
    return b
  }
  c
}

///|
// filter_paeth applies the Paeth filter to the cdat slice.
// cdat is the current row's data, pdat is the previous row's data.
fn filter_paeth(
  cdat : Slice[Byte],
  pdat : Slice[Byte],
  bytes_per_pixel : Int,
) -> Unit {
  let mut a = 0
  let mut b = 0
  let mut c = 0
  let mut pa = 0
  let mut pb = 0
  let mut pc = 0
  for i = 0; i < bytes_per_pixel; i = i + 1 {
    a = 0
    c = 0
    for j = i; j < cdat.length(); j = j + bytes_per_pixel {
      b = pdat[j].to_int()
      pa = b - c
      pb = a - c
      pc = abs(pa + pb)
      pa = abs(pa)
      pb = abs(pb)
      if pa <= pb && pa <= pc {
        // No-op.
      } else if pb <= pc {
        a = b
      } else {
        a = c
      }
      a += cdat[j].to_int()
      a = a & 0xff
      cdat[j] = a.to_byte()
      c = b
    }
  }
}
