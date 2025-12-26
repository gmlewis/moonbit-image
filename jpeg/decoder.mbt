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
const SOI : Int = 0xD8 // Start of Image

///|
const SOF0 : Int = 0xC0 // Start of Frame (baseline DCT)

///|
// const SOF1 : Int = 0xC1 // Start of Frame (extended sequential DCT)

///|
// const SOF2 : Int = 0xC2 // Start of Frame (progressive DCT)

///|
const DHT : Int = 0xC4 // Define Huffman Table

///|
// const SOF3 : Int = 0xC3 // Start of Frame (lossless)

///|
const DQT : Int = 0xDB // Define Quantization Table

///|
const DRI : Int = 0xDD // Define Restart Interval

///|
const SOS : Int = 0xDA // Start of Scan

///|
// const RST0 : Int = 0xD0 // Restart 0
// const RST1 : Int = 0xD1 // Restart 1
// const RST2 : Int = 0xD2 // Restart 2
// const RST3 : Int = 0xD3 // Restart 3
// const RST4 : Int = 0xD4 // Restart 4
// const RST5 : Int = 0xD5 // Restart 5
// const RST6 : Int = 0xD6 // Restart 6
// const RST7 : Int = 0xD7 // Restart 7

///|
// const APP0 : Int = 0xE0 // Application 0 (JFIF)
// const APP1 : Int = 0xE1 // Application 1 (EXIF)
// const APP2 : Int = 0xE2 // Application 2
// const APP3 : Int = 0xE3 // Application 3
// const APP4 : Int = 0xE4 // Application 4
// const APP5 : Int = 0xE5 // Application 5
// const APP6 : Int = 0xE6 // Application 6
// const APP7 : Int = 0xE7 // Application 7
// const APP8 : Int = 0xE8 // Application 8
// const APP9 : Int = 0xE9 // Application 9
// const APPA : Int = 0xEA // Application 10
// const APPB : Int = 0xEB // Application 11
// const APPC : Int = 0xEC // Application 12
// const APPD : Int = 0xED // Application 13
// const APPE : Int = 0xEE // Application 14
// const APPF : Int = 0xEF // Application 15

///|
// const COM : Int = 0xFE // Comment

///|
const EOI : Int = 0xD9 // End of Image

///|
using @io {type Slice}

///|
let zig_zag_order : Array[Int] = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48,
  41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15,
  23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62,
  63,
]

///|
let idct_matrix : Array[Int] = [
  11585, 11585, 11585, 11585, 11585, 11585, 11585, 11585, 16069, 13623, 9102, 3196,
  -3196, -9102, -13623, -16069, 15137, 6270, -6270, -15137, -15137, -6270, 6270,
  15137, 13623, -3196, -16069, -9102, 9102, 16069, 3196, -13623, 11585, -11585, -11585,
  11585, 11585, -11585, -11585, 11585, 9102, -16069, 3196, 13623, -13623, -3196,
  16069, -9102, 6270, -15137, 15137, -6270, -6270, 15137, -15137, 6270, 3196, -9102,
  13623, -16069, 16069, -13623, 9102, -3196,
]

///|
priv struct Decoder {
  r : &@io.Reader
  mut width : Int
  mut height : Int
  mut comp : Array[Component] // component info
  mut prev_dc : Array[Int]
  qtab : Array[Array[Int]] // quantization tables
  htab : Array[HuffmanTable] // huffman tables
  mut bit_curr : Int
  mut bits_left : Int
  mut img : &@image.Image
  mut marker : Int
  mut mcu_x : Int
  mut mcu_y : Int
  mut max_h : Int
  mut max_v : Int
  tmp : Slice[Byte]
}

///|
struct Component {
  h : Int // horizontal sampling factor
  v : Int // vertical sampling factor
  c : Int // component identifier
  tq : Int // quantization table destination selector
  mut dctbl : Int
  mut actbl : Int
} derive(Default)

///|
priv struct HuffmanTable {
  class : Int
  id : Int
  lut : Array[Array[Int]]
  max_len : Int
}

///|
fn Decoder::new(r : &@io.Reader) -> Decoder {
  {
    r,
    width: 0,
    height: 0,
    comp: Array::new(),
    prev_dc: Array::new(),
    qtab: Array::new(),
    htab: Array::new(),
    bit_curr: 0,
    bits_left: 0,
    img: &@image.Image::new_empty(),
    marker: -1,
    mcu_x: 0,
    mcu_y: 0,
    max_h: 0,
    max_v: 0,
    tmp: Slice::new(Array::make(1, b'\x00')),
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
  if marker_byte != SOI {
    return (self.img, Some(@io.IOError("missing SOI")))
  }
  //
  // Parse markers until SOS
  let mut done = false
  while !done {
    let (marker, err) = self.read_marker()
    if err != None {
      return (self.img, err)
    }
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
        match self.parse_sos() {
          Some(err) => return (self.img, Some(err))
          None => done = true
        }
      EOI => return (self.img, Some(@io.IOError("unexpected EOI")))
      _ =>
        match self.skip_marker() {
          Some(err) => return (self.img, Some(err))
          None => ()
        }
    }
  }
  //
  // Decode scan header and entropy-coded data
  match self.decode_scan() {
    Some(err) => return (self.img, Some(err))
    None => ()
  }
  (self.img, None)
}

///|
fn Decoder::parse_sos(self : Decoder) -> @io.IOError? {
  let (_, err) = self.read_u16be()
  if err != None {
    return err
  }
  let (ncomp_byte, err) = self.read_byte()
  if err != None {
    return err
  }
  let ncomp = ncomp_byte
  // Read component selectors
  for _ in 0..<ncomp {
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
        self.comp[i].dctbl = dct
        self.comp[i].actbl = act
        break
      }
    }
  }
  // Ss, Se, AhAl
  for _ in 0..<3 {
    let (_, err) = self.read_byte()
    if err != None {
      return err
    }
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
  let (_, err) = @io.read_full(self.r, self.tmp)
  if err != None {
    (0, err)
  } else {
    (self.tmp[0].to_int(), None)
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
  ((b1 << 8) | b2, None)
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
  let (_, err) = self.read_u16be()
  if err != None {
    return err
  }
  let (precision, err) = self.read_byte()
  if err != None {
    return err
  }
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
  let (ncomp, err) = self.read_byte()
  if err != None {
    return err
  }
  if ncomp != 1 && ncomp != 3 {
    return Some(@io.IOError("unsupported number of components"))
  }
  self.height = height
  self.width = width
  // Initialize image
  let r = @image.rect(0, 0, width, height)
  try {
    let rgba = @image.RGBA::new(r)
    self.img = rgba
  } catch {
    err => return Some(@io.IOError("failed to create image: \{err}"))
  }
  //
  self.comp = Array::new()
  let mut max_h = 0
  let mut max_v = 0
  for _ in 0..<ncomp {
    let (c, err) = self.read_byte()
    if err != None {
      return err
    }
    let (hv, err) = self.read_byte()
    if err != None {
      return err
    }
    let h = (hv >> 4) & 0xF
    let v = hv & 0xF
    if h > max_h {
      max_h = h
    }
    if v > max_v {
      max_v = v
    }
    let (tq, err) = self.read_byte()
    if err != None {
      return err
    }
    self.comp.push(Component::{ h, v, c, tq, dctbl: 0, actbl: 0 })
  }
  self.max_h = max_h
  self.max_v = max_v
  // Initialize per-component DC predictors to zero
  self.prev_dc = Array::new()
  for _ in 0..<ncomp {
    self.prev_dc.push(0)
  }
  // Reset MCU coords
  self.mcu_x = 0
  self.mcu_y = 0
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
    for _ in 0..<64 {
      let (v, err) = self.read_byte()
      if err != None {
        return err
      }
      table.push(v)
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
    for _ in 0..<16 {
      let (count, err) = self.read_byte()
      if err != None {
        return err
      }
      lengths.push(count)
      total += count
      remaining = remaining - 1
    }
    // Read 'total' symbols
    let symbols = Array::new()
    for _ in 0..<total {
      let (s, err) = self.read_byte()
      if err != None {
        return err
      }
      symbols.push(s)
      remaining = remaining - 1
    }
    // Build runtime LUT
    let lut = Array::new()
    let mut code = 0
    let mut idx = 0
    let mut max_len = 0
    for bits = 1; bits <= 16; bits = bits + 1 {
      let cnt = lengths[bits - 1]
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
        if code < size {
          arr[code] = sym
        }
        code += 1
      }
      code = code << 1
      lut.push(arr)
    }
    let table = HuffmanTable::{ class: tc, id: th, lut, max_len }
    self.htab.push(table)
  }
  None
}

///|
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
  let (_, err) = self.read_u16be()
  // ri is currently unused
  if err != None {
    return err
  }
  None
}

///|
fn Decoder::read_bit(self : Decoder) -> (Int, @io.IOError?) {
  if self.bits_left == 0 {
    if self.marker != -1 {
      return (0, Some(@io.IOError("marker")))
    }
    let (b, err) = self.read_byte()
    if err != None {
      return (0, err)
    }
    if b == 0xFF {
      let (nb, err2) = self.read_byte()
      if err2 != None {
        return (0, err2)
      }
      if nb == 0x00 {
        self.bit_curr = 0xFF
        self.bits_left = 8
      } else {
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

///|
fn Decoder::read_bits(self : Decoder, n : Int) -> (Int, @io.IOError?) {
  if n <= 0 {
    return (0, None)
  }
  let mut v = 0
  for _ in 0..<n {
    let (b, err) = self.read_bit()
    if err != None {
      return (0, err)
    }
    v = (v << 1) | b
  }
  (v, None)
}

///|
fn Decoder::extend_sign(v : Int, n : Int) -> Int {
  if n <= 0 {
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
    diff = Decoder::extend_sign(bits, sym)
  }
  let prev = self.prev_dc[comp_idx]
  let val = prev + diff
  self.prev_dc[comp_idx] = val
  (val, None)
}

///|
fn Decoder::decode_ac(
  self : Decoder,
  comp_idx : Int,
  block : Array[Int],
) -> (Array[Int], @io.IOError?) {
  let act = self.comp[comp_idx].actbl
  let mut k = 1
  while k <= 63 {
    let (sym, err) = self.huffman_decode(1, act)
    if err != None {
      return (Array::new(), err)
    }
    if sym == 0 {
      break
    }
    if sym == 0xF0 {
      k = k + 16
      continue
    }
    let run = (sym >> 4) & 0xF
    let size = sym & 0xF
    k = k + run
    if k > 63 {
      return (Array::new(), Some(@io.IOError("bad AC run overflow")))
    }
    if size != 0 {
      let (bits, err2) = self.read_bits(size)
      if err2 != None {
        return (Array::new(), err2)
      }
      let val = Decoder::extend_sign(bits, size)
      let pos = zig_zag_order[k]
      block[pos] = val
    }
    k = k + 1
  }
  (block, None)
}

///|
fn Decoder::decode_block(
  self : Decoder,
  comp_idx : Int,
) -> (Array[Int], @io.IOError?) {
  let block = Array::make(64, 0)
  let (dc, err) = self.decode_dc(comp_idx)
  if err != None {
    return (Array::new(), err)
  }
  block[0] = dc
  let (_, err2) = self.decode_ac(comp_idx, block)
  if err2 != None {
    return (Array::new(), err2)
  }
  (block, None)
}

///|
fn Decoder::dequantize(
  self : Decoder,
  block : Array[Int],
  tq : Int,
) -> (Array[Int], @io.IOError?) {
  if tq >= self.qtab.length() {
    return (Array::new(), Some(@io.IOError("missing qtable")))
  }
  let q = self.qtab[tq]
  if q.length() < 64 {
    return (Array::new(), Some(@io.IOError("short qtable")))
  }
  let out = Array::make(64, 0)
  for i in 0..<64 {
    out[i] = block[i] * q[i]
  }
  (out, None)
}

///|
fn Decoder::idct_block(blk : Array[Int]) -> Array[Int] {
  let shift = 30 // 2 * 14 + 2
  let round_val = 1L << (shift - 1)
  let out = Array::make(64, 0)
  for y in 0..<8 {
    for x in 0..<8 {
      let mut s = 0L
      for u in 0..<8 {
        for v in 0..<8 {
          let cu = idct_matrix[u * 8 + x].to_int64()
          let cv = idct_matrix[v * 8 + y].to_int64()
          let coeff = blk[u * 8 + v].to_int64()
          s = s + cu * cv * coeff
        }
      }
      let val = ((s + round_val) >> shift).to_int()
      let pix = val + 128
      let pix = if pix < 0 { 0 } else if pix > 255 { 255 } else { pix }
      out[y * 8 + x] = pix
    }
  }
  out
}

///|
fn Decoder::emit_block_pixels(
  self : Decoder,
  blocks : Array[Array[Array[Int]]],
) -> @io.IOError? {
  if blocks.length() == 0 {
    // Advance anyway to avoid infinite loop
    self.mcu_x = self.mcu_x + self.max_h * 8
    if self.mcu_x >= self.width {
      self.mcu_x = 0
      self.mcu_y = self.mcu_y + self.max_v * 8
    }
    return None
  }
  //
  let mcu_width = self.max_h * 8
  let mcu_height = self.max_v * 8
  //
  // IDCT all blocks
  let idct_blocks : Array[Array[Array[Int]]] = Array::new(
    capacity=blocks.length(),
  )
  for i in 0..<blocks.length() {
    let comp_blocks = Array::new(capacity=blocks[i].length())
    for j in 0..<blocks[i].length() {
      comp_blocks.push(Decoder::idct_block(blocks[i][j]))
    }
    idct_blocks.push(comp_blocks)
  }
  //
  for y in 0..<mcu_height {
    for x in 0..<mcu_width {
      let mut yv = 128
      let mut cbv = 128
      let mut crv = 128
      //
      // For each component, find the pixel value
      for i in 0..<idct_blocks.length() {
        let comp = self.comp[i]
        // block coordinates within this component
        let bx = x * comp.h / self.max_h / 8
        let by = y * comp.v / self.max_v / 8
        // pixel coordinates within that block
        let px = x * comp.h / self.max_h % 8
        let py = y * comp.v / self.max_v % 8
        let block_idx = by * comp.h + bx
        if block_idx < idct_blocks[i].length() {
          let val = idct_blocks[i][block_idx][py * 8 + px]
          if i == 0 {
            yv = val
          } else if i == 1 {
            cbv = val
          } else if i == 2 {
            crv = val
          }
        }
      }
      //
      let (r, g, b) = @color.y_cb_cr_to_rgb(
        yv.to_byte(),
        cbv.to_byte(),
        crv.to_byte(),
      )
      let px = self.mcu_x + x
      let py = self.mcu_y + y
      if px < self.width && py < self.height {
        self.img.set(px, py, @color.RGBA::new(r, g, b, 0xff))
      }
    }
  }
  //
  // Advance MCU position
  self.mcu_x = self.mcu_x + mcu_width
  if self.mcu_x >= self.width {
    self.mcu_x = 0
    self.mcu_y = self.mcu_y + mcu_height
  }
  None
}

///|
fn Decoder::decode_entropy(self : Decoder) -> @io.IOError? {
  if self.comp.length() == 0 {
    return Some(@io.IOError("no components"))
  }
  let n = self.comp.length()
  let blocks : Array[Array[Array[Int]]] = Array::new(capacity=n)
  for i in 0..<n {
    let comp = self.comp[i]
    let nblocks = comp.h * comp.v
    let comp_blocks = Array::new(capacity=nblocks)
    for _ in 0..<nblocks {
      let (block, err) = self.decode_block(i)
      if err != None {
        return err
      }
      let tq = comp.tq
      let (dq, err2) = self.dequantize(block, tq)
      if err2 != None {
        return err2
      }
      comp_blocks.push(dq)
    }
    blocks.push(comp_blocks)
  }
  self.emit_block_pixels(blocks)
}

///|
fn Decoder::decode_scan(self : Decoder) -> @io.IOError? {
  while self.mcu_y < self.height {
    if self.marker != -1 {
      break
    }
    let old_x = self.mcu_x
    let old_y = self.mcu_y
    let err = self.decode_entropy()
    if err != None {
      if self.marker != -1 {
        return None
      }
      return err
    }
    if self.mcu_x == old_x && self.mcu_y == old_y {
      return Some(
        @io.IOError(
          "decoder stuck: x=\{self.mcu_x} y=\{self.mcu_y} width=\{self.width} height=\{self.height}",
        ),
      )
    }
  }
  None
}
