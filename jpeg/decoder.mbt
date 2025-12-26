///|
/// Package jpeg implements a JPEG image decoder.
///
/// The JPEG specification is at ITU T.81.
/// The JFIF specification is at https://www.w3.org/Graphics/JPEG/jfif3.pdf.
///
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/jpeg/reader.go
/// which has the copyright notice:
/// Copyright 2011 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.

///|
// JPEG markers

///|
const SOI : Int = 0xD8 // Start of Image

///|
const SOF0 : Int = 0xC0 // Start of Frame (baseline DCT)

///|
const SOF1 : Int = 0xC1 // Start of Frame (extended sequential DCT)

///|
const SOF2 : Int = 0xC2 // Start of Frame (progressive DCT)

///|
const DHT : Int = 0xC4 // Define Huffman Table

///|
const SOF3 : Int = 0xC3 // Start of Frame (lossless)

///|
const DQT : Int = 0xDB // Define Quantization Table

///|
const DRI : Int = 0xDD // Define Restart Interval

///|
const SOS : Int = 0xDA // Start of Scan

///|
const RST0 : Int = 0xD0 // Restart 0

///|
const RST1 : Int = 0xD1 // Restart 1

///|
const RST2 : Int = 0xD2 // Restart 2

///|
const RST3 : Int = 0xD3 // Restart 3

///|
const RST4 : Int = 0xD4 // Restart 4

///|
const RST5 : Int = 0xD5 // Restart 5

///|
const RST6 : Int = 0xD6 // Restart 6

///|
const RST7 : Int = 0xD7 // Restart 7

///|
const APP0 : Int = 0xE0 // Application 0 (JFIF)

///|
const APP1 : Int = 0xE1 // Application 1 (EXIF)

///|
const APP2 : Int = 0xE2 // Application 2

///|
const APP3 : Int = 0xE3 // Application 3

///|
const APP4 : Int = 0xE4 // Application 4

///|
const APP5 : Int = 0xE5 // Application 5

///|
const APP6 : Int = 0xE6 // Application 6

///|
const APP7 : Int = 0xE7 // Application 7

///|
const APP8 : Int = 0xE8 // Application 8

///|
const APP9 : Int = 0xE9 // Application 9

///|
const APPA : Int = 0xEA // Application 10

///|
const APPB : Int = 0xEB // Application 11

///|
const APPC : Int = 0xEC // Application 12

///|
const APPD : Int = 0xED // Application 13

///|
const APPE : Int = 0xEE // Application 14

///|
const APPF : Int = 0xEF // Application 15

///|
const COM : Int = 0xFE // Comment

///|
const EOI : Int = 0xD9 // End of Image

///|
using @io {type Slice}

// Decoder struct

///|
struct Decoder {
  r : &@io.Reader
  mut width : Int
  mut height : Int
  mut bits : Int // bits per component
  mut ncomp : Int // number of components
  mut comp : Array[Component] // component info
  mut prev_dc : Array[Int]
  qtab : Array[Array[Int]] // quantization tables
  htab : Array[HuffmanTable] // huffman tables
  mut restart_interval : Int
  mut progressive : Bool
  mut bit_curr : Int
  mut bits_left : Int
  img : &@image.Image
  mut marker : Int
}

// Component info

///|
struct Component {
  h : Int // horizontal sampling factor
  v : Int // vertical sampling factor
  c : Int // component identifier
  tq : Int // quantization table destination selector
  mut dctbl : Int
  mut actbl : Int
} derive(Default)

// Huffman table

///|
struct HuffmanTable {
  class : Int
  id : Int
  lengths : Array[Int]
  symbols : Array[Int]
  // runtime lookup tables built from lengths+symbols
  lut : Array[Array[Int]]
  min_len : Int
  max_len : Int
}

///|
fn Decoder::new(r : &@io.Reader) -> Decoder {
  {
    r,
    width: 0,
    height: 0,
    bits: 0,
    ncomp: 0,
    comp: Array::new(),
    prev_dc: Array::new(),
    qtab: Array::new(),
    htab: Array::new(),
    restart_interval: 0,
    progressive: false,
    bit_curr: 0,
    bits_left: 0,
    img: &@image.Image::new_empty(),
    marker: -1,
  }
}

///|
pub fn decode(r : &@io.Reader) -> (&@image.Image, @io.IOError?) {
  let d = Decoder::new(r)
  d.decode()
}

///|
fn Decoder::decode(self : Decoder) -> (&@image.Image, @io.IOError?) {
  // Read SOI
  let (marker_byte, err) = self.read_marker()
  if err != None {
    return (self.img, err)
  }
  let marker = marker_byte
  if marker != SOI {
    return (self.img, Some(@io.IOError("missing SOI")))
  }

  // Parse markers until SOS
  let mut done = false
  while !done {
    let (marker_byte, err) = self.read_marker()
    if err != None {
      return (self.img, err)
    }
    let marker = marker_byte
    match marker {
      SOF0 =>
        match self.parse_sof0() {
          Some(err) => return (self.img, Some(err))
          None => ()
        }
      DQT =>
        match self.parse_dqt() {
          Some(err) => return (self.img, Some(err))
          None => ()
        }
      DHT =>
        match self.parse_dht() {
          Some(err) => return (self.img, Some(err))
          None => ()
        }
      DRI =>
        match self.parse_dri() {
          Some(err) => return (self.img, Some(err))
          None => ()
        }
      SOS =>
        // Parse Start Of Scan header then decode the entropy-coded data
        match self.parse_sos() {
          Some(err) => return (self.img, Some(err))
          None => done = true
        }
      EOI => return (self.img, Some(@io.IOError("unexpected EOI")))
      _ =>
        // Skip other markers
        match self.skip_marker() {
          Some(err) => return (self.img, Some(err))
          None => ()
        }
    }
  }

  // Decode scan header and entropy-coded data
  match self.decode_scan() {
    Some(err) => return (self.img, Some(err))
    None => ()
  }
  (self.img, None)
}

///|
fn Decoder::parse_sos(self : Decoder) -> @io.IOError? {
  let (length, err) = self.read_u16be()
  if err != None {
    return err
  }
  let (ncomp_byte, err) = self.read_byte()
  if err != None {
    return err
  }
  let ncomp = ncomp_byte + 0
  // Read component selectors
  for _ in 0..<(ncomp + 0) {
    let (c, err) = self.read_byte()
    if err != None {
      return err
    }
    let (sel, err) = self.read_byte()
    if err != None {
      return err
    }
    // sel: upper 4 bits = DC table selector, lower 4 bits = AC table selector
    let dct = (sel >> 4) & 0xF
    let act = sel & 0xF
    // find matching component and set table selectors
    for i in 0..<self.comp.length() {
      if self.comp[i].c == c {
        self.comp[i].dctbl = dct + 0
        self.comp[i].actbl = act + 0
        break
      }
    }
  }
  // Ss, Se, AhAl
  let (_, err1) = self.read_byte()
  if err1 != None {
    return err1
  }
  let (_, err2) = self.read_byte()
  if err2 != None {
    return err2
  }
  let (_, err3) = self.read_byte()
  if err3 != None {
    return err3
  }
  None
}

///|
fn Decoder::read_marker(self : Decoder) -> (Int, @io.IOError?) {
  // Read 0xFF
  match self.read_byte() {
    (0xFF, None) => ()
    (_, err) => return (0, err)
  }
  // Read marker byte
  let (b, err) = self.read_byte()
  (b, err)
}

///|
fn Decoder::read_byte(self : Decoder) -> (Int, @io.IOError?) {
  // Read a single byte using io.read_full so this works with plain io.Reader
  let b = Slice::new(Array::make(1, b'\x00'))
  let (_, err) = @io.read_full(self.r, b)
  if err != None {
    (0, err)
  } else {
    (b[0].to_int(), None)
  }
}

///|
fn Decoder::read_u16be(self : Decoder) -> (Int, @io.IOError?) {
  let (b1, err1) = self.read_byte()
  if err1 != None {
    return (0, err1)
  }
  let (b2, err2) = self.read_byte()
  if err2 != None {
    return (0, err2)
  }
  (((b1 + 0) << 8) | (b2 + 0), None)
}

///|
fn Decoder::skip_marker(self : Decoder) -> @io.IOError? {
  let (length, err) = self.read_u16be()
  if err != None {
    return err
  }
  // Skip length - 2 bytes (length includes itself)
  for _ in 0..<(length - 2) {
    let (_, err) = self.read_byte()
    if err != None {
      return err
    }
  }
  None
}

///|
fn Decoder::parse_sof0(self : Decoder) -> @io.IOError? {
  let (length, err) = self.read_u16be()
  if err != None {
    return err
  }
  let (precision_byte, err) = self.read_byte()
  if err != None {
    return err
  }
  let precision = precision_byte + 0
  if precision != 8 {
    return Some(@io.IOError("unsupported precision"))
  }
  let (height, err) = self.read_u16be()
  if err != None {
    return err
  }
  let (width, err) = self.read_u16be()
  if err != None {
    return err
  }
  let (ncomp_byte, err) = self.read_byte()
  if err != None {
    return err
  }
  let ncomp = ncomp_byte + 0
  if ncomp != 1 && ncomp != 3 {
    return Some(@io.IOError("unsupported number of components"))
  }
  self.bits = precision
  self.height = height
  self.width = width
  self.ncomp = ncomp + 0
  self.comp = Array::new()
  for i in 0..<(ncomp + 0) {
    let (c_byte, err) = self.read_byte()
    if err != None {
      return err
    }
    let c = c_byte + 0
    let (hv, err) = self.read_byte()
    if err != None {
      return err
    }
    let h = (hv >> 4) & 0xF
    let v = hv & 0xF
    let (tq_byte, err) = self.read_byte()
    if err != None {
      return err
    }
    let tq = tq_byte + 0
    self.comp.push(Component::{ h, v, c, tq, dctbl: 0, actbl: 0 })
  }
  // Initialize per-component DC predictors to zero
  self.prev_dc = Array::new()
  for i in 0..<(ncomp + 0) {
    self.prev_dc.push(0)
  }
  None
}

///|
fn Decoder::parse_dqt(self : Decoder) -> @io.IOError? {
  let (length, err) = self.read_u16be()
  if err != None {
    return err
  }
  let mut remaining = length - 2

  // DQT may contain multiple tables in one segment
  while remaining > 0 {
    let (info, err) = self.read_byte()
    if err != None {
      return err
    }
    remaining = remaining - 1
    let pq = (info >> 4) & 0xF
    let tq = info & 0xF
    // Only support 8-bit precision for now
    if pq != 0 {
      return Some(@io.IOError("unsupported DQT precision"))
    }
    let table = Array::new()
    for _ in 0..=64 {
      let (v, err) = self.read_byte()
      if err != None {
        return err
      }
      table.push(v + 0)
      remaining = remaining - 1
    }

    // Ensure qtab is large enough and store by table id
    while self.qtab.length() <= tq {
      self.qtab.push(Array::new())
    }
    self.qtab[tq] = table
  }
  None
}

///|
fn Decoder::parse_dht(self : Decoder) -> @io.IOError? {
  let (length, err) = self.read_u16be()
  if err != None {
    return err
  }
  let mut remaining = length - 2

  // DHT may contain multiple tables
  while remaining > 0 {
    let (info, err) = self.read_byte()
    if err != None {
      return err
    }
    remaining = remaining - 1
    let tc = (info >> 4) & 0xF // table class: 0=DC,1=AC
    let th = info & 0xF // table id

    // Read 16 counts of codes for lengths 1..16
    let lengths = Array::new()
    let mut total = 0
    for _ in 0..=16 {
      let (count_b, err) = self.read_byte()
      if err != None {
        return err
      }
      let count = count_b + 0
      lengths.push(count)
      total += count
      remaining = remaining - 1
    }

    // Read 'total' symbols
    let symbols = Array::new()
    for _ in 0..=total {
      let (s, err) = self.read_byte()
      if err != None {
        return err
      }
      symbols.push(s + 0)
      remaining = remaining - 1
    }
    // Build runtime LUT (Array of arrays indexed by bit-length)
    let lut = Array::new()
    let mut code = 0
    let mut idx = 0
    let mut min_len = 0
    let mut max_len = 0
    for bits = 1; bits <= 16; bits = bits + 1 {
      let cnt = lengths[bits - 1]
      if cnt != 0 && min_len == 0 {
        min_len = bits
      }
      if cnt != 0 {
        max_len = bits
      }
      let size = 1 << bits
      let arr = Array::make(size, -1)
      for i = 0; i < cnt; i = i + 1 {
        if idx >= symbols.length() {
          return Some(@io.IOError("malformed DHT: symbols shorter than counts"))
        }
        let sym = symbols[idx]
        idx += 1
        arr[code] = sym
        code += 1
      }
      code = code << 1
      lut.push(arr)
    }
    let table = HuffmanTable::{
      class: tc,
      id: th,
      lengths,
      symbols,
      lut,
      min_len,
      max_len,
    }
    self.htab.push(table)
  }
  None
}

///|
// Huffman decode: read bits and lookup symbol using built LUTs
fn Decoder::huffman_decode(
  self : Decoder,
  class : Int,
  id : Int,
) -> (Int, @io.IOError?) {
  for table in self.htab {
    if table.class != class || table.id != id {
      continue
    }
    let mut code = 0
    for len = 1; len <= table.max_len; len = len + 1 {
      let (b, err) = self.read_bit()
      if err != None {
        return (0, err)
      }
      code = (code << 1) | b
      if len - 1 < table.lut.length() {
        let arr = table.lut[len - 1]
        if code < arr.length() {
          let sym = arr[code]
          if sym != -1 {
            return (sym, None)
          }
        }
      }
    }
    return (0, Some(@io.IOError("huffman decode failed")))
  }
  (0, Some(@io.IOError("missing huffman table")))
}

///|
fn Decoder::parse_dri(self : Decoder) -> @io.IOError? {
  let (length, err) = self.read_u16be()
  if err != None {
    return err
  }
  if length != 4 {
    return Some(@io.IOError("bad DRI length"))
  }
  let (ri, err) = self.read_u16be()
  if err != None {
    return err
  }
  self.restart_interval = ri + 0
  None
}

///|
// Bit-level reader on Decoder handles byte-stuffing.
fn Decoder::read_bit(self : Decoder) -> (Int, @io.IOError?) {
  if self.bits_left == 0 {
    let (b, err) = self.read_byte()
    if err != None {
      return (0, err)
    }
    if b == 0xFF {
      // Need to inspect the stuffed/marker byte
      let (nb, err2) = self.read_byte()
      if err2 != None {
        return (0, err2)
      }
      if nb == 0x00 {
        self.bit_curr = 0xFF
        self.bits_left = 8
      } else {
        // It's a marker; save it in Decoder and signal upward by returning an IOError
        self.marker = nb
        return (0, Some(@io.IOError("marker")))
      }
    } else {
      self.bit_curr = b
      self.bits_left = 8
    }
  }
  let bit = (self.bit_curr >> (self.bits_left - 1)) & 1
  self.bits_left = self.bits_left - 1
  (bit, None)
}

// Consume entropy-coded data until a marker is observed; placeholder for real decoding.

///|
fn Decoder::read_bits(self : Decoder, n : Int) -> (Int, @io.IOError?) {
  if n == 0 {
    return (0, None)
  }
  let mut v = 0
  for _ in 0..=n {
    let (b, err) = self.read_bit()
    if err != None {
      return (0, err)
    }
    v = (v << 1) | b
  }
  (v, None)
}

///|
fn Decoder::extend_sign(self : Decoder, v : Int, n : Int) -> Int {
  if n == 0 {
    return 0
  }
  let half = 1 << (n - 1)
  if v < half {
    v - ((1 << n) - 1)
  } else {
    v
  }
}

///|
fn Decoder::decode_dc(self : Decoder, comp_idx : Int) -> (Int, @io.IOError?) {
  let dct = self.comp[comp_idx].dctbl
  let (sym, err) = self.huffman_decode(0, dct)
  if err != None {
    return (0, err)
  }
  let mut diff = 0
  if sym != 0 {
    let (bits, err2) = self.read_bits(sym)
    if err2 != None {
      return (0, err2)
    }
    diff = self.extend_sign(bits, sym)
  }
  let prev = self.prev_dc[comp_idx]
  let val = prev + diff
  self.prev_dc[comp_idx] = val
  (val, None)
}

///|
fn Decoder::decode_entropy(self : Decoder) -> @io.IOError? {
  if self.comp.length() == 0 {
    return None
  }
  let n = self.comp.length()
  for i in 0..<(n + 0) {
    let (val, err) = self.decode_dc(i)
    if err != None {
      if self.marker != -1 {
        return None
      }
      return err
    }
    let _ = val

  }
  None
}

///|
fn Decoder::decode_scan(self : Decoder) -> @io.IOError? {
  let err2 = self.decode_entropy()
  if err2 != None {
    if self.marker != -1 {
      return None
    }
    return err2
  }
  None
}
