// This file is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/image/png/writer.go
// which has the copyright notice:
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// EncoderBuffer configures encoding PNG images.
struct EncoderBuffer {
  mut w : @io.Writer
  mut m : @image.Image
  mut cb : Int
  mut err : IOError?
  header : Slice[Byte] // [8]byte
  footer : Slice[Byte] // [4]byte
  tmp : Slice[Byte] // [4 * 256]byte
  cr : Array[Slice[Byte]] // [nFilter][]uint8
  pr : Slice[Byte] // []uint8
  zw : @zlib.Writer
  // zwLevel : Int  // zlib currently hard-coded to use BestSpeed algorithm.
  // mut bw : WriterSize // @bufio.Writer
  mut bw : @io.Buffer
}

fn EncoderBuffer::new(w : @io.Writer, m : @image.Image) -> EncoderBuffer {
  {
    w,
    m,
    cb: 0,
    err: None,
    header: Slice::new([0, 0, 0, 0, 0, 0, 0, 0]),
    footer: Slice::new([0, 0, 0, 0]),
    tmp: Slice::new(Array::make(4 * 256, b'\x00')),
    cr: [
      Slice::new([]),
      Slice::new([]),
      Slice::new([]),
      Slice::new([]),
      Slice::new([]),
    ],
    pr: Slice::new([]),
    zw: @zlib.Writer::new(), // TODO
    // bw: WriterSize::new(),
    bw: @io.Buffer::new(),
  }
}

// The absolute value of a byte interpreted as a signed int8.
fn abs8(d : Byte) -> Int {
  if d < 128 {
    return d.to_int()
  }
  256 - d.to_int()
}

fn be_put_uint32(b : Slice[Byte], value : UInt) -> Unit {
  b[3] = (value & 0xff).to_byte()
  b[2] = ((value >> 8) & 0xff).to_byte()
  b[1] = ((value >> 16) & 0xff).to_byte()
  b[0] = ((value >> 24) & 0xff).to_byte()
}

fn write_chunk(self : EncoderBuffer, b : Slice[Byte], name : Bytes) -> Unit {
  if self.err != None {
    return
  }
  let n = b.length().reinterpret_as_uint()
  if n.reinterpret_as_int() != b.length() {
    self.err = Some(
      unsupported_error("\{name} chunk is too large: \{b.length()}"),
    )
    return
  }
  be_put_uint32(self.header[:4], n)
  self.header[4] = name[0]
  self.header[5] = name[1]
  self.header[6] = name[2]
  self.header[7] = name[3]
  let crc = @crc32.new()
  guard let (_, None) = crc.write(self.header[4:8])
  guard let (_, None) = crc.write(b)
  be_put_uint32(self.footer[:4], crc.sum32())
  let (_, err) = self.w.write(self.header[:8])
  self.err = err
  if self.err != None {
    return
  }
  let (_, err) = self.w.write(b)
  self.err = err
  if self.err != None {
    return
  }
  let (_, err) = self.w.write(self.footer[:4])
  self.err = err
}

fn write_ihdr(self : EncoderBuffer) -> Unit {
  let b = self.m.bounds()
  be_put_uint32(self.tmp[0:4], b.dx().reinterpret_as_uint())
  be_put_uint32(self.tmp[4:8], b.dy().reinterpret_as_uint())
  // Set bit depth and color type.
  match self.cb {
    CB_G8 => {
      self.tmp[8] = 8
      self.tmp[9] = CT_GRAYSCALE.to_byte()
    }
    CB_TC8 => {
      self.tmp[8] = 8
      self.tmp[9] = CT_TRUE_COLOR.to_byte()
    }
    CB_P8 => {
      self.tmp[8] = 8
      self.tmp[9] = CT_PALETTED.to_byte()
    }
    CB_P4 => {
      self.tmp[8] = 4
      self.tmp[9] = CT_PALETTED.to_byte()
    }
    CB_P2 => {
      self.tmp[8] = 2
      self.tmp[9] = CT_PALETTED.to_byte()
    }
    CB_P1 => {
      self.tmp[8] = 1
      self.tmp[9] = CT_PALETTED.to_byte()
    }
    CB_TCA8 => {
      self.tmp[8] = 8
      self.tmp[9] = CT_TRUE_COLOR_ALPHA.to_byte()
    }
    CB_G16 => {
      self.tmp[8] = 16
      self.tmp[9] = CT_GRAYSCALE.to_byte()
    }
    CB_TC16 => {
      self.tmp[8] = 16
      self.tmp[9] = CT_TRUE_COLOR.to_byte()
    }
    CB_TCA16 => {
      self.tmp[8] = 16
      self.tmp[9] = CT_TRUE_COLOR_ALPHA.to_byte()
    }
  }
  self.tmp[10] = 0 // default compression method
  self.tmp[11] = 0 // default filter method
  self.tmp[12] = 0 // non-interlaced
  self.write_chunk(self.tmp[:13], b"IHDR")
}

fn write_plte_and_trns(self : EncoderBuffer, p : @color.Palette) -> Unit {
  if p.length() < 1 || p.length() > 256 {
    self.err = Some(format_error("bad palette length: \{p.length()}"))
    return
  }
  let mut last = -1
  for i, c in p._ {
    let c1 = @color.NRGBA::from(c)
    self.tmp[3 * i + 0] = c1.r
    self.tmp[3 * i + 1] = c1.g
    self.tmp[3 * i + 2] = c1.b
    if c1.a != 0xff {
      last = i
    }
    self.tmp[3 * 256 + i] = c1.a
  }
  self.write_chunk(self.tmp[:3 * p.length()], b"PLTE")
  if last != -1 {
    self.write_chunk(self.tmp[3 * 256:3 * 256 + 1 + last], b"tRNS")
  }
}

// An EncoderBuffer is an io.Writer that satisfies writes by writing PNG IDAT chunks,
// including an 8-byte header and 4-byte CRC checksum per Write call. Such calls
// should be relatively infrequent, since write_idats uses a [bufio.Writer].
//
// This method should only be called from write_idats (via write_image).
// No other code should treat an EncoderBuffer as an io.Writer.
pub fn write(self : EncoderBuffer, b : Slice[Byte]) -> (Int, IOError?) {
  self.write_chunk(b, b"IDAT")
  if self.err != None {
    return (0, self.err)
  }
  (b.length(), None)
}

// Chooses the filter to use for encoding the current row, and applies it.
// The return value is the index of the filter and also of the row in cr that has had it applied.
fn filter(cr : Array[Slice[Byte]], pr : Slice[Byte], bpp : Int) -> Byte {
  // We try all five filter types, and pick the one that minimizes the sum of absolute differences.
  // This is the same heuristic that libpng uses, although the filters are attempted in order of
  // estimated most likely to be minimal (ftUp, ftPaeth, ftNone, ftSub, ftAverage), rather than
  // in their enumeration order (ftNone, ftSub, ftUp, ftAverage, ftPaeth).
  let cdat0 = cr[0][1:]
  let cdat1 = cr[1][1:]
  let cdat2 = cr[2][1:]
  let cdat3 = cr[3][1:]
  let cdat4 = cr[4][1:]
  let pdat = pr[1:]
  let n = cdat0.length()

  // The up filter.
  let mut sum = 0
  for i = 0; i < n; i = i + 1 {
    cdat2[i] = cdat0[i] - pdat[i]
    sum += abs8(cdat2[i])
  }
  let mut best = sum
  let mut filter = FT_UP

  // The Paeth filter.
  sum = 0
  for i = 0; i < bpp; i = i + 1 {
    cdat4[i] = cdat0[i] - pdat[i]
    sum += abs8(cdat4[i])
  }
  for i = bpp; i < n; i = i + 1 {
    cdat4[i] = cdat0[i] - paeth(cdat0[i - bpp], pdat[i], pdat[i - bpp])
    sum += abs8(cdat4[i])
    if sum >= best {
      break
    }
  }
  if sum < best {
    best = sum
    filter = FT_PAETH
  }

  // The none filter.
  sum = 0
  for i = 0; i < n; i = i + 1 {
    sum += abs8(cdat0[i])
    if sum >= best {
      break
    }
  }
  if sum < best {
    best = sum
    filter = FT_NONE
  }

  // The sub filter.
  sum = 0
  for i = 0; i < bpp; i = i + 1 {
    cdat1[i] = cdat0[i]
    sum += abs8(cdat1[i])
  }
  for i = bpp; i < n; i = i + 1 {
    cdat1[i] = cdat0[i] - cdat0[i - bpp]
    sum += abs8(cdat1[i])
    if sum >= best {
      break
    }
  }
  if sum < best {
    best = sum
    filter = FT_SUB
  }

  // The average filter.
  sum = 0
  for i = 0; i < bpp; i = i + 1 {
    cdat3[i] = cdat0[i] - pdat[i] / 2
    sum += abs8(cdat3[i])
  }
  for i = bpp; i < n; i = i + 1 {
    cdat3[i] = cdat0[i] -
      ((cdat0[i - bpp].to_int() + pdat[i].to_int()) / 2).to_byte()
    sum += abs8(cdat3[i])
    if sum >= best {
      break
    }
  }
  if sum < best {
    filter = FT_AVERAGE
  }
  filter
}

fn write_image(
  self : EncoderBuffer,
  w : @io.Writer,
  m : @image.Image,
  cb : Int
  // level : Int
) -> IOError? {
  // 	if e.zw == nil || e.zwLevel != level {
  // 		zw, err := zlib.NewWriterLevel(w, level)
  // 		if err != None {
  // 			return err
  // 		}
  // 		e.zw = zw
  // 		e.zwLevel = level
  // 	} else {
  // 		e.zw.Reset(w)
  // 	}
  // 	defer e.zw.Close()

  // 	bitsPerPixel := 0

  // 	match cb {
  // 	CB_G8 => {
  // 		bitsPerPixel = 8
  // }
  // 	CB_TC8 => {
  // 		bitsPerPixel = 24
  // }
  // 	CB_P8 => {
  // 		bitsPerPixel = 8
  // }
  // 	CB_P4 => {
  // 		bitsPerPixel = 4
  // }
  // 	CB_P2 => {
  // 		bitsPerPixel = 2
  // }
  // 	CB_P1 => {
  // 		bitsPerPixel = 1
  // }
  // 	CB_TCA8 => {
  // 		bitsPerPixel = 32
  // }
  // 	CB_TC16 => {
  // 		bitsPerPixel = 48
  // }
  // 	CB_TCA16 => {
  // 		bitsPerPixel = 64
  // }
  // 	CB_G16 => {
  // 		bitsPerPixel = 16
  // 	}
  // }

  // 	// cr[*] and pr are the bytes for the current and previous row.
  // 	// cr[0] is unfiltered (or equivalently, filtered with the ftNone filter).
  // 	// cr[ft], for non-zero filter types ft, are buffers for transforming cr[0] under the
  // 	// other PNG filter types. These buffers are allocated once and re-used for each row.
  // 	// The +1 is for the per-row filter type, which is at cr[*][0].
  // 	b := m.bounds()
  // 	sz := 1 + (bitsPerPixel*b.Dx()+7)/8
  // 	for i := range e.cr {
  // 		if cap(e.cr[i]) < sz {
  // 			e.cr[i] = make([]uint8, sz)
  // 		} else {
  // 			e.cr[i] = e.cr[i][:sz]
  // 		}
  // 		e.cr[i][0] = uint8(i)
  // 	}
  // 	cr := e.cr
  // 	if cap(e.pr) < sz {
  // 		e.pr = make([]uint8, sz)
  // 	} else {
  // 		e.pr = e.pr[:sz]
  // 		clear(e.pr)
  // 	}
  // 	pr := e.pr

  // 	gray, _ := m.(*image.Gray)
  // 	rgba, _ := m.(*image.RGBA)
  // 	paletted, _ := m.(*image.Paletted)
  // 	nrgba, _ := m.(*image.NRGBA)

  // 	for y := b.Min.Y; y < b.Max.Y; y++ {
  // 		// Convert from colors to bytes.
  // 		i := 1
  // 		match cb {
  // 		CB_G8 => {
  // 			if gray != None {
  // 				offset := (y - b.Min.Y) * gray.Stride
  // 				copy(cr[0][1:], gray.Pix[offset:offset+b.Dx()])
  // 			} else {
  // 				for x := b.Min.X; x < b.Max.X; x++ {
  // 					c := color.GrayModel.Convert(m.At(x, y)).(color.Gray)
  // 					cr[0][i] = c.Y
  // 					i++
  // 				}
  // 			}
  // }
  // 		CB_TC8 => {
  // 			// We have previously verified that the alpha value is fully opaque.
  // 			cr0 := cr[0]
  // 			stride, pix := 0, []byte(nil)
  // 			if rgba != None {
  // 				stride, pix = rgba.Stride, rgba.Pix
  // 			} else if nrgba != None {
  // 				stride, pix = nrgba.Stride, nrgba.Pix
  // 			}
  // 			if stride != 0 {
  // 				j0 := (y - b.Min.Y) * stride
  // 				j1 := j0 + b.Dx()*4
  // 				for j := j0; j < j1; j += 4 {
  // 					cr0[i+0] = pix[j+0]
  // 					cr0[i+1] = pix[j+1]
  // 					cr0[i+2] = pix[j+2]
  // 					i += 3
  // 				}
  // 			} else {
  // 				for x := b.Min.X; x < b.Max.X; x++ {
  // 					r, g, b, _ := m.At(x, y).RGBA()
  // 					cr0[i+0] = uint8(r >> 8)
  // 					cr0[i+1] = uint8(g >> 8)
  // 					cr0[i+2] = uint8(b >> 8)
  // 					i += 3
  // 				}
  // 			}
  // }
  // 		CB_P8 => {
  // 			if paletted != None {
  // 				offset := (y - b.Min.Y) * paletted.Stride
  // 				copy(cr[0][1:], paletted.Pix[offset:offset+b.Dx()])
  // 			} else {
  // 				pi := m.(image.PalettedImage)
  // 				for x := b.Min.X; x < b.Max.X; x++ {
  // 					cr[0][i] = pi.ColorIndexAt(x, y)
  // 					i += 1
  // 				}
  // 			}
  // }
  // 		CB_P4 => { cbP2, cbP1:
  // 			pi := m.(image.PalettedImage)

  // 			var a uint8
  // 			var c int
  // 			pixelsPerByte := 8 / bitsPerPixel
  // 			for x := b.Min.X; x < b.Max.X; x++ {
  // 				a = a<<uint(bitsPerPixel) | pi.ColorIndexAt(x, y)
  // 				c++
  // 				if c == pixelsPerByte {
  // 					cr[0][i] = a
  // 					i += 1
  // 					a = 0
  // 					c = 0
  // 				}
  // 			}
  // 			if c != 0 {
  // 				for c != pixelsPerByte {
  // 					a = a << uint(bitsPerPixel)
  // 					c++
  // 				}
  // 				cr[0][i] = a
  // 			}
  // }
  // 		CB_TCA8 => {
  // 			if nrgba != None {
  // 				offset := (y - b.Min.Y) * nrgba.Stride
  // 				copy(cr[0][1:], nrgba.Pix[offset:offset+b.Dx()*4])
  // 			} else if rgba != None {
  // 				dst := cr[0][1:]
  // 				src := rgba.Pix[rgba.PixOffset(b.Min.X, y):rgba.PixOffset(b.Max.X, y)]
  // 				for ; len(src) >= 4; dst, src = dst[4:], src[4:] {
  // 					d := (*[4]byte)(dst)
  // 					s := (*[4]byte)(src)
  // 					if s[3] == 0x00 {
  // 						d[0] = 0
  // 						d[1] = 0
  // 						d[2] = 0
  // 						d[3] = 0
  // 					} else if s[3] == 0xff {
  // 						copy(d[:], s[:])
  // 					} else {
  // 						// This code does the same as color.NRGBAModel.Convert(
  // 						// rgba.At(x, y)).(color.NRGBA) but with no extra memory
  // 						// allocations or interface/function call overhead.
  // 						//
  // 						// The multiplier m combines 0x101 (which converts
  // 						// 8-bit color to 16-bit color) and 0xffff (which, when
  // 						// combined with the division-by-a, converts from
  // 						// alpha-premultiplied to non-alpha-premultiplied).
  // 						const m = 0x101 * 0xffff
  // 						a := uint32(s[3]) * 0x101
  // 						d[0] = uint8((uint32(s[0]) * m / a) >> 8)
  // 						d[1] = uint8((uint32(s[1]) * m / a) >> 8)
  // 						d[2] = uint8((uint32(s[2]) * m / a) >> 8)
  // 						d[3] = s[3]
  // 					}
  // 				}
  // 			} else {
  // 				// Convert from image.Image (which is alpha-premultiplied) to PNG's non-alpha-premultiplied.
  // 				for x := b.Min.X; x < b.Max.X; x++ {
  // 					c := color.NRGBAModel.Convert(m.At(x, y)).(color.NRGBA)
  // 					cr[0][i+0] = c.R
  // 					cr[0][i+1] = c.G
  // 					cr[0][i+2] = c.B
  // 					cr[0][i+3] = c.A
  // 					i += 4
  // 				}
  // 			}
  // }
  // 		CB_G16 => {
  // 			for x := b.Min.X; x < b.Max.X; x++ {
  // 				c := color.Gray16Model.Convert(m.At(x, y)).(color.Gray16)
  // 				cr[0][i+0] = uint8(c.Y >> 8)
  // 				cr[0][i+1] = uint8(c.Y)
  // 				i += 2
  // 			}
  // }
  // 		CB_TC16 => {
  // 			// We have previously verified that the alpha value is fully opaque.
  // 			for x := b.Min.X; x < b.Max.X; x++ {
  // 				r, g, b, _ := m.At(x, y).RGBA()
  // 				cr[0][i+0] = uint8(r >> 8)
  // 				cr[0][i+1] = uint8(r)
  // 				cr[0][i+2] = uint8(g >> 8)
  // 				cr[0][i+3] = uint8(g)
  // 				cr[0][i+4] = uint8(b >> 8)
  // 				cr[0][i+5] = uint8(b)
  // 				i += 6
  // 			}
  // }
  // 		CB_TCA16 => {
  // 			// Convert from image.Image (which is alpha-premultiplied) to PNG's non-alpha-premultiplied.
  // 			for x := b.Min.X; x < b.Max.X; x++ {
  // 				c := color.NRGBA64Model.Convert(m.At(x, y)).(color.NRGBA64)
  // 				cr[0][i+0] = uint8(c.R >> 8)
  // 				cr[0][i+1] = uint8(c.R)
  // 				cr[0][i+2] = uint8(c.G >> 8)
  // 				cr[0][i+3] = uint8(c.G)
  // 				cr[0][i+4] = uint8(c.B >> 8)
  // 				cr[0][i+5] = uint8(c.B)
  // 				cr[0][i+6] = uint8(c.A >> 8)
  // 				cr[0][i+7] = uint8(c.A)
  // 				i += 8
  // 			}
  // 		}
  // }

  // 		// Apply the filter.
  // 		// Skip filter for NoCompression and paletted images (cbP8) as
  // 		// "filters are rarely useful on palette images" and will result
  // 		// in larger files (see http://www.libpng.org/pub/png/book/chapter09.html).
  // 		f := FT_NONE
  // 		if level != zlib.NoCompression && cb != cbP8 && cb != cbP4 && cb != cbP2 && cb != cbP1 {
  // 			// Since we skip paletted images we don't have to worry about
  // 			// bitsPerPixel not being a multiple of 8
  // 			bpp := bitsPerPixel / 8
  // 			f = filter(&cr, pr, bpp)
  // 		}

  // 		// Write the compressed bytes.
  // 		if _, err := e.zw.write(cr[f]); err != None {
  // 			return err
  // 		}

  // 		// The current row for y is the previous row for y+1.
  // 		pr, cr[0] = cr[0], pr
  // 	}
  None
}

// Write the actual image data to one or more IDAT chunks.
fn write_idats(self : EncoderBuffer) -> Unit {
  if self.err != None {
    return
  }
  // if self.bw == None {
  // self.bw = WriterSize::new(self, 1 << 15)
  self.bw = @io.Buffer::new()
  // } else {
  // 	self.bw.Reset(e)
  // }
  self.err = self.write_image(self.bw, self.m, self.cb)
  // if self.err != None {
  //   return
  // }
  // self.err = self.bw.flush()
}

fn write_iend(self : EncoderBuffer) -> Unit {
  self.write_chunk(Slice::new([]), b"IEND")
}

// Encode writes the Image m to w in PNG format. Any Image may be
// encoded, but images that are not [image.NRGBA] might be encoded lossily.
pub fn encode(w : @io.Writer, m : @image.Image) -> IOError? {
  let e = EncoderBuffer::new(w, m)
  e.enc(w, m)
}

// enc writes the Image m to w in PNG format.
pub fn enc(self : EncoderBuffer, w : @io.Writer, m : @image.Image) -> IOError? {
  // Obviously, negative widths and heights are invalid. Furthermore, the PNG
  // spec section 11.2.2 says that zero is invalid. Excessively large images are
  // also rejected.
  let mw = m.bounds().dx().to_int64()
  let mh = m.bounds().dy().to_int64()
  if mw <= 0 || mh <= 0 || mw >= (1L << 32) || mh >= (1L << 32) {
    return Some(format_error("invalid image size: \{mw}x\{mh}"))
  }

  //
  self.w = w
  self.m = m

  //
  let mut pal = m.color_model().get_palette()
  match m.color_model().name() {
    "Paletted" =>
      if pal.length() <= 2 {
        self.cb = CB_P1
      } else if pal.length() <= 4 {
        self.cb = CB_P2
      } else if pal.length() <= 16 {
        self.cb = CB_P4
      } else {
        self.cb = CB_P8
      }
    "Gray" => self.cb = CB_G8
    "Gray16" => self.cb = CB_G16
    "RGBA" | "NRGBA" | "Alpha" =>
      if m.opaque() {
        self.cb = CB_TC8
      } else {
        self.cb = CB_TCA8
      }
    _ => if m.opaque() { self.cb = CB_TC16 } else { self.cb = CB_TCA16 }
  }

  //
  let (_, err) = @io.write_bytes(w, HEADER)
  self.write_ihdr()
  if pal != None {
    self.write_plte_and_trns(pal)
  }
  self.write_idats()
  self.write_iend()
  self.err
}
