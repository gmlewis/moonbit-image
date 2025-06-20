///|
/// Package png implements a PNG image decoder and encoder.
///
/// The PNG specification is at https://www.w3.org/TR/PNG/.
///
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/png/reader.go
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.

// Color type, as per the PNG spec.
const CT_GRAYSCALE = 0

///|
const CT_TRUE_COLOR = 2

///|
const CT_PALETTED = 3

///|
const CT_GRAYSCALE_ALPHA = 4

///|
const CT_TRUE_COLOR_ALPHA = 6

// A cb is a combination of color type and bit depth.

///|
const CB_INVALID = 0

///|
const CB_G1 = 1

///|
const CB_G2 = 2

///|
const CB_G4 = 3

///|
const CB_G8 = 4

///|
const CB_GA8 = 5

///|
const CB_TC8 = 6

///|
const CB_P1 = 7

///|
const CB_P2 = 8

///|
const CB_P4 = 9

///|
const CB_P8 = 10

///|
const CB_TCA8 = 11

///|
const CB_G16 = 12

///|
const CB_GA16 = 13

///|
const CB_TC16 = 14

///|
const CB_TCA16 = 15

///|
fn cb_paletted(cb : Int) -> Bool {
  CB_P1 <= cb && cb <= CB_P8
}

///|
fn cb_true_color(cb : Int) -> Bool {
  cb == CB_TC8 || cb == CB_TC16
}

///|
/// Filter type, as per the PNG spec.
const FT_NONE = b'\x00'

///|
const FT_SUB = b'\x01'

///|
const FT_UP = b'\x02'

///|
const FT_AVERAGE = b'\x03'

///|
const FT_PAETH = b'\x04'

// const N_FILTER = 5

///|
/// Interlace type.
const IT_NONE = b'\x00'

///|
const IT_ADAM7 = b'\x01'

///|
/// InterlaceScan defines the placement and size of a pass for Adam7 interlacing.
priv struct InterlaceScan {
  x_factor : Int
  y_factor : Int
  x_offset : Int
  y_offset : Int
}

///|
/// interlacing defines Adam7 interlacing, with 7 passes of reduced images.
/// See https://www.w3.org/TR/PNG/#8Interlace
let interlacing : Array[InterlaceScan] = [
  { x_factor: 8, y_factor: 8, x_offset: 0, y_offset: 0 },
  { x_factor: 8, y_factor: 8, x_offset: 4, y_offset: 0 },
  { x_factor: 4, y_factor: 8, x_offset: 0, y_offset: 4 },
  { x_factor: 4, y_factor: 4, x_offset: 2, y_offset: 0 },
  { x_factor: 2, y_factor: 4, x_offset: 0, y_offset: 2 },
  { x_factor: 2, y_factor: 2, x_offset: 1, y_offset: 0 },
  { x_factor: 1, y_factor: 2, x_offset: 0, y_offset: 1 },
]

// Decoding stage.
// The PNG specification says that the IHDR, PLTE (if present), tRNS (if
// present), IDAT and IEND chunks must appear in that order. There may be
// multiple IDAT chunks, and IDAT chunks must be sequential (i.e. they may not
// have any other chunks between them).
// https://www.w3.org/TR/PNG/#5ChunkOrdering

///|
const DS_START = 0

///|
const DS_SEEN_IHDR = 1

///|
const DS_SEEN_PLTE = 2

///|
const DS_SEENT_RNS = 3

///|
const DS_SEEN_IDAT = 4

///|
const DS_SEEN_IEND = 5

///|
let header = b"\x89PNG\r\n\x1a\n"

///|
struct Decoder {
  r : &@io.Reader
  mut img : &@image.Image
  crc : &@hash.Hash32
  mut width : Int
  mut height : Int
  mut depth : Int
  mut palette : @color.Palette
  mut cb : Int
  mut stage : Int
  mut idat_length : UInt
  tmp : Slice[Byte] // [3 * 256]byte
  mut interlace : Int

  // use_transparent and transparent are used for grayscale and truecolor
  // transparency, as opposed to palette transparency.
  mut use_transparent : Bool
  transparent : Slice[Byte] // [6]byte
}

///|
// fn Decoder::read_byte(self : Decoder) -> (Byte, IOError?) {
//   let b = Slice::new([b'\x00'])
//   let (_, err) = self.r.read(b)
//   (b[0], err)
// }

///|
fn Decoder::new(r : &@io.Reader) -> Decoder {
  {
    r,
    img: &@image.Image::new_empty(),
    crc: @crc32.new(),
    width: 0,
    height: 0,
    depth: 0,
    palette: @color.Palette::new_empty(),
    cb: 0,
    stage: 0,
    idat_length: 0U,
    tmp: Slice::new(Array::make(3 * 256, b'\x00')), // [3 * 256]byte
    interlace: 0,
    use_transparent: false,
    transparent: Slice::new([0, 0, 0, 0, 0, 0]), // [6]byte
  }
}

///|
typealias @io.IOError

///|
/// A format_error reports that the input is not a valid PNG.
fn format_error(e : String) -> IOError {
  IOError("png: invalid format: \{e}")
}

///|
pub let chunk_order_error : IOError = format_error("chunk out of order")

///|
/// An unsupported_error reports that the input uses a valid but unimplemented PNG feature.
fn unsupported_error(e : String) -> IOError {
  IOError("png: unsupported feature: \{e}")
}

///|
fn parse_ihdr(self : Decoder, length : UInt) -> IOError? {
  if length != 13 {
    return Some(format_error("bad IHDR length"))
  }
  let (_, err) = @io.read_full(self.r, self.tmp[:13])
  if err != None {
    return err
  }
  guard self.crc.write(self.tmp[:13]) is (_, None)
  if self.tmp[10] != 0 {
    return Some(unsupported_error("compression method"))
  }
  if self.tmp[11] != 0 {
    return Some(unsupported_error("filter method"))
  }
  if self.tmp[12] != IT_NONE && self.tmp[12] != IT_ADAM7 {
    return Some(format_error("invalid interlace method"))
  }
  self.interlace = self.tmp[12].to_int()

  //
  let w = be_uint32(self.tmp[0:4]).reinterpret_as_int()
  let h = be_uint32(self.tmp[4:8]).reinterpret_as_int()
  if w <= 0 || h <= 0 {
    return Some(format_error("non-positive dimension"))
  }
  let n_pixels64 = w.to_int64() * h.to_int64()
  let n_pixels = n_pixels64.to_int()
  if n_pixels64 != n_pixels.to_int64() {
    return Some(unsupported_error("dimension overflow"))
  }
  // There can be up to 8 bytes per pixel, for 16 bits per channel RGBA.
  if n_pixels != n_pixels * 8 / 8 {
    return Some(unsupported_error("dimension overflow"))
  }

  //
  self.cb = CB_INVALID
  self.depth = self.tmp[8].to_int()
  match self.depth {
    1 =>
      match self.tmp[9].to_int() {
        CT_GRAYSCALE => self.cb = CB_G1
        CT_PALETTED => self.cb = CB_P1
        _ => ()
      }
    2 =>
      match self.tmp[9].to_int() {
        CT_GRAYSCALE => self.cb = CB_G2
        CT_PALETTED => self.cb = CB_P2
        _ => ()
      }
    4 =>
      match self.tmp[9].to_int() {
        CT_GRAYSCALE => self.cb = CB_G4
        CT_PALETTED => self.cb = CB_P4
        _ => ()
      }
    8 =>
      match self.tmp[9].to_int() {
        CT_GRAYSCALE => self.cb = CB_G8
        CT_TRUE_COLOR => self.cb = CB_TC8
        CT_PALETTED => self.cb = CB_P8
        CT_GRAYSCALE_ALPHA => self.cb = CB_GA8
        CT_TRUE_COLOR_ALPHA => self.cb = CB_TCA8
        _ => ()
      }
    16 =>
      match self.tmp[9].to_int() {
        CT_GRAYSCALE => self.cb = CB_G16
        CT_TRUE_COLOR => self.cb = CB_TC16
        CT_GRAYSCALE_ALPHA => self.cb = CB_GA16
        CT_TRUE_COLOR_ALPHA => self.cb = CB_TCA16
        _ => ()
      }
    _ => ()
  }
  if self.cb == CB_INVALID {
    return Some(
      unsupported_error(
        "bit depth \{self.tmp[8].to_int()}, color type \{self.tmp[9].to_int()}",
      ),
    )
  }
  self.width = w
  self.height = h
  self.verify_checksum()
}

///|
fn be_uint32(b : Slice[Byte]) -> UInt {
  (b[0].to_uint() << 24) |
  (b[1].to_uint() << 16) |
  (b[2].to_uint() << 8) |
  b[3].to_uint()
}

///|
fn parse_plte(self : Decoder, length : UInt) -> IOError? {
  let np = (length / 3).reinterpret_as_int() // The number of palette entries.
  if length % 3 != 0 || np <= 0 || np > 256 || np > 1 << self.depth {
    return Some(format_error("bad PLTE length"))
  }
  let (n, err) = @io.read_full(self.r, self.tmp[:3 * np])
  if err != None {
    return err
  }
  guard self.crc.write(self.tmp[:n]) is (_, None)
  match self.cb {
    CB_P1 | CB_P2 | CB_P4 | CB_P8 => {
      self.palette = @color.Palette::new(256)
      for i = 0; i < np; i = i + 1 {
        self.palette.inner()[i] = @color.RGBA::new(
          self.tmp[3 * i + 0],
          self.tmp[3 * i + 1],
          self.tmp[3 * i + 2],
          0xff,
        )
      }
      for i = np; i < 256; i = i + 1 {
        // Initialize the rest of the palette to opaque black. The spec (section
        // 11.2.3) says that "any out-of-range pixel value found in the image data
        // is an error", but some real-world PNG files have out-of-range pixel
        // values. We fall back to opaque black, the same as libpng 1.5.13;
        // ImageMagick 6.5.7 returns an error.
        self.palette.inner()[i] = @color.RGBA::new(0x00, 0x00, 0x00, 0xff)
      }
      self.palette = @color.Palette(self.palette.inner()[:np])
    }
    CB_TC8 | CB_TCA8 | CB_TC16 | CB_TCA16 =>
      // As per the PNG spec, a PLTE chunk is optional (and for practical purposes,
      // ignorable) for the CT_TRUE_COLOR and CT_TRUE_COLOR_ALPHA color types (section 4.1.2).
      ()
    _ => return Some(format_error("PLTE, color type mismatch"))
  }
  self.verify_checksum()
}

///|
fn parse_t_rns(self : Decoder, length : UInt) -> IOError? {
  match self.cb {
    CB_G1 | CB_G2 | CB_G4 | CB_G8 | CB_G16 => {
      if length != 2 {
        return Some(format_error("bad tRNS length"))
      }
      let (n, err) = @io.read_full(
        self.r,
        self.tmp[:length.reinterpret_as_int()],
      )
      if err != None {
        return err
      }
      guard self.crc.write(self.tmp[:n]) is (_, None)
      let _ = slice_copy(
        self.transparent[:],
        self.tmp[:length.reinterpret_as_int()],
      )
      match self.cb {
        CB_G1 => self.transparent[1] *= 0xff
        CB_G2 => self.transparent[1] *= 0x55
        CB_G4 => self.transparent[1] *= 0x11
        _ => ()
      }
      self.use_transparent = true
    }
    CB_TC8 | CB_TC16 => {
      if length != 6 {
        return Some(format_error("bad tRNS length"))
      }
      let (n, err) = @io.read_full(
        self.r,
        self.tmp[:length.reinterpret_as_int()],
      )
      if err != None {
        return err
      }
      guard self.crc.write(self.tmp[:n]) is (_, None)
      let _ = slice_copy(
        self.transparent,
        self.tmp[:length.reinterpret_as_int()],
      )
      self.use_transparent = true
    }
    CB_P1 | CB_P2 | CB_P4 | CB_P8 => {
      if length > 256 {
        return Some(format_error("bad tRNS length"))
      }
      let (n, err) = @io.read_full(
        self.r,
        self.tmp[:length.reinterpret_as_int()],
      )
      if err != None {
        return err
      }
      guard self.crc.write(self.tmp[:n]) is (_, None)
      if self.palette.inner().length() < n {
        self.palette = self.palette.inner()[:n]
      }
      for i = 0; i < n; i = i + 1 {
        let (r, g, b, _) = self.palette.inner()[i].rgba()
        let r = (r >> 8).to_byte()
        let g = (g >> 8).to_byte()
        let b = (b >> 8).to_byte()
        self.palette.inner()[i] = @color.NRGBA::new(r, g, b, self.tmp[i])
      }
    }
    _ => return Some(format_error("tRNS, color type mismatch"))
  }
  return self.verify_checksum()
}

///|
fn slice_copy(dst : Slice[Byte], src : Slice[Byte]) -> Int {
  let n = @math.minimum(dst.length(), src.length())
  for i = 0; i < n; i = i + 1 {
    dst[i] = src[i]
  }
  n
}

///|
/// Read presents one or more IDAT chunks as one continuous stream (minus the
/// intermediate chunk headers and footers). If the PNG data looked like:
///
///	... len0 IDAT xxx crc0 len1 IDAT yy crc1 len2 IEND crc2
///
/// then this reader presents xxxyy. For well-formed PNG data, the decoder state
/// immediately before the first Read call is that d.r is positioned between the
/// first IDAT and xxx, and the decoder state immediately after the last Read
/// call is that d.r is positioned between yy and crc1.
pub impl @io.Reader for Decoder with read(self, p) {
  if p.length() == 0 {
    return (0, None)
  }
  while self.idat_length == 0 {
    // We have exhausted an IDAT chunk. Verify the checksum of that chunk.
    let err = self.verify_checksum()
    if err != None {
      return (0, err)
    }
    // Read the length and chunk type of the next chunk, and check that
    // it is an IDAT chunk.
    let (_, err) = @io.read_full(self.r, self.tmp[:8])
    if err != None {
      return (0, err)
    }
    self.idat_length = be_uint32(self.tmp[:4])
    if self.tmp[4:8].to_bytes() != b"IDAT" {
      return (0, Some(format_error("not enough pixel data")))
    }
    self.crc.reset()
    guard self.crc.write(self.tmp[4:8]) is (_, None)
  }
  if self.idat_length.reinterpret_as_int() < 0 {
    return (0, Some(unsupported_error("IDAT chunk length overflow")))
  }
  let want_len = self.idat_length.reinterpret_as_int()
  let read_len = @math.minimum(p.length(), want_len)
  let (n, err) = self.r.read(p[:read_len])
  guard self.crc.write(p[:n]) is (_, None)
  self.idat_length -= n.reinterpret_as_uint()
  (n, err)
}

///|
/// decode decodes the IDAT data into an image.
fn decode_idat(self : Decoder) -> (&@image.Image, IOError?) {
  let mut img = &@image.Image::new_empty()
  let (r, err) = @zlib.Reader::new(ReaderSize::new(self, DEFAULT_BUF_SIZE))
  if err != None {
    return (img, err)
  }
  if self.interlace == IT_NONE.to_int() {
    let tmp = self.read_image_pass(r, 0, false)
    img = tmp.0
    let err = tmp.1
    if err != None {
      let _ = r.close()
      return (img, err)
    }
  } else if self.interlace == IT_ADAM7.to_int() {
    // Allocate a blank image of the full size.
    let tmp = self.read_image_pass(r, 0, true)
    img = tmp.0
    let err = tmp.1
    if err != None {
      let _ = r.close()
      return (img, err)
    }
    for pass = 0; pass < 7; pass = pass + 1 {
      let (image_pass, err) = self.read_image_pass(r, pass, false)
      if err != None {
        let _ = r.close()
        return (img, err)
      }
      if not(image_pass.empty()) {
        merge_pass_into(img, image_pass, pass)
      }
    }
  }

  // Check for EOF, to verify the zlib checksum.
  let mut n = 0
  let mut err : IOError? = None
  for i = 0; n == 0 && err == None; i = i + 1 {
    if i == 100 {
      let _ = r.close()
      return (img, Some(@io.err_no_progress))
    }
    let tmp = r.read(self.tmp[:1]) // discard data
    n = tmp.0
    err = tmp.1
  }
  if err != None && err != Some(@io.eof) {
    let _ = r.close()
    return (img, Some(format_error(err.to_string())))
  }
  if n != 0 || self.idat_length != 0 {
    let _ = r.close()
    return (
      img,
      Some(
        format_error(
          "too much pixel data: n=\{n}, idat_length=\{self.idat_length}",
        ),
      ),
    )
  }
  let _ = r.close()
  return (img, None)
}

///|
fn size_error(e : @image.SizeError) -> IOError? {
  Some(format_error(e.to_string()))
}

///|
/// read_image_pass reads a single image pass, sized according to the pass number.
fn read_image_pass(
  self : Decoder,
  r : &@io.Reader,
  pass : Int,
  allocate_only : Bool
) -> (&@image.Image, IOError?) {
  let mut bits_per_pixel = 0
  let mut pix_offset = 0
  let mut gray = @image.Gray::new_empty()
  let mut rgba = @image.RGBA::new_empty()
  let mut paletted = @image.Paletted::new_empty()
  let mut nrgba = @image.NRGBA::new_empty()
  let mut gray16 = @image.Gray16::new_empty()
  let mut rgba64 = @image.RGBA64::new_empty()
  let mut nrgba64 = @image.NRGBA64::new_empty()
  let mut img = &@image.Image::new_empty()

  //
  let mut width = self.width
  let mut height = self.height
  if self.interlace == IT_ADAM7.to_int() && not(allocate_only) {
    let p = interlacing[pass]
    // Add the multiplication factor and subtract one, effectively rounding up.
    width = (width - p.x_offset + p.x_factor - 1) / p.x_factor
    height = (height - p.y_offset + p.y_factor - 1) / p.y_factor
    // A PNG image can't have zero width or height, but for an interlaced
    // image, an individual pass might have zero width or height. If so, we
    // shouldn't even read a per-row filter type byte, so return early.
    if width == 0 || height == 0 {
      return (img, None)
    }
  }

  //
  match self.cb {
    CB_G1 | CB_G2 | CB_G4 | CB_G8 => {
      bits_per_pixel = self.depth
      if self.use_transparent {
        nrgba = @image.NRGBA::new(@image.rect(0, 0, width, height)) catch {
          e => return (img, size_error(e))
        }
        img = nrgba
      } else {
        gray = @image.Gray::new(@image.rect(0, 0, width, height)) catch {
          e => return (img, size_error(e))
        }
        img = gray
      }
    }
    CB_GA8 => {
      bits_per_pixel = 16
      nrgba = @image.NRGBA::new(@image.rect(0, 0, width, height)) catch {
        e => return (img, size_error(e))
      }
      img = nrgba
    }
    CB_TC8 => {
      bits_per_pixel = 24
      if self.use_transparent {
        nrgba = @image.NRGBA::new(@image.rect(0, 0, width, height)) catch {
          e => return (img, size_error(e))
        }
        img = nrgba
      } else {
        rgba = @image.RGBA::new(@image.rect(0, 0, width, height)) catch {
          e => return (img, size_error(e))
        }
        img = rgba
      }
    }
    CB_P1 | CB_P2 | CB_P4 | CB_P8 => {
      bits_per_pixel = self.depth
      paletted = @image.Paletted::new(
        @image.rect(0, 0, width, height),
        self.palette,
      ) catch {
        e => return (img, size_error(e))
      }
      img = paletted
    }
    CB_TCA8 => {
      bits_per_pixel = 32
      nrgba = @image.NRGBA::new(@image.rect(0, 0, width, height)) catch {
        e => return (img, size_error(e))
      }
      img = nrgba
    }
    CB_G16 => {
      bits_per_pixel = 16
      if self.use_transparent {
        nrgba64 = @image.NRGBA64::new(@image.rect(0, 0, width, height)) catch {
          e => return (img, size_error(e))
        }
        img = nrgba64
      } else {
        gray16 = @image.Gray16::new(@image.rect(0, 0, width, height)) catch {
          e => return (img, size_error(e))
        }
        img = gray16
      }
    }
    CB_GA16 => {
      bits_per_pixel = 32
      nrgba64 = @image.NRGBA64::new(@image.rect(0, 0, width, height)) catch {
        e => return (img, size_error(e))
      }
      img = nrgba64
    }
    CB_TC16 => {
      bits_per_pixel = 48
      if self.use_transparent {
        nrgba64 = @image.NRGBA64::new(@image.rect(0, 0, width, height)) catch {
          e => return (img, size_error(e))
        }
        img = nrgba64
      } else {
        rgba64 = @image.RGBA64::new(@image.rect(0, 0, width, height)) catch {
          e => return (img, size_error(e))
        }
        img = rgba64
      }
    }
    CB_TCA16 => {
      bits_per_pixel = 64
      nrgba64 = @image.NRGBA64::new(@image.rect(0, 0, width, height)) catch {
        e => return (img, size_error(e))
      }
      img = nrgba64
    }
    _ => ()
  }
  if allocate_only {
    return (img, None)
  }
  let bytes_per_pixel = (bits_per_pixel + 7) / 8

  // The +1 is for the per-row filter type, which is at cr[0].
  let row_size = 1L + (bits_per_pixel.to_int64() * width.to_int64() + 7) / 8
  if row_size != row_size.to_int().to_int64() {
    return (img, Some(unsupported_error("dimension overflow")))
  }
  let row_size = row_size.to_int()
  // cr and pr are the bytes for the current and previous row.
  let mut cr = Slice::new(Array::make(row_size, b'\x00'))
  let mut pr = Slice::new(Array::make(row_size, b'\x00'))

  //
  for y = 0; y < height; y = y + 1 {
    // Read the decompressed bytes.
    let (_, err) = @io.read_full(r, cr)
    if err != None {
      if err == Some(@io.eof) || err == Some(@io.err_unexpected_eof) {
        return (img, Some(format_error("not enough pixel data")))
      }
      return (img, err)
    }

    // Apply the filter.
    let cdat = cr[1:]
    let pdat = pr[1:]
    match cr[0] {
      FT_NONE =>
        // No-op.
        ()
      FT_SUB =>
        for i = bytes_per_pixel; i < cdat.length(); i = i + 1 {
          cdat[i] += cdat[i - bytes_per_pixel]
        }
      FT_UP =>
        for i, p in pdat {
          cdat[i] += p
        }
      FT_AVERAGE => {
        // The first column has no column to the left of it, so it is a
        // special case. We know that the first column exists because we
        // check above that width != 0, and so len(cdat) != 0.
        for i = 0; i < bytes_per_pixel; i = i + 1 {
          cdat[i] += pdat[i] / 2
        }
        for i = bytes_per_pixel; i < cdat.length(); i = i + 1 {
          cdat[i] += ((cdat[i - bytes_per_pixel].to_int() + pdat[i].to_int()) /
          2).to_byte()
        }
      }
      FT_PAETH => filter_paeth(cdat, pdat, bytes_per_pixel)
      _ => return (img, Some(format_error("bad filter type")))
    }

    // Convert from bytes to colors.
    match self.cb {
      CB_G1 =>
        if self.use_transparent {
          let ty = self.transparent[1]
          for x = 0; x < width; x = x + 8 {
            let mut b = cdat[x / 8]
            for x2 = 0; x2 < 8 && x + x2 < width; x2 = x2 + 1 {
              let ycol = (b >> 7) * 0xff
              let mut acol = b'\xff'
              if ycol == ty {
                acol = b'\x00'
              }
              nrgba.set_nrgba(
                x + x2,
                y,
                @color.NRGBA::new(ycol, ycol, ycol, acol),
              )
              b = b << 1
            }
          }
        } else {
          for x = 0; x < width; x = x + 8 {
            let mut b = cdat[x / 8]
            for x2 = 0; x2 < 8 && x + x2 < width; x2 = x2 + 1 {
              gray.set_gray(x + x2, y, @color.Gray::new((b >> 7) * 0xff))
              b = b << 1
            }
          }
        }
      CB_G2 =>
        if self.use_transparent {
          let ty = self.transparent[1]
          for x = 0; x < width; x = x + 4 {
            let mut b = cdat[x / 4]
            for x2 = 0; x2 < 4 && x + x2 < width; x2 = x2 + 1 {
              let ycol = (b >> 6) * 0x55
              let mut acol = b'\xff'
              if ycol == ty {
                acol = b'\x00'
              }
              nrgba.set_nrgba(
                x + x2,
                y,
                @color.NRGBA::new(ycol, ycol, ycol, acol),
              )
              b = b << 2
            }
          }
        } else {
          for x = 0; x < width; x = x + 4 {
            let mut b = cdat[x / 4]
            for x2 = 0; x2 < 4 && x + x2 < width; x2 = x2 + 1 {
              gray.set_gray(x + x2, y, @color.Gray::new((b >> 6) * 0x55))
              b = b << 2
            }
          }
        }
      CB_G4 =>
        if self.use_transparent {
          let ty = self.transparent[1]
          for x = 0; x < width; x = x + 2 {
            let mut b = cdat[x / 2]
            for x2 = 0; x2 < 2 && x + x2 < width; x2 = x2 + 1 {
              let ycol = (b >> 4) * 0x11
              let mut acol = b'\xff'
              if ycol == ty {
                acol = b'\x00'
              }
              nrgba.set_nrgba(
                x + x2,
                y,
                @color.NRGBA::new(ycol, ycol, ycol, acol),
              )
              b = b << 4
            }
          }
        } else {
          for x = 0; x < width; x = x + 2 {
            let mut b = cdat[x / 2]
            for x2 = 0; x2 < 2 && x + x2 < width; x2 = x2 + 1 {
              gray.set_gray(x + x2, y, @color.Gray::new((b >> 4) * 0x11))
              b = b << 4
            }
          }
        }
      CB_G8 =>
        if self.use_transparent {
          let ty = self.transparent[1]
          for x = 0; x < width; x = x + 1 {
            let ycol = cdat[x]
            let mut acol = b'\xff'
            if ycol == ty {
              acol = 0x00
            }
            nrgba.set_nrgba(x, y, @color.NRGBA::new(ycol, ycol, ycol, acol))
          }
        } else {
          let _ = slice_copy(gray.pix[pix_offset:], cdat)
          pix_offset += gray.stride
        }
      CB_GA8 =>
        for x = 0; x < width; x = x + 1 {
          let ycol = cdat[2 * x + 0]
          nrgba.set_nrgba(
            x,
            y,
            @color.NRGBA::new(ycol, ycol, ycol, cdat[2 * x + 1]),
          )
        }
      CB_TC8 =>
        if self.use_transparent {
          let pix = nrgba.pix
          let mut i = pix_offset
          let mut j = 0
          let (tr, tg, tb) = (
            self.transparent[1],
            self.transparent[3],
            self.transparent[5],
          )
          for x = 0; x < width; x = x + 1 {
            let r = cdat[j + 0]
            let g = cdat[j + 1]
            let b = cdat[j + 2]
            let mut a = b'\xff'
            if r == tr && g == tg && b == tb {
              a = b'\x00'
            }
            pix[i + 0] = r
            pix[i + 1] = g
            pix[i + 2] = b
            pix[i + 3] = a
            i += 4
            j += 3
          }
          pix_offset += nrgba.stride
        } else {
          let pix = rgba.pix
          let mut i = pix_offset
          let mut j = 0
          for x = 0; x < width; x = x + 1 {
            pix[i + 0] = cdat[j + 0]
            pix[i + 1] = cdat[j + 1]
            pix[i + 2] = cdat[j + 2]
            pix[i + 3] = 0xff
            i += 4
            j += 3
          }
          pix_offset += rgba.stride
        }
      CB_P1 =>
        for x = 0; x < width; x = x + 8 {
          let mut b = cdat[x / 8]
          for x2 = 0; x2 < 8 && x + x2 < width; x2 = x2 + 1 {
            let idx = b >> 7
            if paletted.palette.length() <= idx.to_int() {
              paletted.palette = paletted.palette[:idx.to_int() + 1]
            }
            paletted.set_color_index(x + x2, y, idx)
            b = b << 1
          }
        }
      CB_P2 =>
        for x = 0; x < width; x = x + 4 {
          let mut b = cdat[x / 4]
          for x2 = 0; x2 < 4 && x + x2 < width; x2 = x2 + 1 {
            let idx = b >> 6
            if paletted.palette.length() <= idx.to_int() {
              paletted.palette = paletted.palette[:idx.to_int() + 1]
            }
            paletted.set_color_index(x + x2, y, idx)
            b = b << 2
          }
        }
      CB_P4 =>
        for x = 0; x < width; x = x + 2 {
          let mut b = cdat[x / 2]
          for x2 = 0; x2 < 2 && x + x2 < width; x2 = x2 + 1 {
            let idx = b >> 4
            if paletted.palette.length() <= idx.to_int() {
              paletted.palette = paletted.palette[:idx.to_int() + 1]
            }
            paletted.set_color_index(x + x2, y, idx)
            b = b << 4
          }
        }
      CB_P8 => {
        if paletted.palette.length() != 256 {
          for x = 0; x < width; x = x + 1 {
            if paletted.palette.length() <= cdat[x].to_int() {
              paletted.palette = paletted.palette[:cdat[x].to_int() + 1]
            }
          }
        }
        let _ = slice_copy(paletted.pix[pix_offset:], cdat)
        pix_offset += paletted.stride
      }
      CB_TCA8 => {
        let _ = slice_copy(nrgba.pix[pix_offset:], cdat)
        pix_offset += nrgba.stride
      }
      CB_G16 =>
        if self.use_transparent {
          let ty = (self.transparent[0].to_uint() << 8) |
            self.transparent[1].to_uint()
          for x = 0; x < width; x = x + 1 {
            let ycol = (cdat[2 * x + 0].to_uint() << 8) |
              cdat[2 * x + 1].to_uint()
            let mut acol = 0xffffU
            if ycol == ty {
              acol = 0x0000U
            }
            nrgba64.set_nrgba64(
              x,
              y,
              @color.NRGBA64::new(ycol, ycol, ycol, acol),
            )
          }
        } else {
          for x = 0; x < width; x = x + 1 {
            let ycol = (cdat[2 * x + 0].to_uint() << 8) |
              cdat[2 * x + 1].to_uint()
            gray16.set_gray16(x, y, @color.Gray16::new(ycol))
          }
        }
      CB_GA16 =>
        for x = 0; x < width; x = x + 1 {
          let ycol = (cdat[4 * x + 0].to_uint() << 8) |
            cdat[4 * x + 1].to_uint()
          let acol = (cdat[4 * x + 2].to_uint() << 8) |
            cdat[4 * x + 3].to_uint()
          nrgba64.set_nrgba64(x, y, @color.NRGBA64::new(ycol, ycol, ycol, acol))
        }
      CB_TC16 =>
        if self.use_transparent {
          let tr = (self.transparent[0].to_uint() << 8) |
            self.transparent[1].to_uint()
          let tg = (self.transparent[2].to_uint() << 8) |
            self.transparent[3].to_uint()
          let tb = (self.transparent[4].to_uint() << 8) |
            self.transparent[5].to_uint()
          for x = 0; x < width; x = x + 1 {
            let rcol = (cdat[6 * x + 0].to_uint() << 8) |
              cdat[6 * x + 1].to_uint()
            let gcol = (cdat[6 * x + 2].to_uint() << 8) |
              cdat[6 * x + 3].to_uint()
            let bcol = (cdat[6 * x + 4].to_uint() << 8) |
              cdat[6 * x + 5].to_uint()
            let mut acol = 0xffffU
            if rcol == tr && gcol == tg && bcol == tb {
              acol = 0x0000U
            }
            nrgba64.set_nrgba64(
              x,
              y,
              @color.NRGBA64::new(rcol, gcol, bcol, acol),
            )
          }
        } else {
          for x = 0; x < width; x = x + 1 {
            let rcol = (cdat[6 * x + 0].to_uint() << 8) |
              cdat[6 * x + 1].to_uint()
            let gcol = (cdat[6 * x + 2].to_uint() << 8) |
              cdat[6 * x + 3].to_uint()
            let bcol = (cdat[6 * x + 4].to_uint() << 8) |
              cdat[6 * x + 5].to_uint()
            rgba64.set_rgba64(
              x,
              y,
              @color.RGBA64::new(rcol, gcol, bcol, 0xffff),
            )
          }
        }
      CB_TCA16 =>
        for x = 0; x < width; x = x + 1 {
          let rcol = (cdat[8 * x + 0].to_uint() << 8) |
            cdat[8 * x + 1].to_uint()
          let gcol = (cdat[8 * x + 2].to_uint() << 8) |
            cdat[8 * x + 3].to_uint()
          let bcol = (cdat[8 * x + 4].to_uint() << 8) |
            cdat[8 * x + 5].to_uint()
          let acol = (cdat[8 * x + 6].to_uint() << 8) |
            cdat[8 * x + 7].to_uint()
          nrgba64.set_nrgba64(x, y, @color.NRGBA64::new(rcol, gcol, bcol, acol))
        }
      _ => ()
    }

    // The current row for y is the previous row for y+1.
    let tmp = cr
    cr = pr
    pr = tmp
  }

  //
  (img, None)
}

///|
/// merge_pass_into merges a single pass into a full sized image.
fn merge_pass_into(
  dst : &@image.Image,
  src : &@image.Image,
  pass : Int
) -> Unit {
  let dst_pix = dst.raw_data()
  let stride = dst.get_stride()
  let rect = dst.bounds()
  let bytes_per_pixel = src.get_bytes_per_pixel()
  let src_pix = src.raw_data()
  let bounds = src.bounds()

  //
  let mut s = 0
  let p = interlacing[pass]
  for y = bounds.min.y; y < bounds.max.y; y = y + 1 {
    let d_base = (y * p.y_factor + p.y_offset - rect.min.y) * stride +
      (p.x_offset - rect.min.x) * bytes_per_pixel
    for x = bounds.min.x; x < bounds.max.x; x = x + 1 {
      let d = d_base + x * p.x_factor * bytes_per_pixel
      let _ = slice_copy(dst_pix[d:], src_pix[s:s + bytes_per_pixel])
      s += bytes_per_pixel
    }
  }
}

///|
fn parse_idat(self : Decoder, length : UInt) -> IOError? {
  self.idat_length = length
  let (img, err) = self.decode_idat()
  self.img = img
  if err != None {
    return err
  }
  self.verify_checksum()
}

///|
fn parse_iend(self : Decoder, length : UInt) -> IOError? {
  if length != 0 {
    return Some(format_error("bad IEND length"))
  }
  self.verify_checksum()
}

///|
fn parse_chunk(self : Decoder, config_only : Bool) -> IOError? {
  // Read the length and chunk type.
  let (_, err) = @io.read_full(self.r, self.tmp[:8])
  if err != None {
    return err
  }
  let mut length = be_uint32(self.tmp[:4])
  self.crc.reset()
  guard self.crc.write(self.tmp[4:8]) is (_, None)

  // Read the chunk data.
  let chunk = be_uint32(self.tmp[4:8])
  if chunk == be_uint32(Slice::new(b"IHDR".to_array())) {
    if self.stage != DS_START {
      return Some(chunk_order_error)
    }
    self.stage = DS_SEEN_IHDR
    return self.parse_ihdr(length)
  } else if chunk == be_uint32(Slice::new(b"PLTE".to_array())) {
    if self.stage != DS_SEEN_IHDR {
      return Some(chunk_order_error)
    }
    self.stage = DS_SEEN_PLTE
    return self.parse_plte(length)
  } else if chunk == be_uint32(Slice::new(b"tRNS".to_array())) {
    if cb_paletted(self.cb) {
      if self.stage != DS_SEEN_PLTE {
        return Some(chunk_order_error)
      }
    } else if cb_true_color(self.cb) {
      if self.stage != DS_SEEN_IHDR && self.stage != DS_SEEN_PLTE {
        return Some(chunk_order_error)
      }
    } else if self.stage != DS_SEEN_IHDR {
      return Some(chunk_order_error)
    }
    self.stage = DS_SEENT_RNS
    return self.parse_t_rns(length)
  } else if chunk == be_uint32(Slice::new(b"IDAT".to_array())) {
    if self.stage < DS_SEEN_IHDR ||
      self.stage > DS_SEEN_IDAT ||
      (self.stage == DS_SEEN_IHDR && cb_paletted(self.cb)) {
      return Some(chunk_order_error)
    }
    if self.stage == DS_SEEN_IDAT {
      // Ignore trailing zero-length or garbage IDAT chunks.
      //
      // This does not affect valid PNG images that contain multiple IDAT
      // chunks, since the first call to parse_idat below will consume all
      // consecutive IDAT chunks required for decoding the image.
    } else {
      self.stage = DS_SEEN_IDAT
      if config_only {
        return None
      }
      return self.parse_idat(length)
    }
  } else if chunk == be_uint32(Slice::new(b"IEND".to_array())) {
    if self.stage != DS_SEEN_IDAT {
      return Some(chunk_order_error)
    }
    self.stage = DS_SEEN_IEND
    return self.parse_iend(length)
  }

  //
  if length > 0x7fffffff {
    return Some(format_error("Bad chunk length: \{length}"))
  }
  // Ignore this chunk (of a known length).
  let ignored = Slice::new(Array::make(4096, b'\x00'))
  while length > 0 {
    let (n, err) = @io.read_full(
      self.r,
      ignored[:@math.minimum(ignored.length(), length.reinterpret_as_int())],
    )
    if err != None {
      return err
    }
    guard self.crc.write(ignored[:n]) is (_, None)
    length -= n.reinterpret_as_uint()
  }
  self.verify_checksum()
}

///|
fn verify_checksum(self : Decoder) -> IOError? {
  let (_, err) = @io.read_full(self.r, self.tmp[:4])
  if err != None {
    return err
  }
  if be_uint32(self.tmp[:4]) != self.crc.sum32() {
    return Some(format_error("invalid checksum"))
  }
  None
}

///|
fn check_header(self : Decoder) -> IOError? {
  let (_, err) = @io.read_full(self.r, self.tmp[:header.length()])
  if err != None {
    return err
  }
  if self.tmp[:header.length()].to_bytes() != header {
    return Some(format_error("not a PNG file"))
  }
  None
}

///|
/// decode reads a PNG image from r and returns it as an [image.Image].
/// The type of Image returned depends on the PNG contents.
pub fn decode(r : &@io.Reader) -> (&@image.Image, IOError?) {
  let d = Decoder::new(r)
  let mut err = d.check_header()
  if err != None {
    if err == Some(@io.eof) {
      err = Some(@io.err_unexpected_eof)
    }
    return (&@image.Image::new_empty(), err)
  }
  while d.stage != DS_SEEN_IEND {
    let mut err = d.parse_chunk(false)
    if err != None {
      if err == Some(@io.eof) {
        err = Some(@io.err_unexpected_eof)
      }
      return (&@image.Image::new_empty(), err)
    }
  }
  (d.img, None)
}

///|
/// decode_config returns the color model and dimensions of a PNG image without
/// decoding the entire image.
pub fn decode_config(r : &@io.Reader) -> (@image.Config, IOError?) {
  let d = Decoder::new(r)
  let mut err = d.check_header()
  if err != None {
    if err == Some(@io.eof) {
      err = Some(@io.err_unexpected_eof)
    }
    return (@image.Config::new_empty(), err)
  }

  //
  while true {
    let mut err = d.parse_chunk(true)
    if err != None {
      if err == Some(@io.eof) {
        err = Some(@io.err_unexpected_eof)
      }
      return (@image.Config::new_empty(), err)
    }
    if cb_paletted(d.cb) {
      if d.stage >= DS_SEENT_RNS {
        break
      }
    } else if d.stage >= DS_SEEN_IHDR {
      break
    }
  }
  let mut cm = @color.rgba_model
  match d.cb {
    CB_G1 | CB_G2 | CB_G4 | CB_G8 => cm = @color.gray_model
    CB_GA8 => cm = @color.nrgba_model
    CB_TC8 => cm = @color.rgba_model
    CB_P1 | CB_P2 | CB_P4 | CB_P8 => cm = d.palette
    CB_TCA8 => cm = @color.nrgba_model
    CB_G16 => cm = @color.gray16_model
    CB_GA16 => cm = @color.nrgba64_model
    CB_TC16 => cm = @color.rgba64_model
    CB_TCA16 => cm = @color.nrgba64_model
    _ => ()
  }

  //
  ({ color_model: cm, width: d.width, height: d.height }, None)
}

// func init {
// 	image.RegisterFormat("png", header, Decode, decode_config)
// }
