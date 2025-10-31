// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/png/writer_test.go
// which has the copyright notice:
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
using @io {type IOError}

///|
fn diff(m0 : &@image.Image, m1 : &@image.Image) -> TestError? {
  let (b0, b1) = (m0.bounds(), m1.bounds())
  if not(b0.size() == b1.size()) {
    return Some(TestError("dimensions differ: \{b0} vs \{b1}"))
  }
  let dx = b1.min.x - b0.min.x
  let dy = b1.min.y - b0.min.y
  for y = b0.min.y; y < b0.max.y; y = y + 1 {
    for x = b0.min.x; x < b0.max.x; x = x + 1 {
      let c0 = m0.at(x, y)
      let c1 = m1.at(x + dx, y + dy)
      let (r0, g0, b0, a0) = c0.rgba()
      let (r1, g1, b1, a1) = c1.rgba()
      if r0 != r1 || g0 != g1 || b0 != b1 || a0 != a1 {
        return Some(TestError("colors differ at (\{x}, \{y}): \{c0} vs \{c1}"))
      }
    }
  }
  None
}

///|
fn encode_decode(m : &@image.Image) -> (&@image.Image, IOError?) {
  let b = @io.Buffer::new()
  guard @png.encode(b, m) is None
  @png.decode(b)
}

///|
fn convert_to_nrgba(m : &@image.Image) -> @image.NRGBA {
  let b = m.bounds()
  let ret = @image.NRGBA::new(b) catch { _ => abort("bad bounds") }
  // draw.draw(ret, b, m, b.min, draw.src)
  for y = b.min.y; y < b.max.y; y = y + 1 {
    for x = b.min.x; x < b.max.x; x = x + 1 {
      let c0 = m.at(x, y)
      ret[@image.pt(x, y)] = c0
    }
  }
  ret
}

///|
struct PalettedTestCase {
  plen : Int
  bitdepth : Byte
  datalen : Int
}

// func TestWriterPaletted(t *testing.T) {

///|
test "writer paletted" {
  let (width, height) = (32, 16)
  let test_cases = [
    { plen: 256, bitdepth: 8, datalen: (1 + width) * height },
    { plen: 128, bitdepth: 8, datalen: (1 + width) * height },
    { plen: 16, bitdepth: 4, datalen: (1 + width / 2) * height },
    { plen: 4, bitdepth: 2, datalen: (1 + width / 4) * height },
    { plen: 2, bitdepth: 1, datalen: (1 + width / 8) * height },
  ]
  for tc in test_cases {
    let test_name = "plen-\{tc.plen}"
    // Create a paletted image with the correct palette length
    let palette = @color.Palette::new(tc.plen)
    for i in 0..<tc.plen {
      let v = i.to_byte()
      palette[i] = @color.NRGBA::new(v, v, v, 255)
    }

    //
    let m0 = @image.Paletted::new(@image.rect(0, 0, width, height), palette)
    let mut i = 0

    //
    for y = 0; y < height; y = y + 1 {
      for x = 0; x < width; x = x + 1 {
        m0.set_color_index(x, y, (i % tc.plen).to_byte())
        i += 1
      }
    }

    // Encode the image
    let b = @io.Buffer::new()
    guard @png.encode(b, m0) is None

    //
    let chunk_fields_length = 12 // 4 bytes for length, name and crc
    let data = Slice::new(b.to_bytes().to_array())
    i = header.length()
    while i < data.length() - chunk_fields_length {
      let length = be_uint32(data[i:i + 4]).reinterpret_as_int()
      let chunk = be_uint32(data[i + 4:i + 8])
      if chunk == be_uint32(Slice::new(b"IHDR".to_array())) {
        let bitdepth = data[i + 8 + 8]
        if bitdepth != tc.bitdepth {
          raise TestError(
            "\{test_name}: got bitdepth \{bitdepth}, want \{tc.bitdepth}",
          )
        }
      } else if chunk == be_uint32(Slice::new(b"IDAT".to_array())) {
        // Uncompress the image data
        guard @zlib.Reader::new(
            @io.Buffer::from_slice(data[i + 8:i + 8 + length]),
          )
          is (r, None)
        let (n, err) = @io.copy(@io.discard, r)
        if err != None {
          raise TestError(
            "\{test_name}: got error while reading image data: \{err}",
          )
        }
        if n != tc.datalen.to_int64() {
          raise TestError(
            "\{test_name}: got uncompressed data length \{n}, want \{tc.datalen}",
          )
        }
      }
      i += chunk_fields_length + length
    }
  }
}

///|
fn be_uint32(b : Slice[Byte]) -> UInt {
  (b[0].to_uint() << 24) |
  (b[1].to_uint() << 16) |
  (b[2].to_uint() << 8) |
  b[3].to_uint()
}

// func Testsub_image(t *testing.T) {

///|
test "sub_image" {
  let mut m0 : &@image.Image = @image.RGBA::new(@image.rect(0, 0, 256, 256))
  for y = 0; y < 256; y = y + 1 {
    for x = 0; x < 256; x = x + 1 {
      m0.set(x, y, @color.RGBA::new(x.to_byte(), y.to_byte(), 0, 255))
    }
  }
  m0 = m0.sub_image(@image.rect(50, 30, 250, 130)) // .(*image.RGBA)
  let (m1, err) = encode_decode(m0)
  match err {
    Some(e) => raise TestError("encode_decode: \{e}")
    _ => ()
  }
  let err = diff(m0, m1)
  match err {
    Some(e) => raise TestError("diff: \{e}")
    _ => ()
  }
}

///|
struct ImageTest {
  name : String
  img : &@image.Image
}

// func TestWriteRGBA(t *testing.T) {

///|
test "write RGBA" {
  let (width, height) = (640, 480)
  let transparent_img = @image.RGBA::new(@image.rect(0, 0, width, height))
  let opaque_img = @image.RGBA::new(@image.rect(0, 0, width, height))
  let mixed_img = @image.RGBA::new(@image.rect(0, 0, width, height))
  let translucent_img = @image.RGBA::new(@image.rect(0, 0, width, height))
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      let opaque_color = @color.RGBA::new(
        x.to_byte(),
        y.to_byte(),
        (y + x).to_byte(),
        255,
      )
      let translucent_color = @color.RGBA::new(
        (x % 128).to_byte(),
        (y % 128).to_byte(),
        ((y + x) % 128).to_byte(),
        128,
      )
      opaque_img.set(x, y, opaque_color)
      translucent_img.set(x, y, translucent_color)
      if y % 2 == 0 {
        mixed_img.set(x, y, opaque_color)
      }
    }
  }

  //
  let test_cases = [
    { name: "Transparent RGBA", img: transparent_img },
    { name: "Opaque RGBA", img: opaque_img },
    { name: "50/50 Transparent/Opaque RGBA", img: mixed_img },
    { name: "RGBA with variable alpha", img: translucent_img },
  ]
  for _, tc in test_cases {
    let m0 = tc.img
    let (m1, err) = encode_decode(m0)
    match err {
      Some(e) => raise TestError("\{tc.name}: encode_decode: \{e}")
      _ => ()
    }
    let err = diff(convert_to_nrgba(m0), m1)
    match err {
      Some(e) => raise TestError("\{tc.name}: diff: \{e}")
      _ => ()
    }
  }
}
